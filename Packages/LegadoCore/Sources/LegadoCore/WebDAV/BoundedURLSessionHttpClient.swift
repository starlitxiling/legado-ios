import Foundation

/// 实现方必须在累计响应体超过上限之前中止传输，不能完整读取后才检查。
public protocol ResponseLimitedHttpClient: HttpClient {
    func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse
}

/// Replay 的响应已经由测试预置；此处只验证限额，不产生真实下载。
extension ReplayHttpClient: ResponseLimitedHttpClient {
    public func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        let response = try await send(request)
        guard maximumResponseBytes >= 0, response.body.count <= maximumResponseBytes,
              Int64(response.headers.httpHeader("Content-Length") ?? "") ?? 0 <= Int64(maximumResponseBytes) else {
            throw WebDavError.responseTooLarge
        }
        return response
    }
}

public struct BoundedURLSessionHttpClient: ResponseLimitedHttpClient {
    private let protocolClasses: [AnyClass]

    public init(protocolClasses: [AnyClass] = []) { self.protocolClasses = protocolClasses }

    public func send(_ request: HttpRequest) async throws -> HttpResponse {
        try await send(request, maximumResponseBytes: 256 * 1024 * 1024)
    }

    public func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        guard maximumResponseBytes >= 0 else { throw WebDavError.responseTooLarge }
        let request = request.resolvingUserAgent(defaultValue: UrlRequestBuilder.defaultUserAgent)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.callTimeout
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        let transfer = BoundedTransfer(limit: maximumResponseBytes, follow: request.followRedirects)
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var outgoing = URLRequest(url: request.url)
        outgoing.httpMethod = request.method
        outgoing.httpBody = request.body
        outgoing.allHTTPHeaderFields = request.headers
        return try await transfer.send(outgoing, session: session)
    }
}

private final class BoundedTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private let follow: Bool
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<HttpResponse, Error>?
    private var completed = false
    private var response: HTTPURLResponse?
    private var body = Data()

    init(limit: Int, follow: Bool) { self.limit = limit; self.follow = follow }

    func send(_ request: URLRequest, session: URLSession) async throws -> HttpResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !completed else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<HttpResponse, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        self.task = nil
        body = Data()
        lock.unlock()
        if case .failure = result { task?.cancel() }
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            finish(.failure(WebDavError.responseTooLarge))
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(WebDavError.invalidURL))
            return
        }
        lock.lock()
        self.response = http
        let completed = self.completed
        lock.unlock()
        completionHandler(completed ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        do {
            try BoundedHTTPBody.append(data, to: &body, limit: limit)
            lock.unlock()
        } catch {
            lock.unlock()
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        guard let response, let url = response.url else {
            lock.unlock()
            finish(.failure(WebDavError.invalidURL))
            return
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
        let result = HttpResponse(status: response.statusCode, body: body, finalURL: url, headers: headers)
        lock.unlock()
        finish(.success(result))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard follow, let original = task.originalRequest?.url, let next = request.url,
              original.scheme == next.scheme, original.host == next.host, original.port == next.port else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum BoundedHTTPBody {
    static func append(_ chunk: Data, to body: inout Data, limit: Int) throws {
        guard limit >= body.count, chunk.count <= limit - body.count else { throw WebDavError.responseTooLarge }
        body.append(chunk)
    }

    static func read<Bytes: AsyncSequence>(_ bytes: Bytes, expectedLength: Int64, limit: Int,
                                           cancel: @escaping @Sendable () -> Void) async throws -> Data where Bytes.Element == UInt8 {
        try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                guard limit >= 0, expectedLength <= Int64(limit) else { throw WebDavError.responseTooLarge }
                var body = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    try append(Data([byte]), to: &body, limit: limit)
                }
                return body
            } catch {
                cancel()
                throw error
            }
        } onCancel: {
            cancel()
        }
    }
}
