import Foundation

public enum WebDavError: Error, Equatable {
    case invalidURL, foreignOrigin, httpStatus(Int), invalidXML
    case responseTooLarge, responseLimitUnavailable
}

public struct WebDavClient: Sendable {
    public let baseURL: URL
    private let authorization: String
    private let httpClient: any HttpClient

    public init(baseURL: URL, username: String, password: String, httpClient: any HttpClient) {
        self.baseURL = baseURL
        // Kotlin Authorization 默认 ISO-8859-1，不可表示的字符按 Java Charset 替换为问号。
        let bytes = (username + ":" + password).unicodeScalars.map { UInt8(exactly: $0.value) ?? 63 }
        self.authorization = "Basic " + Data(bytes).base64EncodedString()
        self.httpClient = httpClient
    }

    /// 接收未编码的相对路径；百分号是文件名字符，href 则应直接使用 WebDavFile.url。
    public func url(path: String) throws -> URL {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: true),
              ["http", "https", "dav", "davs"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil else {
            throw WebDavError.invalidURL
        }
        if parts.scheme == "dav" { parts.scheme = "http" }
        if parts.scheme == "davs" { parts.scheme = "https" }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "%?#")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) else { throw WebDavError.invalidURL }
        if !parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath += "/" }
        parts.percentEncodedPath += encoded.drop(while: { $0 == "/" })
        parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
        guard let result = parts.url else { throw WebDavError.invalidURL }
        return result
    }

    public func propfind(_ url: URL, depth: Int = 1) async throws -> [WebDavFile] {
        guard depth == 0 || depth == 1 else { throw WebDavError.invalidURL }
        let response = try await request("PROPFIND", url: url, headers: ["Depth": String(depth), "Content-Type": "application/xml; charset=utf-8"], body: Self.properties)
        return try WebDavXMLParser.parse(response.body, relativeTo: response.finalURL)
    }

    public func get(_ url: URL, maximumResponseBytes: Int? = nil) async throws -> Data {
        try await request("GET", url: url, maximumResponseBytes: maximumResponseBytes).body
    }

    public func exists(_ url: URL) async throws -> Bool {
        do {
            _ = try await request("PROPFIND", url: url, headers: ["Depth": "0", "Content-Type": "application/xml"], body: Self.properties)
            return true
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw error }
        catch { return false }
    }

    public func put(_ data: Data, to url: URL, contentType: String = "application/octet-stream", overwrite: Bool = true) async throws {
        var headers = ["Content-Type": contentType]
        if !overwrite { headers["If-None-Match"] = "*" }
        _ = try await request("PUT", url: url, headers: headers, body: data)
    }

    public func mkcol(_ url: URL) async throws {
        _ = try await request("MKCOL", url: url)
    }

    public func delete(_ url: URL) async throws {
        _ = try await request("DELETE", url: url)
    }

    public func ensureCollection(_ url: URL) async throws {
        if try await exists(url) { return }
        do { try await mkcol(url) }
        catch WebDavError.httpStatus(405) {
            let files = try await propfind(url, depth: 0)
            guard files.contains(where: { $0.isDirectory && $0.url.standardized == url.standardized }) else {
                throw WebDavError.httpStatus(405)
            }
        }
    }

    private func request(_ method: String, url: URL, headers: [String: String] = [:], body: Data? = nil, maximumResponseBytes: Int? = nil) async throws -> HttpResponse {
        let origin = try self.url(path: "")
        func port(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
        guard url.scheme == origin.scheme, url.host?.lowercased() == origin.host?.lowercased(), port(url) == port(origin) else {
            throw WebDavError.foreignOrigin
        }
        guard url.user == nil, url.password == nil else { throw WebDavError.invalidURL }
        var headers = headers
        headers["Authorization"] = authorization
        let outgoing = HttpRequest(url: url, method: method, headers: headers, body: body)
        let response: HttpResponse
        if let limit = maximumResponseBytes {
            guard limit >= 0 else { throw WebDavError.responseTooLarge }
            guard let bounded = httpClient as? any ResponseLimitedHttpClient else { throw WebDavError.responseLimitUnavailable }
            response = try await bounded.send(outgoing, maximumResponseBytes: limit)
            guard response.body.count <= limit else { throw WebDavError.responseTooLarge }
        } else {
            response = try await httpClient.send(outgoing)
        }
        guard (200..<300).contains(response.status) else { throw WebDavError.httpStatus(response.status) }
        return response
    }

    private static let properties = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getcontenttype/><d:creationdate/><d:getlastmodified/></d:prop></d:propfind>
    """.utf8)
}
