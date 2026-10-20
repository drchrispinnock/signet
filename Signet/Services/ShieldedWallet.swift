import Foundation

/// A TzEL address of ours: the fields of its payment address (the ML-KEM public keys included,
/// so the record alone can receive) and the next unused WOTS+ key index. The auth tree's leaves
/// live in a separate 2 MB file (`ShieldedWalletStore.loadLeaves`) and can be rebuilt from the
/// master key; the signing seed `ask_j` is never stored, it is derived when a shield is signed.
struct ShieldedAddress: Codable, Hashable, Sendable, Identifiable {
    var id: Int { index }
    let index: Int
    let dJ: String
    let authRoot: String
    let pubSeed: String
    let nkTag: String
    let ekV: String
    let ekD: String
    /// The next WOTS+ key index to sign with. Persisted *before* a signature is made: a key
    /// index used twice would leak the signing key.
    var nextKeyIndex: Int

    /// The record as the bridge's scan and witness builder take it.
    var bridgeRecord: [String: Any] {
        ["index": index, "dJ": dJ, "authRoot": authRoot, "pubSeed": pubSeed, "nkTag": nkTag, "ekV": ekV, "ekD": ekD]
    }
}

/// A deposit pool on the rollup funded from layer 1: `deposit:<pubkeyHash>` is what the
/// ticketer was asked to credit, and only the wallet that knows `blind` can shield it.
struct DepositPool: Codable, Hashable, Sendable, Identifiable {
    var id: String { pubkeyHash }
    let pubkeyHash: String
    let blind: String
    let addressIndex: Int
    /// The rollup's `auth_domain` the pool id was computed under.
    let authDomain: String
    /// What was sent to the ticketer for this pool, in mutez (the rollup's balance is the truth).
    var depositedMutez: String
    /// The layer 1 operation that funded it, once injected.
    var operationHash: String?
    /// The commitment of the note the latest shield from this pool created, until it is seen
    /// in the tree; the pool stays listed while its balance is nonzero.
    var shieldedCm: String?
    let created: Date
}

/// A note of ours found in the commitment tree.
struct ShieldedNote: Codable, Hashable, Sendable, Identifiable {
    var id: Int { index }
    /// Position in the commitment tree.
    let index: Int
    let cm: String
    let rseed: String
    let nullifier: String
    let valueMutez: String
    let addressIndex: Int
    var spent = false
    /// The memo it came with, when there was one (a shielded transfer's).
    var memo: String?

    var value: UInt64 { UInt64(valueMutez) ?? 0 }
}

/// An unshield handed to the operator: `amountMutez` leave for `recipient` on layer 1 through
/// the rollup's outbox. Its input notes stay reserved until the rollup spends them (`applied`);
/// then its outbox message is looked for on the rollup node, and once the commitment covering
/// it is cemented (about 14 days) the account can execute it on Tezos (`executedHash`).
struct ShieldedWithdrawal: Codable, Hashable, Sendable, Identifiable {
    var id: String { submissionID }
    let submissionID: String
    let recipient: String
    let amountMutez: String
    let rollupFeeMutez: String
    let producerFeeMutez: String
    /// The nullifiers of the notes it spends.
    let nullifiers: [String]
    let changeCm: String?
    /// The rollup level when it was submitted: its outbox message cannot be earlier.
    let submittedLevel: Int
    let created: Date
    /// The operator's layer 1 operation carrying it, when reported.
    var operationHash: String?
    /// The rollup has spent every input: the withdrawal is in its outbox.
    var applied = false
    var outboxLevel: Int?
    var messageIndex: Int?
    /// The layer 1 operation that executed the outbox message.
    var executedHash: String?

    var amount: UInt64 { UInt64(amountMutez) ?? 0 }
    var rollupFee: UInt64 { UInt64(rollupFeeMutez) ?? 0 }
    var producerFee: UInt64 { UInt64(producerFeeMutez) ?? 0 }
}

/// A shielded transfer handed to the operator: `amountMutez` to the payment address with
/// `recipientFingerprint`. Its input notes stay reserved until the rollup spends them.
struct ShieldedTransfer: Codable, Hashable, Sendable, Identifiable {
    var id: String { submissionID }
    let submissionID: String
    let recipientFingerprint: String
    /// The address-book name it was sent to, if any.
    let recipientName: String?
    let amountMutez: String
    let rollupFeeMutez: String
    let producerFeeMutez: String
    let memo: String
    let nullifiers: [String]
    let recipientCm: String
    let changeCm: String
    let created: Date
    var operationHash: String?
    /// The rollup has spent every input: the recipient has the note.
    var applied = false

    var amount: UInt64 { UInt64(amountMutez) ?? 0 }
}

/// A shielded address of someone else: the payment address as the reference JSON, under a
/// name, with its fingerprint (the hash of the canonical record) for checking against theirs.
struct ShieldedContact: Codable, Hashable, Sendable, Identifiable {
    var id: String { fingerprint }
    var name: String
    let fingerprint: String
    let address: [String: String]
    let created: Date
}

/// The shielded wallet of one account on one network: the master key and everything derived
/// or learned from the rollup. Each tz account has its own, so the dashboard's Shielded row is
/// that account's; they all live in one file per chain in the wallet directory
/// (`tzel-<chain>.json`, a private file, `ShieldedWalletFile`).
struct ShieldedWallet: Codable, Equatable, Sendable {
    let chain: String
    /// The random 251-bit master secret, hex. Everything else derives from it. Kept in the clear
    /// like an unencrypted tz key; a password option is to follow.
    let masterSk: String
    var addresses: [ShieldedAddress] = []
    /// Feeds the per-pool blind; every new pool advances it.
    var depositNonce: UInt64 = 0
    var pools: [DepositPool] = []
    var notes: [ShieldedNote] = []
    /// How many tree positions have been scanned.
    var scanned = 0
    /// How many rollup nullifiers have been checked against our notes.
    var nullifiersSeen = 0
    /// Every commitment in the rollup's tree, in order, as far as the scan has read it: an
    /// unshield proves its inputs against the tree, so it needs the whole thing.
    var leafCms: [String] = []
    /// Unshields handed to the operator, until their layer 1 side is done.
    var withdrawals: [ShieldedWithdrawal] = []
    /// Shielded transfers handed to the operator.
    var transfers: [ShieldedTransfer] = []

    init(chain: String, masterSk: String) {
        self.chain = chain
        self.masterSk = masterSk
    }

    private enum CodingKeys: String, CodingKey { case chain, masterSk, addresses, depositNonce, pools, notes, scanned, nullifiersSeen, leafCms, withdrawals, transfers }

    /// Fields added after version 2 was first written are absent from older files.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chain = try c.decode(String.self, forKey: .chain)
        masterSk = try c.decode(String.self, forKey: .masterSk)
        addresses = try c.decodeIfPresent([ShieldedAddress].self, forKey: .addresses) ?? []
        depositNonce = try c.decodeIfPresent(UInt64.self, forKey: .depositNonce) ?? 0
        pools = try c.decodeIfPresent([DepositPool].self, forKey: .pools) ?? []
        notes = try c.decodeIfPresent([ShieldedNote].self, forKey: .notes) ?? []
        scanned = try c.decodeIfPresent(Int.self, forKey: .scanned) ?? 0
        nullifiersSeen = try c.decodeIfPresent(Int.self, forKey: .nullifiersSeen) ?? 0
        leafCms = try c.decodeIfPresent([String].self, forKey: .leafCms) ?? []
        withdrawals = try c.decodeIfPresent([ShieldedWithdrawal].self, forKey: .withdrawals) ?? []
        transfers = try c.decodeIfPresent([ShieldedTransfer].self, forKey: .transfers) ?? []
    }

    /// A wallet with a fresh random master key.
    static func make(chain: String) -> ShieldedWallet {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        precondition(status == errSecSuccess, "no randomness for the shielded master key")
        bytes[31] &= 0x07
        return ShieldedWallet(chain: chain, masterSk: Hex.encode(bytes))
    }

    /// Unspent notes, in mutez.
    var balanceMutez: UInt64 { notes.filter { !$0.spent }.reduce(0) { $0 &+ $1.value } }
    var balance: Decimal { Decimal(balanceMutez) / Mutez.perTez }
    /// The nullifiers of notes an unshield or transfer in flight will spend.
    var reservedNullifiers: Set<String> { Set(withdrawals.filter { !$0.applied }.flatMap(\.nullifiers) + transfers.filter { !$0.applied }.flatMap(\.nullifiers)) }
    /// Unspent notes no unshield in flight has claimed.
    var availableNotes: [ShieldedNote] {
        let reserved = reservedNullifiers
        return notes.filter { !$0.spent && !reserved.contains($0.nullifier) }
    }
    var availableMutez: UInt64 { availableNotes.reduce(0) { $0 &+ $1.value } }
    var reservedMutez: UInt64 { balanceMutez &- availableMutez }

    func address(at index: Int) -> ShieldedAddress? { addresses.first { $0.index == index } }
    func pool(_ pubkeyHash: String) -> DepositPool? { pools.first { $0.pubkeyHash == pubkeyHash } }
}

/// `tzel-<chain>.json`: the network's operator token and one `ShieldedWallet` per tz account.
struct ShieldedWalletFile: Codable, Equatable, Sendable {
    static let currentVersion = 2
    var version = currentVersion
    let chain: String
    /// The operator's bearer token for submitting shields (never in the repository, never logged).
    var operatorToken: String?
    /// By the account's tz address.
    var accounts: [String: ShieldedWallet] = [:]
    /// A version 1 file held one wallet for the whole network; it is kept here until an
    /// account adopts it (`ShieldedWalletStore.adoptLegacyWallet`).
    var legacy: ShieldedWallet?
    /// Other people's shielded addresses, shared by every account on the network.
    var contacts: [ShieldedContact] = []

    init(chain: String, operatorToken: String? = nil, accounts: [String: ShieldedWallet] = [:], legacy: ShieldedWallet? = nil, contacts: [ShieldedContact] = []) {
        self.chain = chain
        self.operatorToken = operatorToken
        self.accounts = accounts
        self.legacy = legacy
        self.contacts = contacts
    }

    private enum CodingKeys: String, CodingKey { case version, chain, operatorToken, accounts, legacy, contacts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        chain = try c.decode(String.self, forKey: .chain)
        operatorToken = try c.decodeIfPresent(String.self, forKey: .operatorToken)
        accounts = try c.decodeIfPresent([String: ShieldedWallet].self, forKey: .accounts) ?? [:]
        legacy = try c.decodeIfPresent(ShieldedWallet.self, forKey: .legacy)
        contacts = try c.decodeIfPresent([ShieldedContact].self, forKey: .contacts) ?? []
    }
}

/// Where a network's shielded wallets are kept.
protocol ShieldedWalletStore: Sendable {
    func load(account: Address) throws -> ShieldedWallet?
    func save(_ wallet: ShieldedWallet, account: Address) throws
    func operatorToken() throws -> String?
    func setOperatorToken(_ token: String?) throws
    /// The version 1 file's single wallet, not yet an account's.
    func legacyWallet() throws -> ShieldedWallet?
    /// Makes the legacy wallet `account`'s (nothing happens when there is none or the account has one).
    func adoptLegacyWallet(for account: Address) throws
    /// The 65536 × 32 bytes of an address's auth tree leaves, if built.
    func loadLeaves(account: Address, addressIndex: Int) throws -> [UInt8]?
    func saveLeaves(_ leaves: [UInt8], account: Address, addressIndex: Int) throws
    /// The network's shielded address book.
    func contacts() throws -> [ShieldedContact]
    func saveContacts(_ contacts: [ShieldedContact]) throws
}

/// `tzel-<chain>.json` and `tzel-<chain>-<account>-auth<j>.bin` in the wallet directory, written
/// like the key files (S10: private from the first byte, atomic replace). The JSON is backed up
/// with the wallet; the leaves are not (2 MB each, rebuilt from the master key when missing).
struct FileShieldedWalletStore: ShieldedWalletStore {
    let directory: URL
    let chain: String

    static func walletFile(chain: String) -> String { "tzel-\(chain).json" }
    static func leavesFile(chain: String, account: Address, addressIndex: Int) -> String { "tzel-\(chain)-\(account.value)-auth\(addressIndex).bin" }
    /// Where a version 1 file kept its one address's leaves.
    static func legacyLeavesFile(chain: String, addressIndex: Int) -> String { "tzel-\(chain)-auth\(addressIndex).bin" }

    private var walletURL: URL { directory.appendingPathComponent(Self.walletFile(chain: chain)) }

    /// A version 1 file: one wallet for the network, with the token inside it.
    private struct LegacyFile: Decodable {
        let version: Int
        let chain: String
        let masterSk: String
        var addresses: [ShieldedAddress] = []
        var depositNonce: UInt64 = 0
        var pools: [DepositPool] = []
        var notes: [ShieldedNote] = []
        var scanned = 0
        var nullifiersSeen = 0
        var operatorToken: String?

        var file: ShieldedWalletFile {
            var wallet = ShieldedWallet(chain: chain, masterSk: masterSk)
            wallet.addresses = addresses; wallet.depositNonce = depositNonce; wallet.pools = pools; wallet.notes = notes
            wallet.scanned = scanned; wallet.nullifiersSeen = nullifiersSeen
            return ShieldedWalletFile(chain: chain, operatorToken: operatorToken, accounts: [:], legacy: wallet)
        }
    }

    private func read() throws -> ShieldedWalletFile? {
        guard let data = try PrivateFile.read(walletURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = header["version"] as? Int else {
            throw ShieldedError.unsupportedWalletVersion(0)
        }
        switch version {
        case 1: return try decoder.decode(LegacyFile.self, from: data).file
        case ShieldedWalletFile.currentVersion: return try decoder.decode(ShieldedWalletFile.self, from: data)
        default: throw ShieldedError.unsupportedWalletVersion(version)
        }
    }

    private func write(_ file: ShieldedWalletFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try PrivateFile.write(try encoder.encode(file), to: walletURL)
    }

    func load(account: Address) throws -> ShieldedWallet? { try read()?.accounts[account.value] }

    func save(_ wallet: ShieldedWallet, account: Address) throws {
        var file = try read() ?? ShieldedWalletFile(chain: chain)
        file.accounts[account.value] = wallet
        try write(file)
    }

    func operatorToken() throws -> String? { try read()?.operatorToken }

    func setOperatorToken(_ token: String?) throws {
        var file = try read() ?? ShieldedWalletFile(chain: chain)
        file.operatorToken = token
        try write(file)
    }

    func legacyWallet() throws -> ShieldedWallet? { try read()?.legacy }

    func adoptLegacyWallet(for account: Address) throws {
        guard var file = try read(), let legacy = file.legacy, file.accounts[account.value] == nil else { return }
        file.accounts[account.value] = legacy
        file.legacy = nil
        try write(file)
        for address in legacy.addresses {
            let old = directory.appendingPathComponent(Self.legacyLeavesFile(chain: chain, addressIndex: address.index))
            let new = directory.appendingPathComponent(Self.leavesFile(chain: chain, account: account, addressIndex: address.index))
            if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: new.path) {
                try? FileManager.default.moveItem(at: old, to: new)
            }
        }
    }

    func loadLeaves(account: Address, addressIndex: Int) throws -> [UInt8]? {
        guard let data = try PrivateFile.read(directory.appendingPathComponent(Self.leavesFile(chain: chain, account: account, addressIndex: addressIndex))) else { return nil }
        guard data.count == XMSSAuthTree.leavesBytes else { return nil }
        return [UInt8](data)
    }

    func saveLeaves(_ leaves: [UInt8], account: Address, addressIndex: Int) throws {
        precondition(leaves.count == XMSSAuthTree.leavesBytes)
        try PrivateFile.write(Data(leaves), to: directory.appendingPathComponent(Self.leavesFile(chain: chain, account: account, addressIndex: addressIndex)))
    }

    func contacts() throws -> [ShieldedContact] { try read()?.contacts ?? [] }

    func saveContacts(_ contacts: [ShieldedContact]) throws {
        var file = try read() ?? ShieldedWalletFile(chain: chain)
        file.contacts = contacts
        try write(file)
    }
}

/// For tests and previews: nothing touches the disk.
final class InMemoryShieldedWalletStore: ShieldedWalletStore, @unchecked Sendable {
    private let lock = NSLock()
    private var file: ShieldedWalletFile
    private var leaves: [String: [UInt8]] = [:]
    /// Every wallet ever saved, oldest first, so tests can check what was persisted when.
    private(set) var history: [ShieldedWallet] = []

    init(chain: String = "shadownet", wallets: [String: ShieldedWallet] = [:], legacy: ShieldedWallet? = nil) {
        file = ShieldedWalletFile(chain: chain, accounts: wallets, legacy: legacy)
    }

    func load(account: Address) throws -> ShieldedWallet? { lock.withLock { file.accounts[account.value] } }
    func save(_ wallet: ShieldedWallet, account: Address) throws { lock.withLock { file.accounts[account.value] = wallet; history.append(wallet) } }
    func operatorToken() throws -> String? { lock.withLock { file.operatorToken } }
    func setOperatorToken(_ token: String?) throws { lock.withLock { file.operatorToken = token } }
    func legacyWallet() throws -> ShieldedWallet? { lock.withLock { file.legacy } }
    func adoptLegacyWallet(for account: Address) throws {
        lock.withLock {
            guard let legacy = file.legacy, file.accounts[account.value] == nil else { return }
            file.accounts[account.value] = legacy
            file.legacy = nil
        }
    }
    func loadLeaves(account: Address, addressIndex: Int) throws -> [UInt8]? { lock.withLock { leaves["\(account.value)/\(addressIndex)"] } }
    func saveLeaves(_ leaves: [UInt8], account: Address, addressIndex: Int) throws { lock.withLock { self.leaves["\(account.value)/\(addressIndex)"] = leaves } }
    func contacts() throws -> [ShieldedContact] { lock.withLock { file.contacts } }
    func saveContacts(_ contacts: [ShieldedContact]) throws { lock.withLock { file.contacts = contacts } }
}

/// What can go wrong between the wallet, the rollup node, the proving service and the operator.
enum ShieldedError: LocalizedError, Equatable {
    case notAvailable(String)
    case operatorTokenMissing
    case rollupMismatch(served: String, expected: String)
    case rollupNotConfigured(String)
    case ticketerMismatch(configured: String, expected: String)
    case poolNotCredited(String)
    case poolTooSmall(balance: UInt64, fees: UInt64)
    case poolUnknown(String)
    case keysExhausted(Int)
    case proving(String)
    case operatorRefused(String)
    case submissionFailed(String)
    case badReply(String)
    case unsupportedWalletVersion(Int)
    case treeMissing(Int)
    case insufficientShielded(available: UInt64, needed: UInt64)
    case tooManyInputs(Int)
    case badRecipient(String)
    case feeChanged(from: UInt64, to: UInt64)
    case treeStale
    case withdrawalUnknown(String)
    case withdrawalNotReady(String)
    case badPaymentAddress(String)
    case contactExists(String)
    case memoTooLong
    /// The operator still has it: not a failure, but not delivered within the wait either.
    case submissionPending(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let network): "\(network) has no shielded transactions Signet knows how to reach."
        case .operatorTokenMissing: "Shielding needs the TzEL operator's access token. Enter it in Networks under Shielded Transactions."
        case .rollupMismatch(let served, let expected): "The rollup node serves \(served), not the rollup \(expected) this network shields on. Nothing was sent."
        case .rollupNotConfigured(let what): "The rollup is not ready: \(what). Nothing was sent."
        case .ticketerMismatch(let configured, let expected): "The rollup's bridge ticketer is \(configured), not \(expected). Nothing was sent."
        case .poolNotCredited(let pool): "The rollup has not credited deposit pool \(pool.prefix(8))… yet. Try shielding it again in a minute."
        case .poolTooSmall(let balance, let fees): "The pool holds \(AssetBalance.format(Decimal(balance) / Mutez.perTez, symbol: "tz")), less than the \(AssetBalance.format(Decimal(fees) / Mutez.perTez, symbol: "tz")) of fees a shield pays. Top it up with another deposit."
        case .poolUnknown(let pool): "Deposit pool \(pool.prefix(8))… is not one of this wallet's."
        case .keysExhausted(let index): "Shielded address \(index) has used all of its signing keys."
        case .proving(let detail): "The proving service could not prove the shield: \(detail)"
        case .operatorRefused(let detail): "The TzEL operator refused the shield: \(detail)"
        case .submissionFailed(let detail): "The operator could not deliver the shield to the rollup: \(detail)"
        case .badReply(let detail): "Unexpected reply from the rollup services: \(detail)"
        case .unsupportedWalletVersion(let version): "The shielded wallet file is version \(version), which this Signet does not read."
        case .treeMissing(let index): "The signing tree of shielded address \(index) is missing and could not be rebuilt."
        case .insufficientShielded(let available, let needed): "The shielded balance available is \(AssetBalance.format(Decimal(available) / Mutez.perTez, symbol: "tz")), less than the \(AssetBalance.format(Decimal(needed) / Mutez.perTez, symbol: "tz")) the unshield and its fees need."
        case .tooManyInputs(let count): "That amount would spend \(count) notes; an unshield can spend at most 7. Unshield a smaller amount first."
        case .badRecipient(let text): "“\(text)” is not a Tezos account (tz1 to tz4 or KT1)."
        case .feeChanged(let from, let to): "The rollup's fee changed from \(AssetBalance.format(Decimal(from) / Mutez.perTez, symbol: "tz")) to \(AssetBalance.format(Decimal(to) / Mutez.perTez, symbol: "tz")) since the estimate. Nothing was sent; the estimate will be made again."
        case .treeStale: "The rollup's commitment tree moved while the unshield was being prepared. Nothing was sent; try again."
        case .withdrawalUnknown(let id): "Withdrawal \(id) is not one of this wallet's."
        case .withdrawalNotReady(let detail): "This withdrawal cannot be executed on Tezos yet: \(detail)"
        case .badPaymentAddress(let detail): "That is not a shielded payment address: \(detail)"
        case .contactExists(let name): "That shielded address is already in the address book as “\(name)”."
        case .memoTooLong: "The memo must be at most 1024 bytes."
        case .submissionPending(let detail): "The operator has the request but has not delivered it to the rollup yet: \(detail). It stays listed; refresh later."
        }
    }
}

extension Address {
    /// The address as Michelson forges a `contract`: `00` and the curve tag before an implicit
    /// account's 20-byte hash, `01` before an originated contract's with a padding byte after.
    /// What a rollup outbox message names as the receiver of a `burn`.
    var forgedContract: String? {
        guard let bytes = Base58.checkDecode(value), bytes.count == 23 else { return nil }
        let payload = Array(bytes[3...])
        switch Array(bytes[0..<3]) {
        case [6, 161, 159]: return Hex.encode([0, 0] + payload)
        case [6, 161, 161]: return Hex.encode([0, 1] + payload)
        case [6, 161, 164]: return Hex.encode([0, 2] + payload)
        case [6, 161, 166]: return Hex.encode([0, 3] + payload)
        case [2, 90, 121]: return Hex.encode([1] + payload + [0])
        default: return nil
        }
    }
}

extension ShieldedAddress {
    /// The address as a payment address in the reference JSON form, what another wallet
    /// (Signet or the tzel CLI) takes as a recipient.
    var paymentAddressJSON: [String: String] {
        ["d_j": dJ, "auth_root": authRoot, "auth_pub_seed": pubSeed, "nk_tag": nkTag, "ek_v": ekV, "ek_d": ekD]
    }
}
