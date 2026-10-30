import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one way native code reads an HTTP reply from a node, an indexer, a faucet or a name
/// service (S19). The body is taken as a stream and dropped the moment it passes the caller's
/// byte cap, declared length or not, so a misbehaving or hostile server cannot make the app
/// accumulate an arbitrarily large reply before rejecting it; a JSON reply is also checked
/// against structure and string budgets (`JSONBudget`) before anything parses it. The bridge's
/// own fetches have the same protections in `TaquitoBridge`; this is for the `URLSession`
/// readers outside it.
enum BoundedHTTP {
    struct Reply: Sendable {
        let data: Data
        let status: Int
        var isSuccess: Bool { (200..<300).contains(status) }
    }

    /// Structure budgets for a JSON body, checked before parsing.
    struct JSONLimits: Sendable {
        var depth: Int
        var nodes: Int
        var string: Int
        /// A chain id, a balance, a block header, a name lookup: a handful of values.
        static let small = JSONLimits(depth: 16, nodes: 2_000, string: 16 << 10)
        /// One account record, a faucet reply: a few hundred fields at most.
        static let record = JSONLimits(depth: 32, nodes: 20_000, string: 64 << 10)
        /// A page of operations, tokens or bakers; contract parameters nest deeply and token
        /// metadata can carry long URIs.
        static let page = JSONLimits(depth: 128, nodes: 250_000, string: 1 << 20)
    }

    enum Failure: LocalizedError, Equatable {
        case notHTTP
        case tooLarge(limit: Int)
        case overBudget

        var errorDescription: String? {
            switch self {
            case .notHTTP: "The server did not answer over HTTP."
            case .tooLarge(let limit): "The server's reply was larger than the \(limit / 1024) KB allowed."
            case .overBudget: "The server's reply was more complex than allowed."
            }
        }
    }

    private final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var data = Data()
        private var continuation: CheckedContinuation<Reply, Error>?

        init(limit: Int, continuation: CheckedContinuation<Reply, Error>) {
            self.limit = limit
            self.continuation = continuation
        }

        func finish(_ result: Result<Reply, Error>) {
            let pending = lock.withLock {
                let pending = continuation
                continuation = nil
                data = Data()
                return pending
            }
            pending?.resume(with: result)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse else {
                finish(.failure(Failure.notHTTP))
                completionHandler(.cancel)
                return
            }
            guard http.expectedContentLength <= Int64(limit) else {
                finish(.failure(Failure.tooLarge(limit: limit)))
                completionHandler(.cancel)
                #if canImport(FoundationNetworking)
                dataTask.cancel()   // swift-corelibs-foundation does not stop the transfer for .cancel
                #endif
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            let overflow = lock.withLock {
                guard continuation != nil else { return false }
                guard chunk.count <= limit - data.count else { return true }
                data.append(chunk)
                return false
            }
            if overflow {
                finish(.failure(Failure.tooLarge(limit: limit)))
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { finish(.failure(error)); return }
            guard let http = task.response as? HTTPURLResponse else { finish(.failure(Failure.notHTTP)); return }
            let body = lock.withLock { data }
            finish(.success(Reply(data: body, status: http.statusCode)))
        }
    }

    #if canImport(FoundationNetworking)
    /// swift-corelibs-foundation never calls a task's own delegate, and frees a short-lived
    /// session unsafely, so each caller's session gets one long-lived companion made from its
    /// configuration (protocol classes included) whose delegate passes every task's events to
    /// that task's collector.
    private final class Router: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var collectors: [Int: Collector] = [:]

        private static let lock = NSLock()
        /// Keyed by the caller's session, which is kept too so its identifier is never reused.
        nonisolated(unsafe) private static var companions: [ObjectIdentifier: (original: URLSession, routed: URLSession, router: Router)] = [:]

        static func companion(for session: URLSession) -> (URLSession, Router) {
            lock.withLock {
                if let found = companions[ObjectIdentifier(session)] { return (found.routed, found.router) }
                let router = Router()
                let routed = URLSession(configuration: session.configuration, delegate: router, delegateQueue: nil)
                companions[ObjectIdentifier(session)] = (session, routed, router)
                return (routed, router)
            }
        }

        func register(_ collector: Collector, for task: URLSessionTask) {
            lock.withLock { collectors[task.taskIdentifier] = collector }
        }

        private func collector(for task: URLSessionTask) -> Collector? { lock.withLock { collectors[task.taskIdentifier] } }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            guard let collector = collector(for: dataTask) else { completionHandler(.cancel); return }
            collector.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            collector(for: dataTask)?.urlSession(session, dataTask: dataTask, didReceive: chunk)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let collector = lock.withLock { collectors.removeValue(forKey: task.taskIdentifier) }
            collector?.urlSession(session, task: task, didCompleteWithError: error)
        }
    }
    #endif

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var collector: Collector?
        private var cancelled = false

        func start(_ task: URLSessionDataTask, collector: Collector) {
            lock.withLock {
                self.task = task
                self.collector = collector
                if cancelled {
                    collector.finish(.failure(CancellationError()))
                    task.cancel()
                } else { task.resume() }
            }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                collector?.finish(.failure(CancellationError()))
                task?.cancel()
            }
        }
    }

    /// Reads a reply with a task-local delegate. Limits are enforced before retaining each
    /// chunk, and rejection/caller cancellation stops the underlying request explicitly.
    static func data(for request: URLRequest, session: URLSession, limit: Int, json: JSONLimits? = .small) async throws -> Reply {
        guard limit >= 0 else { throw Failure.tooLarge(limit: limit) }
        let cancellation = Cancellation()
        let reply: Reply = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let collector = Collector(limit: limit, continuation: continuation)
                #if canImport(FoundationNetworking)
                let (routed, router) = Router.companion(for: session)
                let task = routed.dataTask(with: request)
                router.register(collector, for: task)
                #else
                let task = session.dataTask(with: request)
                task.delegate = collector
                #endif
                cancellation.start(task, collector: collector)
            }
        } onCancel: { cancellation.cancel() }
        try Task.checkCancellation()
        if let json, !JSONBudget.accepts(reply.data, depthLimit: json.depth, nodeLimit: json.nodes, stringLimit: json.string) {
            throw Failure.overBudget
        }
        return reply
    }
}
