import Foundation

public struct URLSessionHttpClient: HttpClient {
    private let protocolClasses: [AnyClass]
    public init(protocolClasses: [AnyClass] = []) { self.protocolClasses = protocolClasses }

    public func send(_ request: HttpRequest) async throws -> HttpResponse {
        try await send(request, cookieStore: nil)
    }

    public func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse {
        var current = request
        let start = ContinuousClock.now
        for redirectCount in 0...20 {
            try Task.checkCancellation()
            let elapsed = start.duration(to: .now).components
            current.callTimeout = request.callTimeout - Double(elapsed.seconds) - Double(elapsed.attoseconds) / 1e18
            guard current.callTimeout > 0 else { throw URLError(.timedOut) }
            let outgoing = await cookieStore?.loadRequest(current) ?? current
            let response = try await sendSingle(outgoing)
            if request.enabledCookieJar { await cookieStore?.saveResponse(response) }
            guard request.followRedirects, [300, 301, 302, 303, 307, 308].contains(response.status),
                  let location = response.headers.httpHeader("Location"),
                  let next = URL(string: location, relativeTo: response.finalURL)?.absoluteURL,
                  ["http", "https"].contains(next.scheme?.lowercased() ?? "") else { return response }
            guard redirectCount < 20 else { throw URLError(.httpTooManyRedirects) }
            if next.host != current.url.host || next.scheme != current.url.scheme || next.port != current.url.port {
                for key in current.headers.keys.filter({ ["authorization", "cookie"].contains($0.lowercased()) }) {
                    current.headers.removeValue(forKey: key)
                }
            }
            if ![307, 308].contains(response.status), !["GET", "HEAD", "PROPFIND"].contains(current.method) {
                current.method = "GET"
                current.body = nil
                for key in current.headers.keys.filter({ ["content-type", "content-length", "transfer-encoding"].contains($0.lowercased()) }) {
                    current.headers.removeValue(forKey: key)
                }
            }
            current.url = next
        }
        throw URLError(.httpTooManyRedirects)
    }

    private func sendSingle(_ request: HttpRequest) async throws -> HttpResponse {
        let configuration = URLSessionConfiguration.ephemeral
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.callTimeout
        // 每跳返回后先等待 actor 保存 Cookie，再发下一跳；同时保留停止跳转的响应体。
        let delegate = RedirectDelegate(followRedirects: false)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: Self.urlRequest(request))
        guard let response = response as? HTTPURLResponse, let url = response.url else {
            throw URLError(.badServerResponse)
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
        return HttpResponse(status: response.statusCode, body: data, finalURL: url, headers: headers)
    }

    static func urlRequest(_ request: HttpRequest) -> URLRequest {
        var result = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeout)
        result.httpMethod = request.method
        result.allHTTPHeaderFields = request.headers
        result.httpBody = request.body
        result.httpShouldHandleCookies = false
        return result
    }
}

final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let followRedirects: Bool
    init(followRedirects: Bool) { self.followRedirects = followRedirects }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(followRedirects ? request : nil)
    }
}
