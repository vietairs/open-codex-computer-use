import Foundation

// Minimal blocking HTTP transport for the decision-model sidecar.
//
// This code runs inside the TCC-privileged app agent, so it is deliberately narrow: loopback http only, proxies
// disabled, no cookies or cache, redirects refused, response size capped, and one ephemeral session per call so no
// connection or credential state outlives a request. Callers block on a semaphore, which is safe because MCP handlers
// run on per-connection background threads and the session delegate runs on its own private serial queue; calling
// from the main thread is refused rather than risking a deadlock of the UI run loop.

public protocol DecisionModelTransport: Sendable {
    func postJSON(to url: URL, body: Data, timeout: TimeInterval, maxResponseBytes: Int) throws -> Data
}

/// One ephemeral URLSession per call; proxies disabled; no cookies/cache; redirects refused;
/// response capped; private serial delegate queue; throws .transport if called on the main thread.
public final class URLSessionDecisionModelTransport: DecisionModelTransport, @unchecked Sendable {
    // Immutable after init; `@unchecked Sendable` only because `AnyClass` is not Sendable.
    private let protocolClasses: [AnyClass]?

    public init() {
        protocolClasses = nil
    }

    /// Test injection of a URLProtocol stub, so tests never open a real socket.
    init(protocolClasses: [AnyClass]) {
        self.protocolClasses = protocolClasses
    }

    public func postJSON(to url: URL, body: Data, timeout: TimeInterval, maxResponseBytes: Int) throws -> Data {
        guard !Thread.isMainThread else {
            throw DecisionModelError.transport("postJSON must not be called on the main thread")
        }
        guard timeout > 0, maxResponseBytes > 0 else {
            throw DecisionModelError.transport("timeout and maxResponseBytes must be positive")
        }
        // Defence in depth: the endpoint is validated at the environment boundary, but this is a public entry point.
        guard url.scheme?.lowercased() == "http" else {
            throw DecisionModelError.unsupportedScheme(url.scheme ?? "")
        }
        guard let host = url.host, DecisionModelEndpoint.canonicalLoopbackHost(host) != nil else {
            throw DecisionModelError.nonLoopbackHost(url.host ?? "")
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.name = "OpenComputerUse.DecisionModelTransport"
        let delegate = TransportDelegate(maxResponseBytes: maxResponseBytes)
        let session = URLSession(
            configuration: makeConfiguration(timeout: timeout), delegate: delegate, delegateQueue: delegateQueue
        )
        // The session retains its delegate until invalidated; always invalidate so nothing leaks per call.
        defer { session.invalidateAndCancel() }

        let task = session.dataTask(with: request)
        task.resume()
        // The whole call, not just idle time, is bounded by `timeout`.
        if delegate.finished.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            throw DecisionModelError.timeout
        }
        return try delegate.result()
    }

    private func makeConfiguration(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // Explicitly disable every proxy kind rather than inheriting system settings.
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
            "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0,
        ]
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return configuration
    }
}

/// Collects one response on the session's private serial queue and signals `finished` exactly once.
/// State is lock-protected because `result()` is read from the calling thread.
private final class TransportDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let finished = DispatchSemaphore(value: 0)
    private let maxResponseBytes: Int
    private let lock = NSLock()
    private var data = Data()
    private var failure: DecisionModelError?
    private var didFinish = false

    init(maxResponseBytes: Int) {
        self.maxResponseBytes = maxResponseBytes
    }

    func result() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        return data
    }

    /// Records the first failure, cancels the task, and releases the waiting caller.
    private func fail(_ error: DecisionModelError, task: URLSessionTask) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
        task.cancel()
        signalOnce()
    }

    private func signalOnce() {
        lock.lock()
        let shouldSignal = !didFinish
        didFinish = true
        lock.unlock()
        if shouldSignal { finished.signal() }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
        fail(.redirectRefused, task: task)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return fail(.transport("response is not HTTP"), task: dataTask)
        }
        if (300..<400).contains(http.statusCode) {
            completionHandler(.cancel)
            return fail(.redirectRefused, task: dataTask)
        }
        guard (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            return fail(.httpStatus(http.statusCode), task: dataTask)
        }
        if http.expectedContentLength > Int64(maxResponseBytes) {
            completionHandler(.cancel)
            return fail(.responseTooLarge(limit: maxResponseBytes), task: dataTask)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        let overflow = data.count + chunk.count > maxResponseBytes
        if !overflow { data.append(chunk) }
        lock.unlock()
        if overflow { fail(.responseTooLarge(limit: maxResponseBytes), task: dataTask) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let mapped: DecisionModelError
            if let urlError = error as? URLError, urlError.code == .timedOut {
                mapped = .timeout
            } else {
                mapped = .transport(error.localizedDescription)
            }
            // A cancellation we caused keeps its original, more specific failure.
            lock.lock()
            if failure == nil { failure = mapped }
            lock.unlock()
        }
        signalOnce()
    }
}
