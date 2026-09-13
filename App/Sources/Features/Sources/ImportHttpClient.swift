import Foundation
import LegadoCore

enum ImportHTTPError: LocalizedError {
    case tooManyRedirects, invalidRedirect

    var errorDescription: String? {
        switch self {
        case .tooManyRedirects: return "导入地址跳转超过 5 次。"
        case .invalidRedirect: return "导入地址跳转无效或尝试降级为 HTTP。"
        }
    }
}

struct ImportHttpClient: ResponseLimitedHttpClient {
    private let protocolClasses: [AnyClass]

    init(protocolClasses: [AnyClass] = []) { self.protocolClasses = protocolClasses }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        try await send(request, maximumResponseBytes: ManagementImport.maximumBytes)
    }

    func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        guard Self.isPublicURL(request.url) else { throw ManagementImportError.invalidURL }
        guard maximumResponseBytes >= 0 else { throw ManagementImportError.tooLarge }
        let limit = min(maximumResponseBytes, ManagementImport.maximumBytes)
        var outgoing = URLRequest(url: request.url)
        outgoing.httpMethod = request.method
        outgoing.allHTTPHeaderFields = request.headers
        outgoing.httpBody = request.body
        outgoing.timeoutInterval = request.timeout
        for hop in 0...5 {
            try Task.checkCancellation()
            let response = try await transfer(outgoing, limit: limit, callTimeout: request.callTimeout)
            guard request.followRedirects, [301, 302, 303, 307, 308].contains(response.status),
                  let location = response.headers.first(where: { $0.key.caseInsensitiveCompare("Location") == .orderedSame })?.value else {
                return response
            }
            guard hop < 5 else { throw ImportHTTPError.tooManyRedirects }
            guard let next = URL(string: location, relativeTo: response.finalURL)?.absoluteURL,
                  Self.isPublicURL(next),
                  !(response.finalURL.scheme?.lowercased() == "https" && next.scheme?.lowercased() == "http") else {
                throw ImportHTTPError.invalidRedirect
            }
            if !Self.sameOrigin(response.finalURL, next) {
                for header in ["Authorization", "Cookie", "Proxy-Authorization"] {
                    outgoing.setValue(nil, forHTTPHeaderField: header)
                }
            }
            outgoing.setValue(nil, forHTTPHeaderField: "Host")
            if (response.status == 303 && outgoing.httpMethod != "HEAD") ||
                ([301, 302].contains(response.status) && outgoing.httpMethod == "POST") {
                outgoing.httpMethod = "GET"
                outgoing.httpBody = nil
                for header in ["Content-Length", "Content-Type", "Transfer-Encoding"] {
                    outgoing.setValue(nil, forHTTPHeaderField: header)
                }
            }
            outgoing.url = next
        }
        throw ImportHTTPError.tooManyRedirects
    }

    private static func isPublicURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
        !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased() &&
            lhs.host?.lowercased() == rhs.host?.lowercased() && port(lhs) == port(rhs)
    }

    private func transfer(_ request: URLRequest, limit: Int, callTimeout: TimeInterval) async throws -> HttpResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = callTimeout
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        let transfer = ImportTransfer(limit: limit)
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await transfer.send(request, session: session)
    }
}

private final class ImportTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HttpResponse, Error>?
    private var task: URLSessionDataTask?
    private var completed = false
    private var response: HTTPURLResponse?
    private var body = Data()

    init(limit: Int) { self.limit = limit }

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
        } onCancel: { self.finish(.failure(CancellationError())) }
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

    // 每一跳均交给外层重新构造请求，URLSession 不自动携带凭据跟随跳转。
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        self.response = response
        lock.unlock()
        if response.expectedContentLength > Int64(limit) {
            finish(.failure(ManagementImportError.tooLarge))
        }
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            finish(.failure(ManagementImportError.tooLarge))
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(ManagementImportError.invalidURL))
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
        guard data.count <= limit - body.count else {
            lock.unlock()
            finish(.failure(ManagementImportError.tooLarge))
            return
        }
        body.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        guard let response, let url = response.url else {
            lock.unlock()
            finish(.failure(ManagementImportError.invalidURL))
            return
        }
        let headers = Dictionary(response.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) },
                                 uniquingKeysWith: { _, last in last })
        let result = HttpResponse(status: response.statusCode, body: body, finalURL: url, headers: headers)
        lock.unlock()
        finish(.success(result))
    }
}
