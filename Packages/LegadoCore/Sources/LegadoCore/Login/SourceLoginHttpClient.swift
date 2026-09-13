import Foundation

protocol SourceScriptClient: HttpClient {
    func configureSourceBindings(_ engine: JsEngine)
    func checkResponse(_ response: StrResponse) async throws -> StrResponse
    func loginHeaders(url: String, headers: [String: String]) throws -> [String: String]
}

public protocol SourceSessionClientProviding: HttpClient {
    func client(for source: BookSource) -> any HttpClient
}

public struct SourceLoginHttpClient: ResponseLimitedHttpClient, SourceSessionClientProviding {
    private let database: AppDatabase
    private let underlying: any ResponseLimitedHttpClient
    private let secrets: any SourceSecretStore
    public init(database: AppDatabase, underlying: any ResponseLimitedHttpClient, secrets: any SourceSecretStore = MemorySourceSecretStore()) {
        self.database = database; self.underlying = underlying; self.secrets = secrets
    }
    public func client(for source: BookSource) -> any HttpClient {
        SourceSessionHttpClient(source: source, database: database, client: underlying, secrets: secrets)
    }
    public func send(_ request: HttpRequest) async throws -> HttpResponse { try await underlying.send(request) }
    public func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        try await underlying.send(request, maximumResponseBytes: maximumResponseBytes)
    }
}
