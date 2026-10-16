import Foundation
import Testing
@testable import Signet

/// F23 is a measurement, not a timing gate. Opt in explicitly; all files are synthetic and temporary.
@MainActor
struct WalletLockMeasurementTests {
    struct Sample: Codable {
        let aliases: Int
        let contention: String
        let repeatIndex: Int
        let elapsedMS: Double
        let heartbeatGapMS: Double
        let timedOut: Bool
    }
    private final class Heartbeat {
        var last = ContinuousClock.now
        var largest = Duration.zero
        func beat() { let now = ContinuousClock.now; largest = max(largest, last.duration(to: now)); last = now }
    }
    private func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SIGNET_LOCK_BENCHMARK"] == "1"), .timeLimit(.minutes(10)))
    func measureSyntheticWalletInitializationUnderProcessLock() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("signet-lock-measurement-\(UUID().uuidString)")
        try PrivateFile.hardenDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        var samples: [Sample] = []
        for count in [1, 1000] {
            let directory = root.appendingPathComponent("\(count)")
            try PrivateFile.hardenDirectory(directory)
            let rows = (0..<count).map { ["name":"synthetic-\($0)", "value":"tz1VSUr8wwNhLAzempoch5d6hLRiTh8Cjcjb"] }
            try PrivateFile.write(try JSONSerialization.data(withJSONObject: rows), to: directory.appendingPathComponent(TezosClientStore.publicKeyHashesFile))
            for file in [TezosClientStore.publicKeysFile, TezosClientStore.secretKeysFile] {
                try PrivateFile.write(Data("[]".utf8), to: directory.appendingPathComponent(file))
            }
            for (name, seconds) in [("uncontended", 0.0), ("250ms", 0.25), ("1s", 1.0), ("timeout", 6.0)] {
                for index in 0..<10 {
                    let process = Process(), release = Pipe(), ready = Pipe()
                    if seconds > 0 {
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                        process.arguments = ["-c", "import fcntl,select,sys\nf=open(sys.argv[1],'a+')\nfcntl.lockf(f,fcntl.LOCK_EX)\nprint('locked',flush=True)\nselect.select([sys.stdin],[],[],float(sys.argv[2]))\n", directory.appendingPathComponent(TezosClientStore.lockFile).path, String(seconds)]
                        process.standardOutput = ready; process.standardInput = release
                        try process.run()
                        #expect(ready.fileHandleForReading.readData(ofLength: 7) == Data("locked\n".utf8))
                    }
                    let beat = Heartbeat()
                    let started = AsyncStream<Void>.makeStream()
                    let ticker = Task { @MainActor in
                        beat.beat(); started.continuation.yield(())
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .milliseconds(5)) } catch { break }
                            beat.beat()
                        }
                    }
                    var iterator = started.stream.makeAsyncIterator()
                    _ = await iterator.next()
                    let beginning = ContinuousClock.now
                    let model = WalletViewModel(chain: MockChainService(), walletStore: TezosClientStore(directory: directory), nodeProbe: { _ in throw URLError(.notConnectedToInternet) })
                    let elapsed = beginning.duration(to: .now)
                    // The delayed heartbeat must get a turn after the synchronous load finishes.
                    try await Task.sleep(for: .milliseconds(15))
                    ticker.cancel(); await ticker.value
                    if seconds > 0 {
                        try release.fileHandleForWriting.close()
                        process.waitUntilExit()
                        #expect(process.terminationStatus == 0)
                    }
                    let timedOut = model.errorMessage != nil
                    #expect(timedOut == (name == "timeout"))
                    #expect(model.wallets.count == (timedOut ? 0 : count))
                    samples.append(Sample(aliases: count, contention: name, repeatIndex: index, elapsedMS: milliseconds(elapsed), heartbeatGapMS: milliseconds(beat.largest), timedOut: timedOut))
                }
            }
        }
        let output = ProcessInfo.processInfo.environment["SIGNET_LOCK_BENCHMARK_OUTPUT"] ?? root.deletingLastPathComponent().appendingPathComponent("signet-lock-measurement.json").path
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateFile.write(try encoder.encode(samples), to: URL(fileURLWithPath: output))
        print("F23: wrote \(samples.count) synthetic initialization measurements to \(output)")
    }
}
