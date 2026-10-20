import Foundation

/// A deposit pool and what the rollup holds for it.
struct ShieldedPoolStatus: Hashable, Sendable, Identifiable {
    var id: String { pool.pubkeyHash }
    let pool: DepositPool
    /// `nil` until the rollup has credited the pool.
    let balanceMutez: UInt64?
    var balance: Decimal? { balanceMutez.map { Decimal($0) / Mutez.perTez } }
}

/// What a shield is doing right now.
enum ShieldProgress: Hashable, Sendable {
    case preparing
    /// Building the address's 65536 signing keys, first time only; the fraction done.
    case buildingKeys(Double)
    case depositing
    case waitingForLayer1
    case waitingForRollup
    case proving
    case submitting

    var text: String {
        switch self {
        case .preparing: "Checking the rollup…"
        case .buildingKeys(let fraction): "Creating your shielded address (\(Int(fraction * 100))%)…"
        case .depositing: "Sending the deposit on Tezos…"
        case .waitingForLayer1: "Waiting for the Tezos block…"
        case .waitingForRollup: "Waiting for the rollup to credit the deposit…"
        case .proving: "Proving the shield (about a minute)…"
        case .submitting: "Handing the shield to the operator…"
        }
    }
}

/// The dashboard's view of the shielded wallet after a scan.
struct ShieldedSnapshot: Sendable {
    var wallet: ShieldedWallet?
    var pools: [ShieldedPoolStatus]
    var row: AssetBalance
}

/// A deposit estimate together with the pool it is for and the context it is valid in (S31).
struct ShieldEstimate: Sendable {
    let estimate: TransferEstimate
    let context: WalletViewModel.BridgeContext
    let amount: Decimal
    let pool: DepositPool
    /// What the rollup charged at estimate time, and the producer's fixed fee, in mutez.
    let rollupFeeMutez: UInt64
    let producerFeeMutez: UInt64
    /// What the note will hold if the rollup fee is still the same when the pool is shielded.
    var shieldedAmount: Decimal { max(amount - Decimal(rollupFeeMutez + producerFeeMutez) / Mutez.perTez, 0) }
}

/// What a finished shield left behind.
struct ShieldReceipt: Hashable, Sendable {
    let pool: String
    let depositHash: String?
    let depositLevel: Int?
    /// The note's value, in mutez, after the rollup and producer fees.
    let shieldedMutez: UInt64
    let rollupFeeMutez: UInt64
    let producerFeeMutez: UInt64
    let submissionID: String
    let operationHash: String?
    let cm: String
    var shielded: Decimal { Decimal(shieldedMutez) / Mutez.perTez }
}

// MARK: - Shielded tez (TzEL)

extension WalletViewModel {
    /// The Shield item: shielded transactions on with known services, and an account we can sign for.
    var canShield: Bool {
        guard network.canShield, let wallet = selectedWallet else { return false }
        return wallet.keyKind.canSign && !wallet.address.isContract
    }

    /// Whether the operator's access token is on file for `base`'s shielded wallets.
    func shieldedOperatorTokenIsSet(for base: Network) -> Bool {
        guard base.shielded != nil else { return false }
        return ((try? shieldedStore(for: base.chain).operatorToken())??.isEmpty == false)
    }

    /// Keeps the operator's token in `base`'s shielded wallet file. Empty text removes it.
    func setShieldedOperatorToken(_ token: String, for base: Network) throws {
        guard base.shielded != nil else { throw ShieldedError.notAvailable(base.name) }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try shieldedStore(for: base.chain).setOperatorToken(trimmed.isEmpty ? nil : trimmed)
    }

    /// A version 1 file held one shielded wallet for the whole network. It becomes the wallet
    /// of the account that funded its first deposit (asked of TzKT), or of the selected
    /// account when that cannot be told, so nothing shielded is lost.
    func adoptLegacyShieldedWallet() async {
        guard network.canShield, let selected = selectedWallet else { return }
        let store = shieldedStore(for: network.chain)
        guard let legacy = try? store.legacyWallet() else { return }
        var owner = selected.address
        if let hash = legacy.pools.compactMap(\.operationHash).first, let tzkt = network.tzktURL,
           let sender = try? await TzKTService(baseURL: tzkt).sender(ofOperation: hash), wallets.contains(where: { $0.address == sender }) {
            owner = sender
        }
        try? store.adoptLegacyWallet(for: owner)
    }

    /// The store of `chain`'s shielded wallet in the current directory, made once.
    func shieldedStore(for chain: String) -> any ShieldedWalletStore {
        let key = "\(walletDirectory?.standardizedFileURL.path ?? "")|\(chain)"
        if let store = shieldedStores[key] { return store }
        let store = shieldedStoreFactory(walletDirectory, chain)
        shieldedStores[key] = store
        return store
    }

    private var shieldedConfig: ShieldedConfig {
        get throws {
            guard let config = network.shielded, network.shieldedEnabled else { throw ShieldedError.notAvailable(network.name) }
            return config
        }
    }

    // MARK: Scan

    /// Reads what the rollup holds for the wallet: new notes since the last scan (decrypted in
    /// the bridge with the viewing keys), nullifiers that spend ours, and the deposit pools'
    /// balances. Saves the advanced cursors. A rollup that cannot be reached blanks the row.
    nonisolated static func scanShielded(store: any ShieldedWalletStore, account: Address, rollup: any ShieldedRollup, bridge: TaquitoBridge) async -> ShieldedSnapshot {
        func row(_ wallet: ShieldedWallet?, pools: [ShieldedPoolStatus], unavailable: String? = nil) -> AssetBalance {
            var details: [AssetBalance.Detail] = []
            let pooled = pools.compactMap(\.balanceMutez).reduce(0, +)
            if pooled > 0 { details.append(AssetBalance.Detail(id: "pooled", label: "In deposit pools, not yet shielded", amount: Decimal(pooled) / Mutez.perTez)) }
            return AssetBalance(id: "shielded", kind: .shielded, name: "Shielded", symbol: "tz", amount: wallet?.balance ?? 0, details: details, unavailable: unavailable)
        }
        var wallet: ShieldedWallet?
        do {
            wallet = try store.load(account: account)
        } catch {
            return ShieldedSnapshot(wallet: nil, pools: [], row: row(nil, pools: [], unavailable: "Shielded wallet unreadable: \(error.localizedDescription)"))
        }
        guard var current = wallet else { return ShieldedSnapshot(wallet: nil, pools: [], row: row(nil, pools: [])) }
        do {
            let before = current
            let head = try await rollup.head()
            // Notes: fetched a batch at a time (the bridge takes at most 2 MB of arguments).
            let size = try await rollup.treeSize(at: head.hash)
            if !current.addresses.isEmpty, current.scanned < size {
                let account = try await bridge.call("tzelAccount", [current.masterSk])
                let accountJSON = try Self.json(account)
                let addressesJSON = try Self.json(.array(current.addresses.map { .object($0.bridgeRecord.mapValues { JSONValue(bridged: $0) }) }))
                var from = current.scanned
                while from < size {
                    try Task.checkCancellation()
                    let to = min(from + 200, size)
                    let batch = try await Self.fetchNotes(rollup: rollup, block: head.hash, range: from..<to)
                    if !batch.isEmpty {
                        let found = try await bridge.call("tzelScan", [accountJSON, addressesJSON, try Self.json(.array(batch.map { .object(["index": .number(Double($0.index)), "bytes": .string($0.hex)]) }))])
                        for note in found.arrayValue ?? [] {
                            guard let index = note["index"]?.intValue, let cm = note["cm"]?.stringValue, let rseed = note["rseed"]?.stringValue,
                                  let nullifier = note["nullifier"]?.stringValue, let value = note["v"]?.stringValue, let addressIndex = note["addressIndex"]?.intValue
                            else { throw ShieldedError.badReply("scan result") }
                            if !current.notes.contains(where: { $0.index == index }) {
                                current.notes.append(ShieldedNote(index: index, cm: cm, rseed: rseed, nullifier: nullifier, valueMutez: value, addressIndex: addressIndex))
                            }
                        }
                    }
                    from = to
                    current.scanned = to
                }
            } else if current.addresses.isEmpty {
                current.scanned = size   // nothing before the first address can be ours
            }
            // Nullifiers: any of ours seen means that note is spent.
            let nullifiers = try await rollup.nullifierCount(at: head.hash)
            if current.nullifiersSeen < nullifiers, !current.notes.isEmpty {
                let unspent = Set(current.notes.filter { !$0.spent }.map(\.nullifier))
                for i in current.nullifiersSeen..<nullifiers {
                    let seen = try await rollup.nullifier(at: head.hash, index: i)
                    if unspent.contains(seen), let at = current.notes.firstIndex(where: { $0.nullifier == seen }) { current.notes[at].spent = true }
                }
            }
            current.nullifiersSeen = nullifiers
            // Pools: what the rollup holds; a pool drained by a shield whose note we have seen is done.
            var statuses: [ShieldedPoolStatus] = []
            let seenCms = Set(current.notes.map(\.cm))
            for pool in current.pools {
                let balance = try await rollup.poolBalance(at: head.hash, pubkeyHash: pool.pubkeyHash)
                let drained = (balance ?? 0) == 0
                if drained, let cm = pool.shieldedCm, seenCms.contains(cm) { continue }
                if drained, pool.operationHash == nil, pool.created < Date().addingTimeInterval(-86_400) { continue }
                statuses.append(ShieldedPoolStatus(pool: pool, balanceMutez: balance))
            }
            current.pools = statuses.map(\.pool)
            if current != before { try store.save(current, account: account) }
            return ShieldedSnapshot(wallet: current, pools: statuses, row: row(current, pools: statuses))
        } catch {
            let statuses = current.pools.map { ShieldedPoolStatus(pool: $0, balanceMutez: nil) }
            return ShieldedSnapshot(wallet: current, pools: statuses, row: row(current, pools: statuses, unavailable: "Shielded balance unavailable: \(error.localizedDescription)"))
        }
    }

    private struct FetchedNote: Sendable { let index: Int; let hex: String }

    /// The published notes in `range`, a few at a time, in order.
    private nonisolated static func fetchNotes(rollup: any ShieldedRollup, block: String, range: Range<Int>) async throws -> [FetchedNote] {
        try await withThrowingTaskGroup(of: FetchedNote?.self) { group in
            var results: [FetchedNote] = []
            var next = range.lowerBound
            func add() {
                let index = next
                next += 1
                group.addTask {
                    guard let bytes = try await rollup.publishedNote(at: block, index: index) else { return nil }
                    guard bytes.count == RollupState.publishedNoteBytes else { throw ShieldedError.badReply("note \(index) is \(bytes.count) bytes") }
                    return FetchedNote(index: index, hex: Hex.encode(bytes))
                }
            }
            for _ in 0..<min(8, range.count) { add() }
            while let note = try await group.next() {
                if let note { results.append(note) }
                if next < range.upperBound { add() }
            }
            return results.sorted { $0.index < $1.index }
        }
    }

    nonisolated static func json(_ value: JSONValue) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value.foundationObject, options: [.fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Wallet and address

    /// The network's shielded wallet with its first address ready to receive: made on first use
    /// (a random master key), the address's signing tree built natively (seconds) and kept.
    private func ensureShieldedWallet(config: ShieldedConfig, account: Address) async throws -> ShieldedWallet {
        let store = shieldedStore(for: network.chain)
        var wallet = try store.load(account: account) ?? ShieldedWallet.make(chain: network.chain)
        if wallet.addresses.isEmpty {
            let keys = try await addressKeys(of: wallet, index: 0)
            let leaves = try await buildLeaves(askJ: keys.askJ, pubSeed: keys.pubSeed)
            try store.saveLeaves(leaves, account: account, addressIndex: 0)
            let root = XMSSAuthTree.root(pubSeed: keys.pubSeedBytes, leaves: leaves)
            wallet.addresses.append(ShieldedAddress(index: 0, dJ: keys.dJ, authRoot: Hex.encode(root), pubSeed: keys.pubSeed, nkTag: keys.nkTag, ekV: keys.ekV, ekD: keys.ekD, nextKeyIndex: 0))
            try store.save(wallet, account: account)
        } else if try store.load(account: account) == nil {
            try store.save(wallet, account: account)
        }
        shieldedWallet = wallet
        return wallet
    }

    private struct AddressKeys {
        let dJ, nkTag, ekV, ekD, askJ, pubSeed: String
        var pubSeedBytes: [UInt8] { Hex.decode(pubSeed) ?? [] }
        var askJBytes: [UInt8] { Hex.decode(askJ) ?? [] }
    }

    private func addressKeys(of wallet: ShieldedWallet, index: Int) async throws -> AddressKeys {
        let account = try await shieldedBridge.call("tzelAccount", [wallet.masterSk])
        let keys = try await shieldedBridge.call("tzelAddressKeys", [try Self.json(account), index])
        guard let dJ = keys["dJ"]?.stringValue, let nkTag = keys["nkTag"]?.stringValue, let ekV = keys["ekV"]?.stringValue, let ekD = keys["ekD"]?.stringValue,
              let askJ = keys["askJ"]?.stringValue, let pubSeed = keys["pubSeed"]?.stringValue, Hex.decode(askJ)?.count == 32, Hex.decode(pubSeed)?.count == 32
        else { throw ShieldedError.badReply("address keys") }
        return AddressKeys(dJ: dJ, nkTag: nkTag, ekV: ekV, ekD: ekD, askJ: askJ, pubSeed: pubSeed)
    }

    /// Builds the 65536 leaves off the main actor, reporting progress to the sheet.
    private func buildLeaves(askJ: String, pubSeed: String) async throws -> [UInt8] {
        guard let ask = Hex.decode(askJ), let seed = Hex.decode(pubSeed), ask.count == 32, seed.count == 32 else { throw ShieldedError.badReply("signing seed") }
        shieldProgress = .buildingKeys(0)
        let reporter = ProgressReporter { [weak self] fraction in Task { @MainActor in self?.shieldProgress = .buildingKeys(fraction) } }
        return await Task.detached(priority: .userInitiated) {
            XMSSAuthTree.buildLeaves(askJ: ask, pubSeed: seed) { done in reporter.report(Double(done) / Double(XMSSAuthTree.size)) }
        }.value
    }

    private final class ProgressReporter: @unchecked Sendable {
        private let lock = NSLock()
        private var last = -1.0
        private let onChange: @Sendable (Double) -> Void
        init(_ onChange: @escaping @Sendable (Double) -> Void) { self.onChange = onChange }
        /// At most one report per percent.
        func report(_ fraction: Double) {
            let step = (fraction * 100).rounded(.down)
            let changed: Bool = lock.withLock { if step > last { last = step; return true } else { return false } }
            if changed { onChange(fraction) }
        }
    }

    /// The leaves of an address's signing tree from the store, rebuilt from the master key when
    /// the file is missing (it is not backed up). The root must be the address's.
    private func leaves(of address: ShieldedAddress, in wallet: ShieldedWallet, account: Address) async throws -> [UInt8] {
        let store = shieldedStore(for: network.chain)
        guard let pubSeed = Hex.decode(address.pubSeed) else { throw ShieldedError.treeMissing(address.index) }
        if let leaves = try store.loadLeaves(account: account, addressIndex: address.index), Hex.encode(XMSSAuthTree.root(pubSeed: pubSeed, leaves: leaves)) == address.authRoot { return leaves }
        let keys = try await addressKeys(of: wallet, index: address.index)
        guard keys.pubSeed == address.pubSeed else { throw ShieldedError.treeMissing(address.index) }
        let leaves = try await buildLeaves(askJ: keys.askJ, pubSeed: keys.pubSeed)
        guard Hex.encode(XMSSAuthTree.root(pubSeed: pubSeed, leaves: leaves)) == address.authRoot else { throw ShieldedError.treeMissing(address.index) }
        try store.saveLeaves(leaves, account: account, addressIndex: address.index)
        return leaves
    }

    // MARK: Deposit

    /// Everything before money moves: the rollup node serves the expected rollup, is configured
    /// and names our ticketer; the wallet and its address exist; a pool is reserved for the next
    /// deposit (an unfunded one is reused). Nothing is sent.
    func prepareShield() async throws -> DepositPool {
        let config = try shieldedConfig
        guard let account = selectedWallet?.address else { throw WalletError.emptyAlias }
        let context = bridgeContext
        shieldProgress = .preparing
        defer { shieldProgress = nil }
        let rollup = shieldedRollupFactory(config)
        let served = try await rollup.smartRollupAddress()
        guard served == config.rollupAddress else { throw ShieldedError.rollupMismatch(served: served, expected: config.rollupAddress) }
        let head = try await rollup.head()
        guard try await rollup.verifierConfigured(at: head.hash) else { throw ShieldedError.rollupNotConfigured("its verifier is not installed") }
        let ticketer = try await rollup.bridgeTicketer(at: head.hash)
        guard ticketer == config.ticketer.value else { throw ShieldedError.ticketerMismatch(configured: ticketer ?? "unset", expected: config.ticketer.value) }
        let authDomain = try await rollup.authDomain(at: head.hash)
        var wallet = try await ensureShieldedWallet(config: config, account: account)
        guard bridgeContext == context else { throw WalletError.contextChanged }
        if let unfunded = wallet.pools.first(where: { $0.operationHash == nil && $0.authDomain == authDomain }) { return unfunded }
        guard let address = wallet.addresses.first else { throw ShieldedError.treeMissing(0) }
        let nonce = wallet.depositNonce
        wallet.depositNonce += 1
        let made = try await shieldedBridge.call("tzelDepositPool", [wallet.masterSk, address.index, String(nonce), authDomain, address.authRoot, address.pubSeed])
        guard let pubkeyHash = made["pubkeyHash"]?.stringValue, let blind = made["blind"]?.stringValue, Hex.decode(pubkeyHash)?.count == 32 else { throw ShieldedError.badReply("deposit pool") }
        let pool = DepositPool(pubkeyHash: pubkeyHash, blind: blind, addressIndex: address.index, authDomain: authDomain, depositedMutez: "0", operationHash: nil, shieldedCm: nil, created: Date())
        wallet.pools.append(pool)
        try shieldedStore(for: network.chain).save(wallet, account: account)   // the pool is on file before any tez go to it
        shieldedWallet = wallet
        return pool
    }

    /// The layer 1 fee for depositing `amount` into `pool`, and the rollup's fee of the moment.
    func estimateShield(amount: Decimal, pool: DepositPool) async throws -> ShieldEstimate {
        let config = try shieldedConfig
        guard let wallet = selectedWallet, let context = bridgeContext else { throw WalletError.emptyAlias }
        guard amount > 0, Mutez.isValid(Mutez.fromTez(amount)) else { throw SendViewModel.SendError.invalidAmount }
        let chain = currentChain
        let rollup = shieldedRollupFactory(config)
        let deposit = ShieldDeposit(ticketer: config.ticketer, rollup: config.rollupAddress, pubkeyHash: pool.pubkeyHash, amount: amount)
        async let estimate = chain.estimateShieldDeposit(from: wallet, deposit: deposit)
        async let fee = rollup.requiredTxFee(at: rollup.head())
        let result = ShieldEstimate(estimate: try await estimate, context: context, amount: amount, pool: pool, rollupFeeMutez: try await fee, producerFeeMutez: config.producerFeeMutez)
        guard bridgeContext == context else { throw WalletError.contextChanged }
        return result
    }

    /// Shields `approved.amount` tez from the selected account: the deposit to the ticketer with
    /// the approved limits (S14), the layer 1 block, then `shieldPool` once the rollup has
    /// credited the pool. Refused up front without the operator token, so no tez are parked in
    /// a pool that cannot be shielded. A deposit that lands but whose shield fails leaves the
    /// pool listed in the sheet to be shielded again.
    func shieldTez(approved: ShieldEstimate, passphrase: String?) async throws -> ShieldReceipt {
        let config = try shieldedConfig
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        guard let limits = approved.estimate.limits else { throw WalletError.notEstimated }
        guard approved.context == bridgeContext, canShield else { throw WalletError.contextChanged }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        let store = shieldedStore(for: network.chain)
        guard let token = try store.operatorToken(), !token.isEmpty else { throw ShieldedError.operatorTokenMissing }
        guard var shielded = try store.load(account: wallet.address) else { throw ShieldedError.poolUnknown(approved.pool.pubkeyHash) }
        guard let at = shielded.pools.firstIndex(where: { $0.pubkeyHash == approved.pool.pubkeyHash }) else { throw ShieldedError.poolUnknown(approved.pool.pubkeyHash) }
        let amountMutez = Mutez.fromTez(approved.amount)
        guard let added = UInt64(amountMutez), added + config.producerFeeMutez > 0 else { throw SendViewModel.SendError.invalidAmount }

        shieldProgress = .depositing
        defer { shieldProgress = nil }
        let chain = currentChain
        let deposit = ShieldDeposit(ticketer: config.ticketer, rollup: config.rollupAddress, pubkeyHash: approved.pool.pubkeyHash, amount: approved.amount)
        let sent = try await chain.sendShieldDeposit(from: wallet, signer: signer, deposit: deposit, limits: limits)
        // On file before the block is waited for: the pool is funded (or about to be) by this operation.
        shielded.pools[at].operationHash = sent.hash
        shielded.pools[at].depositedMutez = String((UInt64(shielded.pools[at].depositedMutez) ?? 0) + added)
        try store.save(shielded, account: wallet.address)
        shieldedWallet = shielded
        shieldProgress = .waitingForLayer1
        let level: Int
        do {
            level = try await chain.waitForConfirmation(of: sent.hash)
        } catch where !sent.injected {
            throw WalletError.outcomeUnknown(sent.hash)
        }
        let receipt = try await shieldPool(approved.pool.pubkeyHash, depositHash: sent.hash, depositLevel: level)
        return receipt
    }

    // MARK: Shield

    /// Drains deposit pool `pubkeyHash` into a note of ours: waits for the rollup to show the
    /// pool's balance, takes the rollup's fee of the moment and the producer's fee off it,
    /// reserves the address's next WOTS+ key (on file before it signs), builds the two output
    /// notes, the signature and the witness in the bridge, has the proving service prove it and
    /// the operator deliver it, then records the note's commitment against the pool.
    func shieldPool(_ pubkeyHash: String, depositHash: String? = nil, depositLevel: Int? = nil) async throws -> ShieldReceipt {
        let config = try shieldedConfig
        guard let account = selectedWallet?.address else { throw WalletError.emptyAlias }
        let context = bridgeContext
        let store = shieldedStore(for: network.chain)
        guard let token = try store.operatorToken(), !token.isEmpty else { throw ShieldedError.operatorTokenMissing }
        guard var wallet = try store.load(account: account) else { throw ShieldedError.poolUnknown(pubkeyHash) }
        guard let poolAt = wallet.pools.firstIndex(where: { $0.pubkeyHash == pubkeyHash }) else { throw ShieldedError.poolUnknown(pubkeyHash) }
        let pool = wallet.pools[poolAt]
        guard let addressAt = wallet.addresses.firstIndex(where: { $0.index == pool.addressIndex }) else { throw ShieldedError.treeMissing(pool.addressIndex) }
        let rollup = shieldedRollupFactory(config)
        shieldProgress = .waitingForRollup
        defer { shieldProgress = nil }

        // The rollup sees the layer 1 deposit a level or two after the block.
        var head = try await rollup.head()
        var balance = try await rollup.poolBalance(at: head.hash, pubkeyHash: pubkeyHash) ?? 0
        var polls = 0
        while balance == 0, polls < shieldedCreditPolls {
            try await Task.sleep(for: shieldedPollInterval)
            polls += 1
            head = try await rollup.head()
            balance = try await rollup.poolBalance(at: head.hash, pubkeyHash: pubkeyHash) ?? 0
        }
        guard balance > 0 else { throw ShieldedError.poolNotCredited(pubkeyHash) }
        let fee = try await rollup.requiredTxFee(at: head)
        let producerFee = config.producerFeeMutez
        guard balance > fee + producerFee else { throw ShieldedError.poolTooSmall(balance: balance, fees: fee + producerFee) }
        let value = balance - fee - producerFee
        let authDomain = try await rollup.authDomain(at: head.hash)
        guard authDomain == pool.authDomain else { throw ShieldedError.rollupNotConfigured("its authentication domain changed since the deposit") }
        guard bridgeContext == context else { throw WalletError.contextChanged }

        // One signature per key index, ever: the index is spent on disk before it is used.
        let address = wallet.addresses[addressAt]
        let keyIdx = address.nextKeyIndex
        guard keyIdx < XMSSAuthTree.size else { throw ShieldedError.keysExhausted(address.index) }
        wallet.addresses[addressAt].nextKeyIndex = keyIdx + 1
        try store.save(wallet, account: account)
        shieldedWallet = wallet

        let leaves = try await leaves(of: address, in: wallet, account: account)
        guard let pubSeed = Hex.decode(address.pubSeed) else { throw ShieldedError.treeMissing(address.index) }
        let path = XMSSAuthTree.path(levels: XMSSAuthTree.levels(pubSeed: pubSeed, leaves: leaves), index: keyIdx).map(Hex.encode)
        let keys = try await addressKeys(of: wallet, index: address.index)
        let seeds = try await shieldedBridge.call("tzelAccount", [wallet.masterSk])
        guard let outgoingSeed = seeds["outgoingSeed"]?.stringValue else { throw ShieldedError.badReply("account seeds") }
        let request: [String: Any] = [
            "askJ": keys.askJ, "outgoingSeed": outgoingSeed, "address": address.bridgeRecord, "keyIdx": keyIdx, "authPath": path,
            "authDomain": authDomain, "pubkeyHash": pubkeyHash, "blind": pool.blind, "v": String(value), "fee": String(fee), "producerFee": String(producerFee),
            "producerAddress": try config.producerAddressJSON(),
        ]
        let built = try await shieldedBridge.call("tzelBuildShield", [String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)])
        guard let witness = built["witness"]?.arrayValue?.compactMap(\.stringValue), witness.count == 1 + 16 + 133 + 16 + 5,
              let clientCm = built["clientCm"]?.stringValue, let clientEnc = built["clientEnc"]?.stringValue,
              let producerCm = built["producerCm"]?.stringValue, let producerEnc = built["producerEnc"]?.stringValue,
              let outputs = built["publicOutputs"]?.arrayValue?.compactMap(\.stringValue), outputs.count == 9
        else { throw ShieldedError.badReply("shield witness") }

        shieldProgress = .proving
        let bundle = try await rollup.prove(program: "run_shield", arguments: witness)
        let message: [String: Any] = [
            "pubkeyHash": pubkeyHash, "fee": String(fee), "v": String(value), "producerFee": String(producerFee),
            "proofBytes": bundle.proofBytes, "outputPreimage": bundle.outputPreimage, "expectedOutputs": outputs, "programHash": bundle.programHash,
            "clientCm": clientCm, "clientEnc": clientEnc, "producerCm": producerCm, "producerEnc": producerEnc,
        ]
        let encoded = try await shieldedBridge.call("tzelEncodeShieldMessage", [String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)])
        guard let payload = encoded.stringValue, Hex.decode(payload) != nil else {
            throw ShieldedError.badReply("shield message: \(String(describing: encoded).prefix(200))")
        }

        shieldProgress = .submitting
        let submission = try await rollup.deliver(kind: "shield", payloadHex: payload, rollupAddress: config.rollupAddress, token: token)
        // The note is ours once the scan sees it; the pool is retired when it is seen drained.
        if var latest = try store.load(account: account), let at = latest.pools.firstIndex(where: { $0.pubkeyHash == pubkeyHash }) {
            latest.pools[at].shieldedCm = clientCm
            try store.save(latest, account: account)
            shieldedWallet = latest
        }
        await refreshAfterOperation()
        return ShieldReceipt(pool: pubkeyHash, depositHash: depositHash, depositLevel: depositLevel, shieldedMutez: value, rollupFeeMutez: fee, producerFeeMutez: producerFee, submissionID: submission.id, operationHash: submission.operationHash, cm: clientCm)
    }
}

extension JSONValue {
    /// The Foundation object `JSONSerialization` writes for this value.
    var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let b): b
        case .number(let n): n
        case .string(let s): s
        case .array(let a): a.map(\.foundationObject)
        case .object(let o): o.mapValues(\.foundationObject)
        }
    }
}
