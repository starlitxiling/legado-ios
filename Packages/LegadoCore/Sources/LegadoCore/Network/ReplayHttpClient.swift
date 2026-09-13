import Foundation

public actor ReplayHttpClient: HttpClient {
    public enum ReplayError: Error, Equatable { case unmatched(method: String, url: URL) }
    private struct Key: Hashable { let url: URL; let method: String }
    private var recordings: [Key: [Result<HttpResponse, Error>]] = [:]
    public private(set) var requests: [HttpRequest] = []

    public init() {}

    public func enqueue(url: URL, method: String = "GET", response: HttpResponse) {
        recordings[Key(url: url, method: method.uppercased()), default: []].append(.success(response))
    }

    public func enqueue(url: URL, method: String = "GET", error: Error) {
        recordings[Key(url: url, method: method.uppercased()), default: []].append(.failure(error))
    }

    public func send(_ request: HttpRequest) async throws -> HttpResponse {
        try Task.checkCancellation()
        requests.append(request)
        let key = Key(url: request.url, method: request.method.uppercased())
        guard recordings[key]?.isEmpty == false else { throw ReplayError.unmatched(method: request.method, url: request.url) }
        return try recordings[key]!.removeFirst().get()
    }
}
