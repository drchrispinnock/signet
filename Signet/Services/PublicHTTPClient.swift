import Foundation

/// Untrusted URLs use the system TLS client with a pinned, validated DNS answer. URLSession
/// resolves hosts again after a preflight check; --resolve keeps the connection on the checked
/// address while preserving the original HTTPS hostname for certificate validation and SNI.
/// Proxies, user curl configuration and automatic redirects are disabled. Each artwork redirect
/// is a separate validated/pinned request. Request configuration is private and short-lived.
enum PublicHTTPClient {
    private static let gate = BridgeCallGate(limit: 6)
    struct Reply: Sendable {
        let data: Data
        let status: Int
        let headers: [String: String]
    }

    private final class Cancellation: @unchecked Sendable {
        let lock = NSLock()
        var process: Process?
        var cancelled = false
        func cancel() { lock.withLock { cancelled = true; if let process, process.isRunning { process.terminate() } } }
        func launch(_ process: Process) throws {
            try lock.withLock {
                if cancelled { throw CancellationError() }
                try process.run()
                self.process = process
            }
        }
        func check() throws { try lock.withLock { if cancelled { throw CancellationError() } } }
    }

    static func data(for request: URLRequest, limit: Int, followRedirects: Bool = false) async throws -> Reply {
        try await gate.acquire()
        defer { Task { await gate.release() } }
        try Task.checkCancellation()
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        var current = request
                        for hop in 0...5 {
                            try cancellation.check()
                            let reply = try perform(current, limit: limit, cancellation: cancellation)
                            if (300..<400).contains(reply.status) {
                                guard followRedirects, hop < 5, let location = reply.headers["location"],
                                      let base = current.url, let target = URL(string: location, relativeTo: base)?.absoluteURL,
                                      EndpointPolicy.isPublicHTTPS(target) else { throw URLError(.redirectToNonExistentLocation) }
                                // Artwork requests carry no credentials, cookies or bodies.
                                current = URLRequest(url: target)
                                continue
                            }
                            continuation.resume(returning: reply)
                            return
                        }
                        throw URLError(.httpTooManyRedirects)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    static func configuration(for request: URLRequest, addresses: [String], limit: Int) throws -> String {
        guard let url = request.url, EndpointPolicy.isPublicHTTPS(url), let host = url.host(percentEncoded: false),
              !addresses.isEmpty, addresses.allSatisfy({ !EndpointPolicy.isLocalOrPrivateHost($0) }),
              addresses.allSatisfy({ $0.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" } }),
              limit > 0 else { throw URLError(.unsupportedURL) }
        func quoted(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") + "\""
        }
        let port = url.port ?? 443
        let address = addresses.prefix(8).map { $0.contains(":") ? "[\($0)]" : $0 }.joined(separator: ",")
        let method = request.httpMethod ?? "GET"
        guard method.count <= 16, method.allSatisfy({ $0.isASCII && $0.isUppercase }) else { throw URLError(.badURL) }
        var lines = ["url = \(quoted(url.absoluteString))", "resolve = \(quoted("\(host):\(port):\(address)"))",
                     "noproxy = \"*\"", "proto = \"=https\"", "http1.1", "include", "silent", "show-error",
                     "connect-timeout = 15", "max-time = 60", "max-filesize = \(limit)", "request = \(quoted(method))"]
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            guard !key.contains("\r"), !key.contains("\n"), !value.contains("\r"), !value.contains("\n") else { throw URLError(.badURL) }
            lines.append("header = \(quoted("\(key): \(value)"))")
        }
        if let body = request.httpBody {
            guard body.count <= 1 << 20, let text = String(data: body, encoding: .utf8) else { throw URLError(.dataLengthExceedsMaximum) }
            lines.append("data-raw = \(quoted(text))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func perform(_ request: URLRequest, limit: Int, cancellation: Cancellation) throws -> Reply {
        guard let host = request.url?.host(percentEncoded: false) else { throw URLError(.badURL) }
        let addresses = EndpointPolicy.publicAddresses(host)
        let config = try configuration(for: request, addresses: addresses, limit: limit)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signet-http-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("request")
        try PrivateFile.write(Data(config.utf8), to: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-q", "--config", file.path]
        // No proxy/env overrides, credential helpers or user configuration are inherited.
        process.environment = ["PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try cancellation.launch(process)
        var bytes = Data()
        do {
            while let chunk = try output.fileHandleForReading.read(upToCount: 32 * 1024), !chunk.isEmpty {
                try cancellation.check()
                guard bytes.count + chunk.count <= limit + 64 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
                bytes.append(chunk)
            }
        } catch {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw error
        }
        process.waitUntilExit()
        try cancellation.check()
        guard process.terminationStatus == 0 else { throw URLError(.cannotLoadFromNetwork) }
        return try decode(bytes, limit: limit)
    }

    static func decode(_ bytes: Data, limit: Int) throws -> Reply {
        var remaining = bytes
        for _ in 0..<8 {
            guard let boundary = remaining.range(of: Data("\r\n\r\n".utf8)), boundary.lowerBound <= 64 * 1024,
                  let header = String(data: remaining[..<boundary.lowerBound], encoding: .utf8) else { throw URLError(.cannotParseResponse) }
            let lines = header.components(separatedBy: "\r\n")
            guard let statusText = lines.first?.split(separator: " ").dropFirst().first, let status = Int(statusText) else { throw URLError(.cannotParseResponse) }
            remaining = Data(remaining[boundary.upperBound...])
            if (100..<200).contains(status) { continue }
            guard remaining.count <= limit else { throw URLError(.dataLengthExceedsMaximum) }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            return Reply(data: remaining, status: status, headers: headers)
        }
        throw URLError(.cannotParseResponse)
    }
}
