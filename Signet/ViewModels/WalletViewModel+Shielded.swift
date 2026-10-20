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
    /// Unshield: reading the rollup's commitment tree, proving, handing over.
    case readingTree
    case provingUnshield
    case submittingUnshield
    /// Executing a withdrawal's outbox message on Tezos.
    case executing
    /// Send shielded: proving and handing over.
    case provingTransfer
    case submittingTransfer

    var text: String {
        switch self {
        case .preparing: "Checking the rollup…"
        case .buildingKeys(let fraction): "Creating your shielded address (\(Int(fraction * 100))%)…"
        case .depositing: "Sending the deposit on Tezos…"
        case .waitingForLayer1: "Waiting for the Tezos block…"
        case .waitingForRollup: "Waiting for the rollup to credit the deposit…"
        case .proving: "Proving the shield (about a minute)…"
        case .submitting: "Handing the shield to the operator…"
        case .readingTree: "Reading the rollup's commitment tree…"
        case .provingUnshield: "Proving the unshield (a minute or two)…"
        case .submittingUnshield: "Handing the unshield to the operator…"
        case .executing: "Executing the withdrawal on Tezos…"
        case .provingTransfer: "Proving the transfer (a minute or two)…"
        case .submittingTransfer: "Handing the transfer to the operator…"
        }
    }
}

/// The dashboard's view of the shielded wallet after a scan.
struct ShieldedSnapshot: Sendable {
    var wallet: ShieldedWallet?
    var pools: [ShieldedPoolStatus]
    var row: AssetBalance
    var withdrawals: [ShieldedWithdrawalStatus] = []
    var transfers: [ShieldedTransfer] = []
}

/// An unshield and where it stands, as of the last scan.
struct ShieldedWithdrawalStatus: Hashable, Sendable, Identifiable {
    var id: String { withdrawal.id }
    let withdrawal: ShieldedWithdrawal
    /// The rollup's last cemented level when it was looked at, if it was.
    let cementedLevel: Int?

    enum State: Hashable, Sendable {
        /// With the operator; the rollup has not spent the notes yet.
        case submitted
        /// Applied by the rollup; its outbox message has not been found yet.
        case queued
        /// In the outbox, waiting for the commitment covering it to be cemented.
        case waiting(blocksLeft: Int)
        /// Cemented: the account can execute it on Tezos.
        case ready
        case executed(String)
    }

    var state: State {
        if let hash = withdrawal.executedHash { return .executed(hash) }
        guard withdrawal.applied else { return .submitted }
        guard let level = withdrawal.outboxLevel, let cemented = cementedLevel else { return .queued }
        return cemented >= level ? .ready : .waiting(blocksLeft: level - cemented)
    }

    var text: String {
        switch state {
        case .submitted: "With the operator"
        case .queued: "Applied by the rollup, outbox message not found yet"
        case .waiting(let blocks): "Waiting for the rollup commitment to be cemented (about \(ShieldedWithdrawalStatus.days(blocks)))"
        case .ready: "Ready to execute on Tezos"
        case .executed: "Executed on Tezos"
        }
    }

    /// Shadownet and mainnet make a block every 6 seconds or so.
    static func days(_ blocks: Int) -> String {
        let hours = Double(blocks) * 6 / 3600
        if hours < 1 { return "\(max(1, Int(hours * 60))) minutes" }
        if hours < 48 { return "\(Int(hours.rounded(.up))) hours" }
        return "\(Int((hours / 24).rounded(.up))) days"
    }
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
/// An unshield estimate: the notes it will spend and the fees of the moment, in the context it
/// was made in (S31). The rollup fee is checked again before anything is proved.
struct UnshieldEstimate: Sendable {
    let context: WalletViewModel.BridgeContext
    /// What the recipient receives on Tezos.
    let amount: Decimal
    let amountMutez: UInt64
    let recipient: String
    let rollupFeeMutez: UInt64
    let producerFeeMutez: UInt64
    /// The notes selected to pay for it, largest first.
    let inputs: [ShieldedNote]

    var totalMutez: UInt64 { amountMutez + rollupFeeMutez + producerFeeMutez }
    var inputMutez: UInt64 { inputs.reduce(0) { $0 &+ $1.value } }
    /// What comes back as a note to a fresh address of ours.
    var changeMutez: UInt64 { inputMutez &- totalMutez }
    var change: Decimal { Decimal(changeMutez) / Mutez.perTez }
    var fees: Decimal { Decimal(rollupFeeMutez + producerFeeMutez) / Mutez.perTez }
}

/// A shielded transfer estimate (S31): the recipient, the notes it will spend and the fees.
struct SendShieldedEstimate: Sendable {
    let context: WalletViewModel.BridgeContext
    let amount: Decimal
    let amountMutez: UInt64
    let recipient: ShieldedContact
    let memo: String
    let rollupFeeMutez: UInt64
    let producerFeeMutez: UInt64
    let inputs: [ShieldedNote]

    var totalMutez: UInt64 { amountMutez + rollupFeeMutez + producerFeeMutez }
    var inputMutez: UInt64 { inputs.reduce(0) { $0 &+ $1.value } }
    var changeMutez: UInt64 { inputMutez &- totalMutez }
    var change: Decimal { Decimal(changeMutez) / Mutez.perTez }
    var fees: Decimal { Decimal(rollupFeeMutez + producerFeeMutez) / Mutez.perTez }
}

struct SendShieldedReceipt: Hashable, Sendable {
    let transfer: ShieldedTransfer
    var amount: Decimal { Decimal(transfer.amount) / Mutez.perTez }
}

/// One of the account's own shielded addresses as something to hand out.
struct ShieldedReceiveAddress: Hashable, Sendable {
    let index: Int
    /// The reference JSON, pretty-printed, as another wallet pastes it.
    let json: String
    let fingerprint: String
}

struct UnshieldReceipt: Hashable, Sendable {
    let withdrawal: ShieldedWithdrawal
    let changeMutez: UInt64
    var amount: Decimal { Decimal(withdrawal.amount) / Mutez.perTez }
}

/// The layer 1 fee for executing a withdrawal's outbox message, with the proof it was made for.
struct WithdrawalExecutionEstimate: Sendable {
    let estimate: TransferEstimate
    let context: WalletViewModel.BridgeContext
    let withdrawal: ShieldedWithdrawal
    let execution: OutboxExecution
}

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
            if let reserved = wallet?.reservedMutez, reserved > 0 { details.append(AssetBalance.Detail(id: "unshielding", label: "Leaving in an unshield or transfer, not yet applied", amount: Decimal(reserved) / Mutez.perTez)) }
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
            // Notes: fetched a batch at a time (the bridge takes at most 2 MB of arguments). Every
            // commitment is kept (`leafCms`, the tree an unshield proves against); a wallet whose
            // copy is shorter than its scan cursor reads again from where the copy ends.
            let size = try await rollup.treeSize(at: head.hash)
            var from = min(current.scanned, current.leafCms.count, size)
            if current.leafCms.count > from { current.leafCms.removeSubrange(from...) }
            if from < size {
                let scanning = !current.addresses.isEmpty
                let accountJSON = scanning ? try Self.json(try await bridge.call("tzelAccount", [current.masterSk])) : ""
                let addressesJSON = try Self.json(.array(current.addresses.map { .object($0.bridgeRecord.mapValues { JSONValue(bridged: $0) }) }))
                while from < size {
                    try Task.checkCancellation()
                    let to = min(from + 200, size)
                    let batch = try await Self.fetchNotes(rollup: rollup, block: head.hash, range: from..<to)
                    guard batch.count == to - from, batch.first?.index == from else { throw ShieldedError.badReply("notes \(from) to \(to - 1) are not all published") }
                    current.leafCms += batch.map { String($0.hex.prefix(64)) }
                    if scanning {
                        let found = try await bridge.call("tzelScan", [accountJSON, addressesJSON, try Self.json(.array(batch.map { .object(["index": .number(Double($0.index)), "bytes": .string($0.hex)]) }))])
                        for note in found.arrayValue ?? [] {
                            guard let index = note["index"]?.intValue, let cm = note["cm"]?.stringValue, let rseed = note["rseed"]?.stringValue,
                                  let nullifier = note["nullifier"]?.stringValue, let value = note["v"]?.stringValue, let addressIndex = note["addressIndex"]?.intValue
                            else { throw ShieldedError.badReply("scan result") }
                            if !current.notes.contains(where: { $0.index == index }) {
                                var found = ShieldedNote(index: index, cm: cm, rseed: rseed, nullifier: nullifier, valueMutez: value, addressIndex: addressIndex)
                                if let memo = note["memo"]?.stringValue, !memo.isEmpty { found.memo = memo }
                                current.notes.append(found)
                            }
                        }
                    }
                    from = to
                    current.scanned = to
                }
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
            // Withdrawals: applied once the rollup has spent every input; then the outbox message
            // is looked for among the node's pending ones (the recipient as forged, the amount,
            // not before the level it was submitted at) and watched for the cemented level.
            let spent = Set(current.notes.filter(\.spent).map(\.nullifier))
            for i in current.withdrawals.indices where !current.withdrawals[i].applied && current.withdrawals[i].nullifiers.allSatisfy(spent.contains) {
                current.withdrawals[i].applied = true
            }
            var cemented: Int?
            if current.withdrawals.contains(where: { $0.applied && $0.executedHash == nil }) {
                cemented = try await rollup.cementedLevel()
                if current.withdrawals.contains(where: { $0.applied && $0.outboxLevel == nil }) {
                    let pending = try await rollup.pendingOutbox()
                    var claimed = Set(current.withdrawals.compactMap { w in w.outboxLevel.map { "\($0)/\(w.messageIndex ?? 0)" } })
                    for i in current.withdrawals.indices where current.withdrawals[i].applied && current.withdrawals[i].outboxLevel == nil {
                        let w = current.withdrawals[i]
                        guard let receiver = Address(w.recipient).forgedContract else { continue }
                        let matches = pending.filter { $0.entrypoint == "burn" && $0.receiver == receiver && $0.amountMutez == w.amount && $0.outboxLevel >= w.submittedLevel && !claimed.contains("\($0.outboxLevel)/\($0.messageIndex)") }
                        guard let match = matches.min(by: { ($0.outboxLevel, $0.messageIndex) < ($1.outboxLevel, $1.messageIndex) }) else { continue }
                        current.withdrawals[i].outboxLevel = match.outboxLevel
                        current.withdrawals[i].messageIndex = match.messageIndex
                        claimed.insert("\(match.outboxLevel)/\(match.messageIndex)")
                    }
                }
            }
            // Executed withdrawals and applied transfers stay a week for the record.
            current.withdrawals.removeAll { $0.executedHash != nil && $0.created < Date().addingTimeInterval(-7 * 86_400) }
            for i in current.transfers.indices where !current.transfers[i].applied && current.transfers[i].nullifiers.allSatisfy(spent.contains) {
                current.transfers[i].applied = true
            }
            current.transfers.removeAll { $0.applied && $0.created < Date().addingTimeInterval(-7 * 86_400) }
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
            // Onto the wallet as it is on file now: a key index may have been spent, an address
            // or a record added while this scan ran, and none of that is rolled back.
            if let merged = try store.update(account: account, initial: nil, { $0 = $0.merging(scan: current, since: before) }) { current = merged }
            let withdrawals = current.withdrawals.map { ShieldedWithdrawalStatus(withdrawal: $0, cementedLevel: cemented) }
            return ShieldedSnapshot(wallet: current, pools: statuses, row: row(current, pools: statuses), withdrawals: withdrawals, transfers: current.transfers)
        } catch {
            let statuses = current.pools.map { ShieldedPoolStatus(pool: $0, balanceMutez: nil) }
            let withdrawals = current.withdrawals.map { ShieldedWithdrawalStatus(withdrawal: $0, cementedLevel: nil) }
            return ShieldedSnapshot(wallet: current, pools: statuses, row: row(current, pools: statuses, unavailable: "Shielded balance unavailable: \(error.localizedDescription)"), withdrawals: withdrawals, transfers: current.transfers)
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
        // The first address takes seconds to build, so the wallet is written only once it is
        // there, onto whatever is on file by then: another caller may have made the wallet
        // meanwhile, and theirs is kept (its address built next time round if it has none).
        var rounds = 0
        while wallet.addresses.isEmpty, rounds < 2 {
            rounds += 1
            let first = try await makeAddress(index: 0, of: wallet, account: account)
            let masterSk = wallet.masterSk
            var created = wallet
            created.addresses.append(first)
            guard let now = try store.update(account: account, initial: created, { latest in
                if latest.masterSk == masterSk, latest.addresses.isEmpty { latest.addresses.append(first) }
            }) else { throw ShieldedError.treeMissing(0) }
            wallet = now
        }
        shieldedWallet = wallet
        return wallet
    }

    /// Address `index` of `wallet`: its keys from the bridge, its signing tree built natively
    /// (seconds, reported to the sheet) and kept beside the wallet file.
    private func makeAddress(index: Int, of wallet: ShieldedWallet, account: Address) async throws -> ShieldedAddress {
        let keys = try await addressKeys(of: wallet, index: index)
        let leaves = try await buildLeaves(askJ: keys.askJ, pubSeed: keys.pubSeed)
        try shieldedStore(for: network.chain).saveLeaves(leaves, account: account, addressIndex: index)
        let root = XMSSAuthTree.root(pubSeed: keys.pubSeedBytes, leaves: leaves)
        return ShieldedAddress(index: index, dJ: keys.dJ, authRoot: Hex.encode(root), pubSeed: keys.pubSeed, nkTag: keys.nkTag, ekV: keys.ekV, ekD: keys.ekD, nextKeyIndex: 0)
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
        let wallet = try await ensureShieldedWallet(config: config, account: account)
        guard bridgeContext == context else { throw WalletError.contextChanged }
        if let unfunded = wallet.pools.first(where: { $0.operationHash == nil && $0.authDomain == authDomain }) { return unfunded }
        guard let address = wallet.addresses.first else { throw ShieldedError.treeMissing(0) }
        let store = shieldedStore(for: network.chain)
        var nonce: UInt64 = 0
        guard try store.update(account: account, initial: nil, { nonce = $0.depositNonce; $0.depositNonce += 1 }) != nil else { throw ShieldedError.treeMissing(0) }
        let made = try await shieldedBridge.call("tzelDepositPool", [wallet.masterSk, address.index, String(nonce), authDomain, address.authRoot, address.pubSeed])
        guard let pubkeyHash = made["pubkeyHash"]?.stringValue, let blind = made["blind"]?.stringValue, Hex.decode(pubkeyHash)?.count == 32 else { throw ShieldedError.badReply("deposit pool") }
        let pool = DepositPool(pubkeyHash: pubkeyHash, blind: blind, addressIndex: address.index, authDomain: authDomain, depositedMutez: "0", operationHash: nil, shieldedCm: nil, created: Date())
        // The pool is on file before any tez go to it.
        guard let saved = try store.update(account: account, initial: nil, { $0.pools.append(pool) }) else { throw ShieldedError.treeMissing(0) }
        shieldedWallet = saved
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
        guard let shielded = try store.load(account: wallet.address), shielded.pool(approved.pool.pubkeyHash) != nil else { throw ShieldedError.poolUnknown(approved.pool.pubkeyHash) }
        let amountMutez = Mutez.fromTez(approved.amount)
        guard let added = UInt64(amountMutez), added + config.producerFeeMutez > 0 else { throw SendViewModel.SendError.invalidAmount }

        shieldProgress = .depositing
        defer { shieldProgress = nil }
        let chain = currentChain
        let deposit = ShieldDeposit(ticketer: config.ticketer, rollup: config.rollupAddress, pubkeyHash: approved.pool.pubkeyHash, amount: approved.amount)
        let sent = try await chain.sendShieldDeposit(from: wallet, signer: signer, deposit: deposit, limits: limits)
        // On file before the block is waited for: the pool is funded (or about to be) by this
        // operation (and put back should a scan have retired it meanwhile: the tez are on their way).
        let funded = try store.update(account: wallet.address, initial: nil) { latest in
            if latest.pool(approved.pool.pubkeyHash) == nil { latest.pools.append(approved.pool) }
            guard let at = latest.pools.firstIndex(where: { $0.pubkeyHash == approved.pool.pubkeyHash }) else { return }
            latest.pools[at].operationHash = sent.hash
            latest.pools[at].depositedMutez = String((UInt64(latest.pools[at].depositedMutez) ?? 0) + added)
        }
        if let funded { shieldedWallet = funded }
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
        guard var wallet = try store.load(account: account), let pool = wallet.pool(pubkeyHash) else { throw ShieldedError.poolUnknown(pubkeyHash) }
        guard wallet.address(at: pool.addressIndex) != nil else { throw ShieldedError.treeMissing(pool.addressIndex) }
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

        // One signature per key index, ever: the index is spent on file before it is used, taken
        // from the wallet as it is on file now (a scan or another spend may have moved it on
        // since it was read).
        var keyIdx = 0
        guard let spent = try store.update(account: account, initial: nil, { latest in
            guard let at = latest.addresses.firstIndex(where: { $0.index == pool.addressIndex }) else { throw ShieldedError.treeMissing(pool.addressIndex) }
            keyIdx = latest.addresses[at].nextKeyIndex
            guard keyIdx < XMSSAuthTree.size else { throw ShieldedError.keysExhausted(pool.addressIndex) }
            latest.addresses[at].nextKeyIndex = keyIdx + 1
        }), let address = spent.address(at: pool.addressIndex) else { throw ShieldedError.poolUnknown(pubkeyHash) }
        wallet = spent
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
        if let latest = try store.update(account: account, initial: nil, { latest in
            if let at = latest.pools.firstIndex(where: { $0.pubkeyHash == pubkeyHash }) { latest.pools[at].shieldedCm = clientCm }
        }) { shieldedWallet = latest }
        await refreshAfterOperation()
        return ShieldReceipt(pool: pubkeyHash, depositHash: depositHash, depositLevel: depositLevel, shieldedMutez: value, rollupFeeMutez: fee, producerFeeMutez: producerFee, submissionID: submission.id, operationHash: submission.operationHash, cm: clientCm)
    }

    // MARK: Unshield

    /// The kernel takes at most seven inputs per unshield.
    nonisolated static let maxUnshieldInputs = 7

    /// The notes that pay for `total`, largest first until it is covered, as the reference
    /// wallet selects (the fewest signatures and the smallest proof).
    nonisolated static func selectNotes(_ notes: [ShieldedNote], covering total: UInt64) throws -> [ShieldedNote] {
        let available = notes.reduce(0) { $0 &+ $1.value }
        guard available >= total else { throw ShieldedError.insufficientShielded(available: available, needed: total) }
        var selected: [ShieldedNote] = []
        var sum: UInt64 = 0
        for note in notes.sorted(by: { $0.value > $1.value }) {
            selected.append(note)
            sum &+= note.value
            if sum >= total { break }
        }
        guard selected.count <= maxUnshieldInputs else { throw ShieldedError.tooManyInputs(selected.count) }
        return selected
    }

    /// What unshielding `amount` tez to `recipient` would spend: the rollup's fee of the moment,
    /// the producer's fee and the notes chosen to cover them. Nothing is sent.
    func estimateUnshield(amount: Decimal, recipient: String) async throws -> UnshieldEstimate {
        let config = try shieldedConfig
        guard let wallet = selectedWallet, let context = bridgeContext else { throw WalletError.emptyAlias }
        guard amount > 0, Mutez.isValid(Mutez.fromTez(amount)), let amountMutez = UInt64(Mutez.fromTez(amount)), amountMutez > 0 else { throw SendViewModel.SendError.invalidAmount }
        let to = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Address(to).isValidAccount, to.hasPrefix("tz") || to.hasPrefix("KT1"), !to.hasPrefix("tz5"), !to.hasPrefix("tz6") else { throw ShieldedError.badRecipient(to) }
        let shielded = try shieldedStore(for: network.chain).load(account: wallet.address)
        let rollup = shieldedRollupFactory(config)
        let fee = try await rollup.requiredTxFee(at: rollup.head())
        let (total, overflow) = amountMutez.addingReportingOverflow(fee + config.producerFeeMutez)
        guard !overflow else { throw SendViewModel.SendError.invalidAmount }
        let inputs = try Self.selectNotes(shielded?.availableNotes ?? [], covering: total)
        guard bridgeContext == context else { throw WalletError.contextChanged }
        return UnshieldEstimate(context: context, amount: amount, amountMutez: amountMutez, recipient: to, rollupFeeMutez: fee, producerFeeMutez: config.producerFeeMutez, inputs: inputs)
    }

    /// Unshields `approved.amount` tez to `approved.recipient`: reads the rollup's tree again
    /// (an input spent meanwhile is refused, as is a changed rollup fee), makes a fresh address
    /// for the change and builds its signing tree, spends every input's next WOTS+ key index on
    /// disk *before* signing, has the bridge build the change and producer notes, the sighash,
    /// the signatures and the witness, proves it and hands it to the operator. The withdrawal is
    /// on file as soon as the operator has it, so its notes stay reserved; the tez reach the
    /// recipient on Tezos once the covering commitment is cemented and the outbox message is
    /// executed (`executeWithdrawal`). Needs no layer 1 signature, so no password.
    func unshieldTez(approved: UnshieldEstimate) async throws -> UnshieldReceipt {
        let config = try shieldedConfig
        guard let account = selectedWallet?.address else { throw WalletError.emptyAlias }
        guard approved.context == bridgeContext, canShield else { throw WalletError.contextChanged }
        let context = bridgeContext
        let store = shieldedStore(for: network.chain)
        guard let token = try store.operatorToken(), !token.isEmpty else { throw ShieldedError.operatorTokenMissing }
        let rollup = shieldedRollupFactory(config)
        shieldProgress = .readingTree
        defer { shieldProgress = nil }
        let spend = try await prepareSpend(inputs: approved.inputs, totalMutez: approved.totalMutez, approvedFee: approved.rollupFeeMutez, changeAddressAlways: false, account: account, store: store, rollup: rollup, context: context)
        let change = spend.changeMutez, fee = spend.fee, root = spend.root, head = spend.head
        let request: [String: Any] = [
            "account": spend.seeds.foundationObject, "authDomain": spend.authDomain, "root": root, "leafCms": spend.wallet.leafCms,
            "vPub": String(approved.amountMutez), "fee": String(fee), "producerFee": String(config.producerFeeMutez), "recipient": approved.recipient,
            "inputs": spend.inputRecords, "changeAddress": spend.changeAddress?.bridgeRecord ?? NSNull(), "producerAddress": try config.producerAddressJSON(),
        ]
        let built = try await shieldedBridge.call("tzelBuildUnshield", [String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)])
        let n = spend.inputs.count
        guard let witness = built["witness"]?.arrayValue?.compactMap(\.stringValue), witness.count == 1 + 6 + n * 206 + 15,
              let nullifiers = built["nullifiers"]?.arrayValue?.compactMap(\.stringValue), nullifiers == spend.inputs.map(\.nullifier),
              let producerCm = built["producerCm"]?.stringValue, let producerEnc = built["producerEnc"]?.stringValue,
              let outputs = built["publicOutputs"]?.arrayValue?.compactMap(\.stringValue), outputs.count == 2 + n + 7,
              built["changeMutez"]?.stringValue == String(change)
        else { throw ShieldedError.badReply("unshield witness") }
        let changeCm = built["changeCm"]?.stringValue, changeEnc = built["changeEnc"]?.stringValue
        guard (change > 0) == (changeCm != nil && changeEnc != nil) else { throw ShieldedError.badReply("unshield change note") }

        shieldProgress = .provingUnshield
        let bundle = try await rollup.prove(program: "run_unshield", arguments: witness)
        let message: [String: Any] = [
            "root": root, "nullifiers": nullifiers, "vPub": String(approved.amountMutez), "fee": String(fee), "recipient": approved.recipient,
            "cmChange": changeCm ?? Hex.encode(XMSSAuthTree.feltOfInt(0)), "changeEnc": changeEnc ?? NSNull(), "cmFee": producerCm, "producerEnc": producerEnc,
            "proofBytes": bundle.proofBytes, "outputPreimage": bundle.outputPreimage, "expectedOutputs": outputs, "programHash": bundle.programHash,
        ]
        let encoded = try await shieldedBridge.call("tzelEncodeUnshieldMessage", [String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)])
        guard let payload = encoded.stringValue, Hex.decode(payload) != nil else {
            throw ShieldedError.badReply("unshield message: \(String(describing: encoded).prefix(200))")
        }

        shieldProgress = .submittingUnshield
        let submission = try await rollup.submit(kind: "unshield", payloadHex: payload, rollupAddress: config.rollupAddress, token: token)
        // On file as soon as the operator has it: the inputs are reserved from here.
        var withdrawal = ShieldedWithdrawal(submissionID: submission.id, recipient: approved.recipient, amountMutez: String(approved.amountMutez), rollupFeeMutez: String(fee), producerFeeMutez: String(config.producerFeeMutez), nullifiers: nullifiers, changeCm: changeCm, submittedLevel: head.level, created: Date(), operationHash: submission.operationHash)
        try updateWithdrawals(account: account, store: store) { $0.append(withdrawal) }
        do {
            let delivered = try await rollup.awaitDelivery(of: submission, token: token)
            withdrawal.operationHash = delivered.operationHash
            let final = withdrawal
            try updateWithdrawals(account: account, store: store) { list in
                if let at = list.firstIndex(where: { $0.id == final.id }) { list[at].operationHash = final.operationHash }
            }
        } catch ShieldedError.submissionPending {
            // Still with the operator: the record stays, the scan will see it land.
        } catch {
            // The operator gave up on it: the notes are free again.
            try? updateWithdrawals(account: account, store: store) { list in list.removeAll { $0.id == submission.id } }
            throw error
        }
        await refreshAfterOperation()
        return UnshieldReceipt(withdrawal: withdrawal, changeMutez: change)
    }

    /// What an unshield and a shielded transfer do alike: the inputs checked against the
    /// rollup's tree and fee as they are now, the change address made, every input's key
    /// index spent on disk, and the auth paths taken from the native trees.
    private struct SpendPreparation {
        let wallet: ShieldedWallet
        let head: RollupHead
        let root: String
        let authDomain: String
        let fee: UInt64
        let inputs: [ShieldedNote]
        let changeMutez: UInt64
        let changeAddress: ShieldedAddress?
        let inputRecords: [[String: Any]]
        let seeds: JSONValue
    }

    private func prepareSpend(inputs approvedInputs: [ShieldedNote], totalMutez: UInt64, approvedFee: UInt64, changeAddressAlways: Bool, account: Address, store: any ShieldedWalletStore, rollup: any ShieldedRollup, context: BridgeContext?) async throws -> SpendPreparation {
        // The tree as the rollup has it now, our notes and the nullifiers with it.
        let snapshot = await Self.scanShielded(store: store, account: account, rollup: rollup, bridge: shieldedBridge)
        if let problem = snapshot.row.unavailable { throw ShieldedError.badReply(problem) }
        guard var wallet = snapshot.wallet else { throw ShieldedError.insufficientShielded(available: 0, needed: totalMutez) }
        let head = try await rollup.head()
        let root = try await rollup.treeRoot(at: head.hash)
        let size = try await rollup.treeSize(at: head.hash)
        guard wallet.leafCms.count == size else { throw ShieldedError.treeStale }
        let fee = try await rollup.requiredTxFee(at: head)
        guard fee == approvedFee else { throw ShieldedError.feeChanged(from: approvedFee, to: fee) }
        let authDomain = try await rollup.authDomain(at: head.hash)
        let available = Dictionary(wallet.availableNotes.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        let inputs = try approvedInputs.map { note -> ShieldedNote in
            guard let now = available[note.index], now.cm == note.cm, now.value == note.value else { throw ShieldedError.treeStale }
            return now
        }
        let sum = inputs.reduce(0) { $0 &+ $1.value }
        guard sum >= totalMutez else { throw ShieldedError.insufficientShielded(available: sum, needed: totalMutez) }
        let change = sum - totalMutez
        guard bridgeContext == context else { throw WalletError.contextChanged }

        // Change goes to a fresh address of ours, made (and its signing tree built) first.
        var changeAddress: ShieldedAddress?
        if change > 0 || changeAddressAlways {
            changeAddress = try await makeAddress(index: (wallet.addresses.map(\.index).max() ?? -1) + 1, of: wallet, account: account)
        }
        // One signature per key index, ever: every input's index is spent on file before it is
        // used, taken from the wallet as it is on file now (a scan or another spend may have
        // moved it on since it was read, and may have reserved or spent an input).
        var reserved: [(note: ShieldedNote, address: ShieldedAddress, keyIdx: Int)] = []
        guard let spent = try store.update(account: account, initial: nil, { latest in
            if let made = changeAddress, latest.address(at: made.index) == nil { latest.addresses.append(made) }
            let taken = latest.reservedNullifiers
            reserved = []
            for note in inputs {
                guard let now = latest.notes.first(where: { $0.index == note.index }), now.cm == note.cm, !now.spent, !taken.contains(now.nullifier) else { throw ShieldedError.treeStale }
                guard let at = latest.addresses.firstIndex(where: { $0.index == note.addressIndex }) else { throw ShieldedError.treeMissing(note.addressIndex) }
                let keyIdx = latest.addresses[at].nextKeyIndex
                guard keyIdx < XMSSAuthTree.size else { throw ShieldedError.keysExhausted(note.addressIndex) }
                latest.addresses[at].nextKeyIndex = keyIdx + 1
                reserved.append((note, latest.addresses[at], keyIdx))
            }
        }) else { throw ShieldedError.insufficientShielded(available: 0, needed: totalMutez) }
        wallet = spent
        shieldedWallet = wallet
        if let made = changeAddress { changeAddress = wallet.address(at: made.index) }

        // Each input's auth path from its address's native tree.
        var trees: [Int: [[UInt8]]] = [:]
        var inputRecords: [[String: Any]] = []
        for r in reserved {
            if trees[r.address.index] == nil {
                let leaves = try await leaves(of: r.address, in: wallet, account: account)
                guard let pubSeed = Hex.decode(r.address.pubSeed) else { throw ShieldedError.treeMissing(r.address.index) }
                trees[r.address.index] = XMSSAuthTree.levels(pubSeed: pubSeed, leaves: leaves)
            }
            guard let levels = trees[r.address.index] else { throw ShieldedError.treeMissing(r.address.index) }
            let path = XMSSAuthTree.path(levels: levels, index: r.keyIdx).map(Hex.encode)
            inputRecords.append(["note": ["index": r.note.index, "cm": r.note.cm, "rseed": r.note.rseed, "v": r.note.valueMutez], "address": r.address.bridgeRecord, "keyIdx": r.keyIdx, "authPath": path])
        }
        let seeds = try await shieldedBridge.call("tzelAccount", [wallet.masterSk])
        return SpendPreparation(wallet: wallet, head: head, root: root, authDomain: authDomain, fee: fee, inputs: inputs, changeMutez: change, changeAddress: changeAddress, inputRecords: inputRecords, seeds: seeds)
    }

    private func updateWithdrawals(account: Address, store: any ShieldedWalletStore, _ change: (inout [ShieldedWithdrawal]) -> Void) throws {
        guard let latest = try store.update(account: account, initial: nil, { change(&$0.withdrawals) }) else { return }
        shieldedWallet = latest
    }

    private func updateTransfers(account: Address, store: any ShieldedWalletStore, _ change: (inout [ShieldedTransfer]) -> Void) throws {
        guard let latest = try store.update(account: account, initial: nil, { change(&$0.transfers) }) else { return }
        shieldedWallet = latest
    }

    // MARK: Shielded addresses

    /// A shielded recipient is nothing but a payment address (the 2496-byte record: diversifier,
    /// auth root, public seed, nullifier tag and two ML-KEM keys); the protocol has no shorter
    /// name for one. Reads the reference JSON another wallet printed, or a saved contact's, and
    /// names it by its fingerprint, the hash of the canonical record.
    func shieldedRecipient(from text: String) async throws -> ShieldedContact {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShieldedError.badPaymentAddress("nothing was given") }
        let parsed: JSONValue
        do { parsed = try await shieldedBridge.call("tzelPaymentAddress", [trimmed]) } catch { throw ShieldedError.badPaymentAddress(error.localizedDescription) }
        guard let fingerprint = parsed["fingerprint"]?.stringValue, Hex.decode(fingerprint)?.count == 32, let fields = parsed["address"]?.objectValue else { throw ShieldedError.badPaymentAddress("unexpected reply") }
        let address = fields.compactMapValues(\.stringValue)
        guard address.count == 6 else { throw ShieldedError.badPaymentAddress("fields missing") }
        if let known = try shieldedContacts().first(where: { $0.fingerprint == fingerprint }) { return known }
        return ShieldedContact(name: "", fingerprint: fingerprint, address: address, created: Date())
    }

    /// The network's shielded address book (shared by every account in the directory).
    func shieldedContacts() throws -> [ShieldedContact] {
        guard network.shielded != nil else { return [] }
        return try shieldedStore(for: network.chain).contacts()
    }

    /// Adds `contact` under `name`; the same address twice is refused.
    func addShieldedContact(_ contact: ShieldedContact, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WalletError.emptyAlias }
        let store = shieldedStore(for: network.chain)
        var contacts = try store.contacts()
        if let existing = contacts.first(where: { $0.fingerprint == contact.fingerprint }) { throw ShieldedError.contactExists(existing.name) }
        if contacts.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { throw WalletError.aliasExists(trimmed) }
        contacts.append(ShieldedContact(name: trimmed, fingerprint: contact.fingerprint, address: contact.address, created: Date()))
        try store.saveContacts(contacts)
    }

    func removeShieldedContact(_ fingerprint: String) throws {
        let store = shieldedStore(for: network.chain)
        var contacts = try store.contacts()
        contacts.removeAll { $0.fingerprint == fingerprint }
        try store.saveContacts(contacts)
    }

    /// The account's newest shielded address to hand out (the wallet and its first address
    /// are made if need be), as the JSON another wallet pastes, with its fingerprint.
    func shieldedReceiveAddress() async throws -> ShieldedReceiveAddress {
        let config = try shieldedConfig
        guard let account = selectedWallet?.address else { throw WalletError.emptyAlias }
        shieldProgress = .preparing
        defer { shieldProgress = nil }
        let wallet = try await ensureShieldedWallet(config: config, account: account)
        guard let address = wallet.addresses.max(by: { $0.index < $1.index }) else { throw ShieldedError.treeMissing(0) }
        return try await receiveAddress(address)
    }

    /// A fresh shielded address of the account (its signing tree built, seconds), so that
    /// what is handed to one payer links to nothing handed to another.
    func makeShieldedAddress() async throws -> ShieldedReceiveAddress {
        let config = try shieldedConfig
        guard let account = selectedWallet?.address else { throw WalletError.emptyAlias }
        let store = shieldedStore(for: network.chain)
        shieldProgress = .preparing
        defer { shieldProgress = nil }
        let wallet = try await ensureShieldedWallet(config: config, account: account)
        let index = (wallet.addresses.map(\.index).max() ?? -1) + 1
        let made = try await makeAddress(index: index, of: wallet, account: account)
        // Onto the wallet as it is on file now; the same index made meanwhile is the same address.
        guard let saved = try store.update(account: account, initial: nil, { if $0.address(at: made.index) == nil { $0.addresses.append(made) } }) else { throw ShieldedError.treeMissing(index) }
        shieldedWallet = saved
        return try await receiveAddress(saved.address(at: index) ?? made)
    }

    private func receiveAddress(_ address: ShieldedAddress) async throws -> ShieldedReceiveAddress {
        let parsed = try await shieldedBridge.call("tzelPaymentAddress", [try Self.json(.object(address.paymentAddressJSON.mapValues { .string($0) }))])
        guard let fingerprint = parsed["fingerprint"]?.stringValue else { throw ShieldedError.badReply("payment address") }
        let data = try JSONSerialization.data(withJSONObject: address.paymentAddressJSON, options: [.prettyPrinted, .sortedKeys])
        return ShieldedReceiveAddress(index: address.index, json: String(decoding: data, as: UTF8.self), fingerprint: fingerprint)
    }

    // MARK: Send shielded

    /// What sending `amount` tez to `recipient` with `memo` would spend. Nothing is sent.
    func estimateSendShielded(amount: Decimal, recipient: ShieldedContact, memo: String) async throws -> SendShieldedEstimate {
        let config = try shieldedConfig
        guard let wallet = selectedWallet, let context = bridgeContext else { throw WalletError.emptyAlias }
        guard amount > 0, Mutez.isValid(Mutez.fromTez(amount)), let amountMutez = UInt64(Mutez.fromTez(amount)), amountMutez > 0 else { throw SendViewModel.SendError.invalidAmount }
        guard memo.utf8.count <= 1024 else { throw ShieldedError.memoTooLong }
        let shielded = try shieldedStore(for: network.chain).load(account: wallet.address)
        let rollup = shieldedRollupFactory(config)
        let fee = try await rollup.requiredTxFee(at: rollup.head())
        let (total, overflow) = amountMutez.addingReportingOverflow(fee + config.producerFeeMutez)
        guard !overflow else { throw SendViewModel.SendError.invalidAmount }
        let inputs = try Self.selectNotes(shielded?.availableNotes ?? [], covering: total)
        guard bridgeContext == context else { throw WalletError.contextChanged }
        return SendShieldedEstimate(context: context, amount: amount, amountMutez: amountMutez, recipient: recipient, memo: memo, rollupFeeMutez: fee, producerFeeMutez: config.producerFeeMutez, inputs: inputs)
    }

    /// Sends `approved.amount` tez to `approved.recipient` as a shielded transfer: the same
    /// preparation as an unshield (a change address is always made, since the kernel takes
    /// exactly three output notes), then `tzelBuildTransfer`, `run_transfer`, the operator;
    /// the transfer is on file as soon as the operator has it. The recipient sees the note on
    /// their next scan; nothing identifies them on the rollup but their own viewing keys.
    func sendShielded(approved: SendShieldedEstimate) async throws -> SendShieldedReceipt {
        let config = try shieldedConfig
        guard let account = selectedWallet?.address else { throw WalletError.emptyAlias }
        guard approved.context == bridgeContext, canShield else { throw WalletError.contextChanged }
        let context = bridgeContext
        let store = shieldedStore(for: network.chain)
        guard let token = try store.operatorToken(), !token.isEmpty else { throw ShieldedError.operatorTokenMissing }
        let rollup = shieldedRollupFactory(config)
        shieldProgress = .readingTree
        defer { shieldProgress = nil }
        let spend = try await prepareSpend(inputs: approved.inputs, totalMutez: approved.totalMutez, approvedFee: approved.rollupFeeMutez, changeAddressAlways: true, account: account, store: store, rollup: rollup, context: context)
        guard let changeAddress = spend.changeAddress else { throw ShieldedError.treeMissing(spend.wallet.addresses.count) }
        let fee = spend.fee, root = spend.root
        let request: [String: Any] = [
            "account": spend.seeds.foundationObject, "authDomain": spend.authDomain, "root": root, "leafCms": spend.wallet.leafCms,
            "amount": String(approved.amountMutez), "fee": String(fee), "producerFee": String(config.producerFeeMutez), "recipient": approved.recipient.address, "memo": approved.memo,
            "inputs": spend.inputRecords, "changeAddress": changeAddress.bridgeRecord, "producerAddress": try config.producerAddressJSON(),
        ]
        let built = try await shieldedBridge.call("tzelBuildTransfer", [String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)])
        let n = spend.inputs.count
        guard let witness = built["witness"]?.arrayValue?.compactMap(\.stringValue), witness.count == 1 + 4 + n * 206 + 24,
              let nullifiers = built["nullifiers"]?.arrayValue?.compactMap(\.stringValue), nullifiers == spend.inputs.map(\.nullifier),
              let cms = built["cms"]?.arrayValue?.compactMap(\.stringValue), cms.count == 3, let encs = built["encs"]?.arrayValue?.compactMap(\.stringValue), encs.count == 3,
              let outputs = built["publicOutputs"]?.arrayValue?.compactMap(\.stringValue), outputs.count == 2 + n + 7,
              built["changeMutez"]?.stringValue == String(spend.changeMutez), built["recipientFingerprint"]?.stringValue == approved.recipient.fingerprint
        else { throw ShieldedError.badReply("transfer witness") }

        shieldProgress = .provingTransfer
        let bundle = try await rollup.prove(program: "run_transfer", arguments: witness)
        let message: [String: Any] = [
            "root": root, "nullifiers": nullifiers, "fee": String(fee), "cms": cms, "encs": encs,
            "proofBytes": bundle.proofBytes, "outputPreimage": bundle.outputPreimage, "expectedOutputs": outputs, "programHash": bundle.programHash,
        ]
        let encoded = try await shieldedBridge.call("tzelEncodeTransferMessage", [String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)])
        guard let payload = encoded.stringValue, Hex.decode(payload) != nil else {
            throw ShieldedError.badReply("transfer message: \(String(describing: encoded).prefix(200))")
        }

        shieldProgress = .submittingTransfer
        let submission = try await rollup.submit(kind: "transfer", payloadHex: payload, rollupAddress: config.rollupAddress, token: token)
        var transfer = ShieldedTransfer(submissionID: submission.id, recipientFingerprint: approved.recipient.fingerprint, recipientName: approved.recipient.name.isEmpty ? nil : approved.recipient.name, amountMutez: String(approved.amountMutez), rollupFeeMutez: String(fee), producerFeeMutez: String(config.producerFeeMutez), memo: approved.memo, nullifiers: nullifiers, recipientCm: cms[0], changeCm: cms[1], created: Date(), operationHash: submission.operationHash)
        try updateTransfers(account: account, store: store) { $0.append(transfer) }
        do {
            let delivered = try await rollup.awaitDelivery(of: submission, token: token)
            transfer.operationHash = delivered.operationHash
            let final = transfer
            try updateTransfers(account: account, store: store) { list in
                if let at = list.firstIndex(where: { $0.id == final.id }) { list[at].operationHash = final.operationHash }
            }
        } catch ShieldedError.submissionPending {
            // Still with the operator: the record stays, the scan will see it land.
        } catch {
            try? updateTransfers(account: account, store: store) { list in list.removeAll { $0.id == submission.id } }
            throw error
        }
        await refreshAfterOperation()
        return SendShieldedReceipt(transfer: transfer)
    }

    /// Drops a transfer the rollup has not applied, freeing its notes (see `forgetWithdrawal`).
    func forgetTransfer(_ id: String) throws {
        guard let account = selectedWallet?.address else { throw WalletError.emptyAlias }
        let store = shieldedStore(for: network.chain)
        guard let wallet = try store.load(account: account), let transfer = wallet.transfers.first(where: { $0.id == id }) else { throw ShieldedError.withdrawalUnknown(id) }
        guard !transfer.applied else { throw ShieldedError.withdrawalNotReady("the rollup has applied it") }
        try updateTransfers(account: account, store: store) { list in list.removeAll { $0.id == id } }
        shieldedTransfers.removeAll { $0.id == id }
    }

    /// Drops a withdrawal the rollup has not applied, freeing its notes. For one the operator
    /// never delivered; if it is delivered after all, the scan marks the notes spent anyway.
    func forgetWithdrawal(_ id: String) throws {
        guard let account = selectedWallet?.address else { throw WalletError.emptyAlias }
        let store = shieldedStore(for: network.chain)
        guard let wallet = try store.load(account: account), let withdrawal = wallet.withdrawals.first(where: { $0.id == id }) else { throw ShieldedError.withdrawalUnknown(id) }
        guard !withdrawal.applied else { throw ShieldedError.withdrawalNotReady("the rollup has applied it") }
        try updateWithdrawals(account: account, store: store) { list in list.removeAll { $0.id == id } }
        shieldedWithdrawals.removeAll { $0.id == id }
    }

    /// The layer 1 fee for executing withdrawal `id`'s outbox message, with the rollup node's
    /// proof against the last cemented commitment. Refused until that commitment covers it.
    func estimateWithdrawalExecution(_ id: String) async throws -> WithdrawalExecutionEstimate {
        let config = try shieldedConfig
        guard let wallet = selectedWallet, let context = bridgeContext else { throw WalletError.emptyAlias }
        guard let shielded = try shieldedStore(for: network.chain).load(account: wallet.address), let withdrawal = shielded.withdrawals.first(where: { $0.id == id }) else { throw ShieldedError.withdrawalUnknown(id) }
        guard withdrawal.executedHash == nil else { throw ShieldedError.withdrawalNotReady("it has been executed already") }
        guard withdrawal.applied, let level = withdrawal.outboxLevel, let index = withdrawal.messageIndex else { throw ShieldedError.withdrawalNotReady("the rollup has not queued it yet") }
        let rollup = shieldedRollupFactory(config)
        guard try await rollup.cementedLevel() >= level else { throw ShieldedError.withdrawalNotReady("the rollup commitment covering it is not cemented yet (about 14 days after the unshield)") }
        let proof = try await rollup.outboxProof(outboxLevel: level, messageIndex: index)
        let execution = OutboxExecution(rollup: config.rollupAddress, cementedCommitment: proof.commitment, outputProof: proof.proof)
        let estimate = try await currentChain.estimateOutboxExecution(from: wallet, execution: execution)
        guard bridgeContext == context else { throw WalletError.contextChanged }
        return WithdrawalExecutionEstimate(estimate: estimate, context: context, withdrawal: withdrawal, execution: execution)
    }

    /// Executes the outbox message with the approved limits (S14) from the selected account,
    /// records the operation against the withdrawal and waits for its block.
    func executeWithdrawal(approved: WithdrawalExecutionEstimate, passphrase: String?) async throws -> String {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        guard let limits = approved.estimate.limits else { throw WalletError.notEstimated }
        guard approved.context == bridgeContext, canShield else { throw WalletError.contextChanged }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        let store = shieldedStore(for: network.chain)
        shieldProgress = .executing
        defer { shieldProgress = nil }
        let chain = currentChain
        let sent = try await chain.sendOutboxExecution(from: wallet, signer: signer, execution: approved.execution, limits: limits)
        try updateWithdrawals(account: wallet.address, store: store) { list in
            if let at = list.firstIndex(where: { $0.id == approved.withdrawal.id }) { list[at].executedHash = sent.hash }
        }
        shieldProgress = .waitingForLayer1
        do {
            _ = try await chain.waitForConfirmation(of: sent.hash)
        } catch where !sent.injected {
            throw WalletError.outcomeUnknown(sent.hash)
        }
        await refreshAfterOperation()
        return sent.hash
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
