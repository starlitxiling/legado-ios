import Foundation

public struct URLSessionHttpClient: ResponseLimitedHttpClient {
    private let sessions: HTTPSessionPool
    public init(protocolClasses: [AnyClass] = []) { sessions = HTTPSessionPool(protocolClasses: protocolClasses) }
    var cachedSessionCount: Int { sessions.count }

    public func send(_ request: HttpRequest) async throws -> HttpResponse {
        try await send(request, maximumResponseBytes: 256 * 1024 * 1024, cookieStore: nil)
    }

    public func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse {
        try await send(request, maximumResponseBytes: 256 * 1024 * 1024, cookieStore: cookieStore)
    }

    public func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        try await send(request, maximumResponseBytes: maximumResponseBytes, cookieStore: nil)
    }

    private func send(_ request: HttpRequest, maximumResponseBytes: Int, cookieStore: CookieStore?) async throws -> HttpResponse {
        guard maximumResponseBytes >= 0 else { throw WebDavError.responseTooLarge }
        var current = request
        let start = ContinuousClock.now
        for redirectCount in 0...20 {
            try Task.checkCancellation()
            current.callTimeout = request.callTimeout - elapsed(start)
            guard current.callTimeout.isFinite, current.callTimeout > 0 else { throw URLError(.timedOut) }
            let outgoing = await cookieStore?.loadRequest(current) ?? current
            let response = try await sendSingle(outgoing, maximumResponseBytes: maximumResponseBytes)
            if request.enabledCookieJar { await cookieStore?.saveResponse(response) }
            guard request.followRedirects, [300, 301, 302, 303, 307, 308].contains(response.status),
                  let location = response.headers.httpHeader("Location"),
                  let next = URL(string: location, relativeTo: response.finalURL)?.absoluteURL,
                  ["http", "https"].contains(next.scheme?.lowercased() ?? "") else { return response }
            guard redirectCount < 20 else { throw URLError(.httpTooManyRedirects) }
            if next.host != current.url.host || next.scheme != current.url.scheme || next.port != current.url.port {
                if request.confinesRedirectsToOrigin { return response }
                for key in current.headers.keys.filter({ ["authorization", "cookie", "host"].contains($0.lowercased()) }) {
                    current.headers.removeValue(forKey: key)
                }
            }
            if ![307, 308].contains(response.status), !["GET", "HEAD", "PROPFIND"].contains(current.method) {
                current.method = "GET"; current.body = nil
                for key in current.headers.keys.filter({ ["content-type", "content-length", "transfer-encoding"].contains($0.lowercased()) }) {
                    current.headers.removeValue(forKey: key)
                }
            }
            current.url = next
        }
        throw URLError(.httpTooManyRedirects)
    }

    private func sendSingle(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        let count = request.proxy == nil ? max(1, request.hostAddresses[request.url.host?.lowercased() ?? ""]?.count ?? 0) : 1
        let start = ContinuousClock.now
        for index in 0..<count {
            try Task.checkCancellation()
            let route = try NetworkRoute(request: request, addressIndex: index)
            let entry = sessions.entry(for: route)
            let transfer = BoundedTransfer(limit: maximumResponseBytes, follow: false)
            let remaining = request.callTimeout - elapsed(start)
            guard remaining > 0 else { throw URLError(.timedOut) }
            let outgoing = Self.urlRequest(route.request)
            do {
                if remaining >= Double(UInt64.max) / 1e9 {
                    let response = try await transfer.send(outgoing, session: entry.session, delegate: entry.delegate)
                    try Task.checkCancellation()
                    return route.logicalResponse(response)
                }
                let response = try await withThrowingTaskGroup(of: HttpResponse.self) { group in
                    group.addTask { try await transfer.send(outgoing, session: entry.session, delegate: entry.delegate) }
                    group.addTask {
                        try await Task.sleep(for: .seconds(remaining))
                        throw URLError(.timedOut)
                    }
                    defer { group.cancelAll() }
                    return try await group.next()!
                }
                try Task.checkCancellation()
                return route.logicalResponse(response)
            } catch let error as URLError where index + 1 < count &&
                [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .secureConnectionFailed].contains(error.code) {
                continue
            }
        }
        throw URLError(.cannotConnectToHost)
    }

    private func elapsed(_ start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }

    static func urlRequest(_ request: HttpRequest) -> URLRequest {
        let request = request.resolvingUserAgent(defaultValue: UrlRequestBuilder.defaultUserAgent)
        var result = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeout)
        result.httpMethod = request.method
        result.allHTTPHeaderFields = request.headers
        result.httpBody = request.body
        result.httpShouldHandleCookies = false
        return result
    }
}
