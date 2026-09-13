import Foundation

public enum WebHttpError: Error, Equatable { case malformed, tooLarge, unsupportedEncoding }

public struct WebHttpRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: [String]]
    public let headers: [String: String]
    public let body: Data

    public init(method: String, target: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        path = String(parts[0])
        var query: [String: [String]] = [:]
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let values = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                func decode(_ value: String) -> String {
                    let text = value.replacingOccurrences(of: "+", with: " ")
                    return text.removingPercentEncoding ?? text
                }
                query[decode(String(values[0])), default: []].append(values.count == 2 ? decode(String(values[1])) : "")
            }
        }
        self.query = query; self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last }); self.body = body
    }

    public static let maximumBodySize = 4 * 1024 * 1024
    public static let maximumHeaderSize = 16 * 1024

    /// 返回 nil 表示需要更多字节；拒绝模糊消息边界和 chunked 编码。
    public static func parse(_ bytes: Data) throws -> WebHttpRequest? {
        guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
            guard bytes.count <= maximumHeaderSize else { throw WebHttpError.tooLarge }
            return nil
        }
        guard boundary.lowerBound <= maximumHeaderSize else { throw WebHttpError.tooLarge }
        guard let head = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) else { throw WebHttpError.malformed }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[1].hasPrefix("/"), ["HTTP/1.0", "HTTP/1.1"].contains(first[2]) else { throw WebHttpError.malformed }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { throw WebHttpError.malformed }
            let key = String(line[..<colon]).lowercased()
            guard !key.contains(where: { $0.isWhitespace }), headers[key] == nil else { throw WebHttpError.malformed }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else { throw WebHttpError.unsupportedEncoding }
        let length: Int
        if let raw = headers["content-length"] {
            guard !raw.isEmpty, raw.allSatisfy({ $0 >= "0" && $0 <= "9" }), let count = Int(raw) else { throw WebHttpError.malformed }
            length = count
        } else { length = 0 }
        guard length <= maximumBodySize else { throw WebHttpError.tooLarge }
        guard bytes.count - boundary.upperBound >= length else { return nil }
        return WebHttpRequest(method: String(first[0]), target: String(first[1]), headers: headers,
                              body: bytes.subdata(in: boundary.upperBound..<(boundary.upperBound + length)))
    }
}

public struct WebHttpResponse: Sendable {
    public let status: Int
    public let contentType: String
    public let body: Data
    public var headers: [String: String] = [:]

    public init(status: Int = 200, contentType: String = "application/json; charset=utf-8", body: Data) {
        self.status = status; self.contentType = contentType; self.body = body
    }

    public func encoded() -> Data {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 501: "Not Implemented"][status] ?? "Error"
        let extra = headers.sorted { $0.key < $1.key }.filter { !$0.key.contains("\r") && !$0.key.contains("\n") && !$0.value.contains("\r") && !$0.value.contains("\n") }.map { "\($0.key): \($0.value)\r\n" }.joined()
        var data = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\n\(extra)\r\n".utf8)
        data.append(body)
        return data
    }
}

public struct HttpRouter: Sendable {
    private let api: WebApi
    private let token: @Sendable () -> String?
    private let tokenRequired: @Sendable () -> Bool
    private static let protectedWrites: Set<String> = ["/saveBookSource", "/saveBookSources", "/deleteBookSources",
        "/saveRssSource", "/saveRssSources", "/deleteRssSources", "/saveReplaceRule", "/deleteReplaceRule", "/testReplaceRule",
        "/saveJsSource", "/startBookSourceCheck", "/stopBookSourceCheck", "/openLegacyReview", "/runLegacyReview"]

    public init(api: WebApi, token: @escaping @Sendable () -> String? = { nil },
                tokenRequired: @escaping @Sendable () -> Bool = { true }) {
        self.api = api; self.token = token; self.tokenRequired = tokenRequired
    }

    public func handle(_ request: WebHttpRequest) async -> WebHttpResponse {
        var response = await dispatch(request)
        response.headers["Access-Control-Allow-Methods"] = "GET, POST"
        response.headers["Access-Control-Allow-Headers"] = "content-type, x-legado-token"
        response.headers["Access-Control-Allow-Origin"] = request.headers["origin"]
        return response
    }

    public func authorizesWebSocket(_ request: WebHttpRequest) -> Bool {
        WebSocketHandshake.authorized(request, token: token(), required: tokenRequired())
    }

    private func dispatch(_ request: WebHttpRequest) async -> WebHttpResponse {
        if request.method == "GET", request.path == "/debug.html" {
            return WebHttpResponse(contentType: "text/html; charset=utf-8", body: Data(WebSocketDebugPage.html.utf8))
        }
        if request.method == "OPTIONS" { return WebHttpResponse(contentType: "text/plain; charset=utf-8", body: Data()) }
        if request.method == "GET", request.path == "/getJsSourceApiTokenRequired" {
            return WebHttpResponse(body: (try? JSONEncoder().encode(ReturnData(data: tokenRequired()))) ?? Data())
        }
        if request.method == "POST", Self.protectedWrites.contains(request.path), tokenRequired(),
           !Self.matches(token(), request.headers["x-legado-token"]) {
            return WebHttpResponse(body: (try? JSONEncoder().encode(ReturnData<String>(errorMsg: "Web 书源访问令牌未配置或不正确"))) ?? Data())
        }
        guard let method = WebApi.routes[request.path] else {
            let path = "/" + request.path.split(separator: "/").joined(separator: "/")
            let indexed = request.path.hasSuffix("/") ? (path == "/" ? "/index.html" : path + "/index.html") : path
            if indexed == "/index.html" {
                return WebHttpResponse(contentType: "text/html; charset=utf-8", body: Data(WebPage.html.utf8))
            }
            return WebHttpResponse(status: 404, body: Data("{\"isSuccess\":false,\"errorMsg\":\"Not Found\"}".utf8))
        }
        guard request.method == method else {
            return WebHttpResponse(status: 405, body: Data("{\"isSuccess\":false,\"errorMsg\":\"Method Not Allowed\"}".utf8))
        }
        return await api.handle(request)
    }

    private static func matches(_ expected: String?, _ actual: String?) -> Bool {
        guard let expected, !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let actual else { return false }
        let a = Array(expected.utf8), b = Array(actual.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
