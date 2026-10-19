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

    var value: UInt64 { UInt64(valueMutez) ?? 0 }
}

/// The shielded wallet for one network: the master key and everything derived or learned from
/// the rollup. One per chain, in the wallet directory (`tzel-<chain>.json`, a private file).
struct ShieldedWallet: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
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
    /// The operator's bearer token for submitting shields (never in the repository, never logged).
    var operatorToken: String?

    init(chain: String, masterSk: String) {
        self.chain = chain
        self.masterSk = masterSk
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

    func address(at index: Int) -> ShieldedAddress? { addresses.first { $0.index == index } }
    func pool(_ pubkeyHash: String) -> DepositPool? { pools.first { $0.pubkeyHash == pubkeyHash } }
}

/// Where a network's shielded wallet is kept.
protocol ShieldedWalletStore: Sendable {
    func load() throws -> ShieldedWallet?
    func save(_ wallet: ShieldedWallet) throws
    /// The 65536 × 32 bytes of an address's auth tree leaves, if built.
    func loadLeaves(addressIndex: Int) throws -> [UInt8]?
    func saveLeaves(_ leaves: [UInt8], addressIndex: Int) throws
}

/// `tzel-<chain>.json` and `tzel-<chain>-auth<j>.bin` in the wallet directory, written like the
/// key files (S10: private from the first byte, atomic replace). The JSON is backed up with the
/// wallet; the leaves are not (2 MB each, rebuilt from the master key when missing).
struct FileShieldedWalletStore: ShieldedWalletStore {
    let directory: URL
    let chain: String

    static func walletFile(chain: String) -> String { "tzel-\(chain).json" }
    static func leavesFile(chain: String, addressIndex: Int) -> String { "tzel-\(chain)-auth\(addressIndex).bin" }

    private var walletURL: URL { directory.appendingPathComponent(Self.walletFile(chain: chain)) }

    func load() throws -> ShieldedWallet? {
        guard let data = try PrivateFile.read(walletURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wallet = try decoder.decode(ShieldedWallet.self, from: data)
        guard wallet.version == ShieldedWallet.currentVersion else {
            throw ShieldedError.unsupportedWalletVersion(wallet.version)
        }
        return wallet
    }

    func save(_ wallet: ShieldedWallet) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try PrivateFile.write(try encoder.encode(wallet), to: walletURL)
    }

    func loadLeaves(addressIndex: Int) throws -> [UInt8]? {
        guard let data = try PrivateFile.read(directory.appendingPathComponent(Self.leavesFile(chain: chain, addressIndex: addressIndex))) else { return nil }
        guard data.count == XMSSAuthTree.leavesBytes else { return nil }
        return [UInt8](data)
    }

    func saveLeaves(_ leaves: [UInt8], addressIndex: Int) throws {
        precondition(leaves.count == XMSSAuthTree.leavesBytes)
        try PrivateFile.write(Data(leaves), to: directory.appendingPathComponent(Self.leavesFile(chain: chain, addressIndex: addressIndex)))
    }
}

/// For tests and previews: nothing touches the disk.
final class InMemoryShieldedWalletStore: ShieldedWalletStore, @unchecked Sendable {
    private let lock = NSLock()
    private var wallet: ShieldedWallet?
    private var leaves: [Int: [UInt8]] = [:]
    /// Every wallet ever saved, oldest first, so tests can check what was persisted when.
    private(set) var history: [ShieldedWallet] = []

    init(wallet: ShieldedWallet? = nil) { self.wallet = wallet }

    func load() throws -> ShieldedWallet? { lock.withLock { wallet } }
    func save(_ wallet: ShieldedWallet) throws { lock.withLock { self.wallet = wallet; history.append(wallet) } }
    func loadLeaves(addressIndex: Int) throws -> [UInt8]? { lock.withLock { leaves[addressIndex] } }
    func saveLeaves(_ leaves: [UInt8], addressIndex: Int) throws { lock.withLock { self.leaves[addressIndex] = leaves } }
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
        }
    }
}
