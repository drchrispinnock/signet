import Foundation
import os

/// The XMSS-style authentication tree of a TzEL address (spec § Authentication): 65536 WOTS+
/// keys (w = 4, 133 chains), each compressed by an L-tree into a leaf, the leaves hashed up
/// into the `auth_root` a payment address carries. Every signature consumes one key index and
/// needs that key's sibling path, so the leaves are built once per address and kept.
///
/// This is the one piece of the protocol done natively: about 44 million BLAKE2s hashes, which
/// the bridge's JavaScript takes minutes over and `tzel_blake2s.c` takes seconds, across every
/// core. The leaf and node functions there are a port of `authLeaf` / `xmssTreeNode` in
/// `TaquitoBridge/src/tzel.js`; `ShieldedTests` checks the two agree leaf for leaf and that the
/// full tree gives the shared vectors' roots.
enum XMSSAuthTree {
    static let depth = 16
    static let size = 1 << depth
    static let chains = 133
    static let wotsW = 4
    static let feltBytes = 32
    /// `leaves` buffers are `size * feltBytes` bytes.
    static let leavesBytes = size * feltBytes

    /// A domain tag felt: the label's bytes reversed into the low positions.
    static func feltTag(_ label: String) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: feltBytes)
        for (i, byte) in label.utf8.reversed().enumerated() { out[i] = byte }
        return out
    }

    static func feltOfInt(_ n: UInt64) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: feltBytes)
        for i in 0..<8 { out[i] = UInt8(truncatingIfNeeded: n >> (8 * UInt64(i))) }
        return out
    }

    /// Unpersonalized BLAKE2s truncated to 251 bits, as the key hierarchy uses.
    static func hash(_ data: [UInt8]) -> [UInt8] {
        var out = Blake2s.hash(data)
        out[31] &= 0x07
        return out
    }

    static func hashTwo(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] { hash(a + b) }

    /// `ask_j = H(ask_base, felt(j))`.
    static func deriveAsk(askBase: [UInt8], j: UInt32) -> [UInt8] { hashTwo(askBase, feltOfInt(UInt64(j))) }

    /// `pub_seed = H(tag("xmss-ps") ‖ ask_j)`.
    static func pubSeed(askJ: [UInt8]) -> [UInt8] { hash(feltTag("xmss-ps") + askJ) }

    /// `key_seed = H(tag("xmss-sk") ‖ ask_j ‖ felt(key_idx))`.
    static func keySeed(askJ: [UInt8], keyIdx: UInt32) -> [UInt8] { hash(feltTag("xmss-sk") + askJ + feltOfInt(UInt64(keyIdx))) }

    /// One leaf, for tests and spot checks; `buildLeaves` does the whole tree.
    static func leaf(askJ: [UInt8], pubSeed: [UInt8], keyIdx: Int) -> [UInt8] {
        precondition(askJ.count == feltBytes && pubSeed.count == feltBytes && (0..<size).contains(keyIdx))
        var out = [UInt8](repeating: 0, count: feltBytes)
        askJ.withUnsafeBufferPointer { ask in
            pubSeed.withUnsafeBufferPointer { seed in
                out.withUnsafeMutableBufferPointer { tzel_auth_leaf(ask.baseAddress, seed.baseAddress, UInt32(keyIdx), $0.baseAddress) }
            }
        }
        return out
    }

    /// All 65536 leaves, concatenated, built across every core. `progress` is called from the
    /// worker threads with the number of leaves done so far (a few hundred at a time).
    static func buildLeaves(askJ: [UInt8], pubSeed: [UInt8], progress: (@Sendable (Int) -> Void)? = nil) -> [UInt8] {
        precondition(askJ.count == feltBytes && pubSeed.count == feltBytes)
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: leavesBytes)
        defer { buffer.deallocate() }
        let out = UnsafeSlot(buffer)
        let ask = UnsafeSlot(copying: askJ), seed = UnsafeSlot(copying: pubSeed)
        defer { ask.buffer.deallocate(); seed.buffer.deallocate() }
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 32))
        let done = OSAllocatedUnfairLock(initialState: 0)
        let reportEvery = 512
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            var sinceReport = 0
            var index = worker
            while index < size {
                tzel_auth_leaf(ask.buffer.baseAddress, seed.buffer.baseAddress, UInt32(index), out.buffer.baseAddress! + index * feltBytes)
                index += workers
                sinceReport += 1
                if sinceReport == reportEvery, let progress {
                    let add = sinceReport
                    let total = done.withLock { $0 += add; return $0 }
                    sinceReport = 0
                    progress(total)
                }
            }
            if sinceReport > 0, let progress {
                let add = sinceReport
                let total = done.withLock { $0 += add; return $0 }
                progress(total)
            }
        }
        return Array(buffer)
    }

    /// Every level of the tree, leaves first: `levels[0]` is `leaves`, `levels[16]` the root.
    static func levels(pubSeed: [UInt8], leaves: [UInt8]) -> [[UInt8]] {
        precondition(leaves.count == leavesBytes, "an auth tree has 65536 leaves")
        precondition(pubSeed.count == feltBytes)
        var levels = [leaves]
        for level in 0..<depth {
            let below = levels[level]
            let count = below.count / feltBytes / 2
            var above = [UInt8](repeating: 0, count: count * feltBytes)
            pubSeed.withUnsafeBufferPointer { seed in
                below.withUnsafeBufferPointer { low in
                    above.withUnsafeMutableBufferPointer { high in
                        for i in 0..<count {
                            tzel_auth_node(seed.baseAddress, UInt32(level), UInt32(i), low.baseAddress! + 2 * i * feltBytes, low.baseAddress! + (2 * i + 1) * feltBytes, high.baseAddress! + i * feltBytes)
                        }
                    }
                }
            }
            levels.append(above)
        }
        return levels
    }

    static func root(levels: [[UInt8]]) -> [UInt8] { levels[depth] }

    static func root(pubSeed: [UInt8], leaves: [UInt8]) -> [UInt8] { root(levels: levels(pubSeed: pubSeed, leaves: leaves)) }

    /// The 16 sibling nodes of leaf `index`, leaf level first.
    static func path(levels: [[UInt8]], index: Int) -> [[UInt8]] {
        precondition((0..<size).contains(index))
        return (0..<depth).map { level in
            let sibling = (index >> level) ^ 1
            return Array(levels[level][(sibling * feltBytes)..<((sibling + 1) * feltBytes)])
        }
    }

    /// A pointer handed to the parallel workers; each writes its own disjoint leaves.
    private struct UnsafeSlot: @unchecked Sendable {
        let buffer: UnsafeMutableBufferPointer<UInt8>
        init(_ buffer: UnsafeMutableBufferPointer<UInt8>) { self.buffer = buffer }
        init(copying bytes: [UInt8]) {
            buffer = .allocate(capacity: bytes.count)
            _ = buffer.initialize(from: bytes)
        }
    }
}
