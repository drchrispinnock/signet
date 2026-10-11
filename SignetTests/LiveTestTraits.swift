import Foundation
import Testing
@testable import Signet

/// Live tests are opt-in (S24). They reach public testnets, faucets and the relay, originate
/// contracts and spend test tez, so categorisation by tag is not enough: each is also gated on
/// an environment variable the runner must set on purpose, e.g.
///
///     TEST_RUNNER_SIGNET_NETWORK_TESTS=1 xcodebuild … test
///
/// (`xcodebuild` passes `TEST_RUNNER_`-prefixed variables to the test host.)
extension Trait where Self == ConditionTrait {
    static var liveNetwork: Self {
        .enabled(if: ProcessInfo.processInfo.environment["SIGNET_NETWORK_TESTS"] == "1",
                 "Live network test: set TEST_RUNNER_SIGNET_NETWORK_TESTS=1 to run it")
    }

    /// Tests that read the developer's real `~/.tezos-client` or `~/.signet` state.
    static var realWalletState: Self {
        .enabled(if: ProcessInfo.processInfo.environment["SIGNET_REAL_WALLET_TESTS"] == "1",
                 "Reads the real wallet directories: set TEST_RUNNER_SIGNET_REAL_WALLET_TESTS=1 to run it")
    }
}

/// The bridge is one shared JavaScript context. Tests that swap its storage or event handler run
/// one at a time through here, whatever suite they are in.
actor SharedBridge {
    static let shared = SharedBridge()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        while busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        return try await body()
    }
}
