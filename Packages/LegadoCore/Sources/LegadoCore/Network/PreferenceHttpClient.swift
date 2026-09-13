import Foundation

/// 书源显式指定的 User-Agent 优先；默认值在每次请求时读取。
public struct PreferenceHttpClient: ResponseLimitedHttpClient {
    private let underlying: any ResponseLimitedHttpClient
    private let userAgent: @Sendable () -> String
    private let recordResponse: @Sendable (HttpRequest, HttpResponse) -> Void

    public init(underlying: any ResponseLimitedHttpClient, userAgent: @escaping @Sendable () -> String,
                recordResponse: @escaping @Sendable (HttpRequest, HttpResponse) -> Void = { _, _ in }) {
        self.underlying = underlying
        self.userAgent = userAgent
        self.recordResponse = recordResponse
    }

    private func configured(_ request: HttpRequest) -> HttpRequest {
        let value = userAgent().trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = !value.isEmpty && !value.contains("\r") && !value.contains("\n")
        return request.resolvingUserAgent(defaultValue: valid ? value : UrlRequestBuilder.defaultUserAgent)
    }

    public func send(_ request: HttpRequest) async throws -> HttpResponse {
        let response = try await underlying.send(configured(request))
        recordResponse(request, response)
        return response
    }

    public func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse {
        let response = try await underlying.send(configured(request), cookieStore: cookieStore)
        recordResponse(request, response)
        return response
    }

    public func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        let response = try await underlying.send(configured(request), maximumResponseBytes: maximumResponseBytes)
        recordResponse(request, response)
        return response
    }
}
