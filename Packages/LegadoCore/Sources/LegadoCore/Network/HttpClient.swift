import Foundation

public protocol HttpClient: Sendable {
    func send(_ request: HttpRequest) async throws -> HttpResponse
    func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse
}

public extension HttpClient {
    func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse {
        let outgoing = await cookieStore?.loadRequest(request) ?? request
        let response = try await send(outgoing)
        if request.enabledCookieJar { await cookieStore?.saveResponse(response) }
        return response
    }
}

public struct HttpRequest: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    /// URLSession 的请求空闲超时与资源总超时，单位为秒。
    public var timeout: TimeInterval
    public var callTimeout: TimeInterval
    public var followRedirects: Bool
    public var enabledCookieJar: Bool

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil,
                timeout: TimeInterval = 60, callTimeout: TimeInterval = 60, followRedirects: Bool = true,
                enabledCookieJar: Bool = false) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.callTimeout = callTimeout
        self.followRedirects = followRedirects
        self.enabledCookieJar = enabledCookieJar
    }
}

public struct HttpResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public let finalURL: URL

    public init(status: Int, body: Data = Data(), finalURL: URL, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.finalURL = finalURL
        self.headers = headers
    }
}

extension Dictionary where Key == String, Value == String {
    func httpHeader(_ name: String) -> String? { first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }
    mutating func setHTTPHeader(_ name: String, _ value: String) {
        for key in keys.filter({ $0.caseInsensitiveCompare(name) == .orderedSame }) { removeValue(forKey: key) }
        self[name] = value
    }
}
