import Foundation
import JavaScriptCore
import Security

/// Hosts the bundled Taquito script (`taquito-bridge.js`) inside JavaScriptCore and exposes
/// its exported functions to Swift as async calls.
///
/// `JSContext` is not thread-safe, so every touch of the context happens on one serial queue.
/// The polyfills in `TaquitoBridge/src/polyfills.js` call back into the `__signet` native object
/// installed here for timers, HTTP and randomness; those run on the same queue.
///
/// Private keys never enter the JavaScript runtime.
final class TaquitoBridge: @unchecked Sendable {
    enum BridgeError: LocalizedError {
        case bundleMissing
        case loadFailed(String)
        case javaScript(String)
        case notAFunction(String)

        var errorDescription: String? {
            switch self {
            case .bundleMissing: "taquito-bridge.js is missing from the app bundle (run `npm run build` in TaquitoBridge/)"
            case .loadFailed(let message): "Taquito bridge failed to load: \(message)"
            case .javaScript(let message): message
            case .notAFunction(let name): "TaquitoBridge.\(name) is not a function"
            }
        }
    }

    static let shared = TaquitoBridge()

    private let queue = DispatchQueue(label: "org.tezos.signet.taquito-bridge")
    private let session: URLSession
    private var context: JSContext?
    private var loadError: Error?
    private var timers: [Int: DispatchWorkItem] = [:]
    private var fetches: [Int: URLSessionDataTask] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Calls `TaquitoBridge.<name>(...args)` and awaits the result, unwrapping promises.
    func call(_ name: String, _ args: [any Sendable] = []) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            queue.async {
                do {
                    let context = try self.loadedContext()
                    guard let api = context.objectForKeyedSubscript("TaquitoBridge"),
                          let function = api.objectForKeyedSubscript(name),
                          !function.isUndefined
                    else { throw BridgeError.notAFunction(name) }

                    context.exception = nil
                    guard let result = function.call(withArguments: args) else {
                        throw BridgeError.javaScript("no result from \(name)")
                    }
                    if let exception = context.exception {
                        context.exception = nil
                        throw BridgeError.javaScript(exception.toString())
                    }
                    self.resolve(result, in: context, continuation: continuation)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Promise handling

    private func resolve(_ value: JSValue, in context: JSContext, continuation: CheckedContinuation<JSONValue, Error>) {
        guard value.isObject, let then = value.objectForKeyedSubscript("then"), !then.isUndefined else {
            continuation.resume(returning: JSONValue(bridged: value.toObject()))
            return
        }
        // Box the continuation so exactly one of the two blocks consumes it.
        final class Once: @unchecked Sendable {
            var continuation: CheckedContinuation<JSONValue, Error>?
            init(_ c: CheckedContinuation<JSONValue, Error>) { continuation = c }
        }
        let once = Once(continuation)
        let onFulfilled: @convention(block) (JSValue?) -> Void = { result in
            guard let c = once.continuation else { return }
            once.continuation = nil
            c.resume(returning: JSONValue(bridged: result?.toObject()))
        }
        let onRejected: @convention(block) (JSValue?) -> Void = { reason in
            guard let c = once.continuation else { return }
            once.continuation = nil
            let message = reason?.objectForKeyedSubscript("message")?.toString() ?? reason?.toString() ?? "unknown error"
            c.resume(throwing: BridgeError.javaScript(message))
        }
        context.exception = nil
        // Must be invoked as a method so `this` is the promise; a bare `then.call` throws and
        // would leak the continuation.
        value.invokeMethod("then", withArguments: [
            JSValue(object: onFulfilled, in: context)!,
            JSValue(object: onRejected, in: context)!,
        ])
        if let exception = context.exception, let c = once.continuation {
            once.continuation = nil
            context.exception = nil
            c.resume(throwing: BridgeError.javaScript(exception.toString()))
        }
    }

    // MARK: - Loading

    private func loadedContext() throws -> JSContext {
        dispatchPrecondition(condition: .onQueue(queue))
        if let context { return context }
        if let loadError { throw loadError }
        do {
            let context = try makeContext()
            self.context = context
            return context
        } catch {
            loadError = error
            throw error
        }
    }

    private func makeContext() throws -> JSContext {
        guard let url = Bundle.main.url(forResource: "taquito-bridge", withExtension: "js")
                ?? Bundle(for: TaquitoBridge.self).url(forResource: "taquito-bridge", withExtension: "js")
        else { throw BridgeError.bundleMissing }
        let source = try String(contentsOf: url, encoding: .utf8)

        guard let context = JSContext() else { throw BridgeError.loadFailed("could not create JSContext") }
        var firstException: String?
        context.exceptionHandler = { _, exception in
            if firstException == nil { firstException = exception?.toString() }
        }
        installConsole(in: context)
        installNatives(in: context)

        context.evaluateScript(source, withSourceURL: url)
        if let firstException { throw BridgeError.loadFailed(firstException) }
        guard let api = context.objectForKeyedSubscript("TaquitoBridge"), api.isObject else {
            throw BridgeError.loadFailed("TaquitoBridge global not defined after evaluating bundle")
        }
        // Route later uncaught exceptions to the log instead of silently swallowing them.
        context.exceptionHandler = { _, exception in
            NSLog("TaquitoBridge JS exception: %@", exception?.toString() ?? "?")
        }
        return context
    }

    private func installConsole(in context: JSContext) {
        let log: @convention(block) (String) -> Void = { NSLog("TaquitoBridge: %@", $0) }
        context.setObject(log, forKeyedSubscript: "__signet_log" as NSString)
        context.evaluateScript("var console = { log: __signet_log, info: __signet_log, warn: __signet_log, error: __signet_log, debug: function(){} };")
    }

    private func installNatives(in context: JSContext) {
        let native = JSValue(newObjectIn: context)!

        let setTimer: @convention(block) (Int, Double) -> Void = { [weak self] id, ms in
            guard let self else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.timers.removeValue(forKey: id) != nil else { return }
                self.context?.objectForKeyedSubscript("__signet_timerFired")?.call(withArguments: [id])
            }
            self.timers[id] = work
            self.queue.asyncAfter(deadline: .now() + .milliseconds(Int(ms)), execute: work)
        }
        let clearTimer: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers.removeValue(forKey: id)?.cancel()
        }
        let randomBytes: @convention(block) (Int) -> [UInt8] = { count in
            var bytes = [UInt8](repeating: 0, count: max(0, count))
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
            return bytes
        }
        let fetch: @convention(block) (Int, String, String, String, JSValue?) -> Void = { [weak self] id, urlString, method, headersJSON, body in
            self?.startFetch(id: id, urlString: urlString, method: method, headersJSON: headersJSON, body: body)
        }
        let cancelFetch: @convention(block) (Int) -> Void = { [weak self] id in
            self?.fetches.removeValue(forKey: id)?.cancel()
        }

        native.setObject(setTimer, forKeyedSubscript: "setTimer" as NSString)
        native.setObject(clearTimer, forKeyedSubscript: "clearTimer" as NSString)
        native.setObject(randomBytes, forKeyedSubscript: "randomBytes" as NSString)
        native.setObject(fetch, forKeyedSubscript: "fetch" as NSString)
        native.setObject(cancelFetch, forKeyedSubscript: "cancelFetch" as NSString)
        context.setObject(native, forKeyedSubscript: "__signet" as NSString)
    }

    // MARK: - fetch

    private func startFetch(id: Int, urlString: String, method: String, headersJSON: String, body: JSValue?) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let url = URL(string: urlString) else {
            finishFetch(id: id, error: "Invalid URL: \(urlString)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let data = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        }
        if let body, !body.isNull, !body.isUndefined {
            request.httpBody = body.toString().data(using: .utf8)
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.queue.async {
                guard self.fetches.removeValue(forKey: id) != nil else { return } // cancelled
                if let error {
                    self.finishFetch(id: id, error: error.localizedDescription)
                    return
                }
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 200
                let headerPairs = (http?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { acc, pair in
                    acc[String(describing: pair.key).lowercased()] = String(describing: pair.value)
                }
                let headersJSON = (try? JSONSerialization.data(withJSONObject: headerPairs)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                self.finishFetch(id: id, status: status, statusText: HTTPURLResponse.localizedString(forStatusCode: status), headersJSON: headersJSON, body: text)
            }
        }
        fetches[id] = task
        task.resume()
    }

    private func finishFetch(id: Int, status: Int = 0, statusText: String = "", headersJSON: String = "{}", body: String = "", error: String? = nil) {
        context?.objectForKeyedSubscript("__signet_fetchDone")?.call(withArguments: [
            id, status, statusText, headersJSON, body, error ?? NSNull(),
        ])
    }
}
