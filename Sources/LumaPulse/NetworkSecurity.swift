import Foundation

enum NetworkPolicy {
    static func https(_ url: URL, hosts: [String]? = nil) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        guard let hosts else { return true }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func article(_ value: String, source: FeedSource) -> Bool {
        guard let url = URL(string: value) else { return false }
        let hosts: [String]
        switch source.id {
        case "bbc": hosts = ["bbc.com", "bbc.co.uk"]
        case "cnbc": hosts = ["cnbc.com"]
        case "coindesk": hosts = ["coindesk.com"]
        case "fxstreet": hosts = ["fxstreet.com"]
        case "fed": hosts = ["federalreserve.gov"]
        default: hosts = URL(string: source.url)?.host.map { [$0] } ?? []
        }
        return https(url, hosts: hosts)
    }
    static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 2
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return config
    }
}

class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let next = request.url, NetworkPolicy.https(next), next.host?.lowercased() == task.originalRequest?.url?.host?.lowercased() else { completionHandler(nil); return }
        completionHandler(request)
    }
}

private final class RequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false
    func install(_ task: URLSessionTask) { lock.lock(); self.task = task; let cancelled = cancelled; lock.unlock(); if cancelled { task.cancel() } }
    func cancel() { lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel() }
}

final class LimitedHTTP: SameOriginRedirectDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = LimitedHTTP()
    private struct Pending {
        var data = Data()
        var response: HTTPURLResponse?
        let limit: Int
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
    }
    private let lock = NSLock()
    private var pending: [Int: Pending] = [:]
    private lazy var session: URLSession = {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: NetworkPolicy.configuration, delegate: self, delegateQueue: queue)
    }()
    func get(_ url: URL, limit: Int = 1_048_576, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard NetworkPolicy.https(url) else { throw URLError(.unsupportedURL) }
        let cancellation = RequestCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var request = URLRequest(url: url)
                request.setValue("LumaPulse/1.0 (macOS news reader)", forHTTPHeaderField: "User-Agent")
                for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
                lock.lock()
                let task = session.dataTask(with: request)
                pending[task.taskIdentifier] = Pending(limit: limit, continuation: continuation)
                lock.unlock()
                cancellation.install(task); task.resume()
            }
        } onCancel: { cancellation.cancel() }
    }
    private func finish(_ task: URLSessionTask, _ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock(); let item = pending.removeValue(forKey: task.taskIdentifier); lock.unlock()
        item?.continuation.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        guard let item = pending[dataTask.taskIdentifier] else { lock.unlock(); completionHandler(.cancel); return }
        let allowed = response.expectedContentLength <= Int64(item.limit) && response is HTTPURLResponse
        if allowed { pending[dataTask.taskIdentifier]?.response = response as? HTTPURLResponse }
        lock.unlock()
        if allowed { completionHandler(.allow) }
        else { finish(dataTask, .failure(URLError(.dataLengthExceedsMaximum))); completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let item = pending[dataTask.taskIdentifier] else { lock.unlock(); return }
        let exceeded = item.data.count + data.count > item.limit
        if !exceeded { pending[dataTask.taskIdentifier]?.data.append(data) }
        lock.unlock()
        if exceeded { finish(dataTask, .failure(URLError(.dataLengthExceedsMaximum))); dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let item = pending[task.taskIdentifier]; lock.unlock()
        if let error { finish(task, .failure(error)) }
        else if let item, let response = item.response { finish(task, .success((item.data, response))) }
        else { finish(task, .failure(URLError(.badServerResponse))) }
    }
}
