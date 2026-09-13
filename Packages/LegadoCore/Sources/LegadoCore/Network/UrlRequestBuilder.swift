import Foundation

public enum UrlRequestBuilder {
    public enum RequestError: Error, Equatable {
        case invalidURL(String), invalidHeaders, webViewNotImplemented, unencodable(String)
    }
    public static let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36"

    public static func build(url: String, options: UrlOptions = UrlOptions(), sourceHeaderJSON: String? = nil,
                             cookie: String? = nil, enabledCookieJar: Bool = false) throws -> HttpRequest {
        if options.useWebView { throw RequestError.webViewNotImplemented }
        var headers: [String: String] = [:]
        if let json = sourceHeaderJSON, !json.isEmpty {
            guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
                throw RequestError.invalidHeaders
            }
            for (key, value) in object { headers.setHTTPHeader(key, String(describing: value)) }
        }
        for (key, value) in options.headers { headers.setHTTPHeader(key, value) }
        for key in headers.keys.filter({ $0.caseInsensitiveCompare("proxy") == .orderedSame }) { headers.removeValue(forKey: key) }
        for key in headers.keys.filter({ $0.caseInsensitiveCompare("CookieJar") == .orderedSame }) { headers.removeValue(forKey: key) }
        if headers.httpHeader("User-Agent") == nil { headers["User-Agent"] = defaultUserAgent }
        else if headers.httpHeader("User-Agent") == "null" {
            for key in headers.keys.filter({ $0.caseInsensitiveCompare("User-Agent") == .orderedSame }) { headers.removeValue(forKey: key) }
        }
        if let cookie {
            let merged = CookieStore.mergeCookies(cookie, headers.httpHeader("Cookie") ?? "")
            if !merged.isEmpty { headers.setHTTPHeader("Cookie", merged) }
        }
        var address = url
        if options.method != "POST", let query = address.firstIndex(of: "?") {
            address = String(address[...query]) + (try encodeParams(String(address[address.index(after: query)...]), charset: options.charset, query: true))
        }
        guard let target = URL(string: address), ["http", "https"].contains(target.scheme?.lowercased() ?? ""),
              target.host != nil else { throw RequestError.invalidURL(address) }
        var body: Data?
        if options.method == "POST" {
            let text = options.body ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let structured = (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
                (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) || (trimmed.hasPrefix("<") && trimmed.hasSuffix(">"))
            let contentType = headers.httpHeader("Content-Type")
            if trimmed.isEmpty || (!structured && (contentType ?? "").isEmpty) {
                body = Data(try encodeParams(trimmed.isEmpty ? "" : text, charset: options.charset, query: false).utf8)
                headers.setHTTPHeader("Content-Type", "application/x-www-form-urlencoded")
            } else {
                let type = contentType ?? "application/json; charset=UTF-8"
                let encoding = try ResponseDecoder.encoding(for: ResponseDecoder.contentTypeCharset(type) ?? "UTF-8")
                guard let data = text.data(using: encoding) else { throw RequestError.unencodable(text) }
                body = data
                headers.setHTTPHeader("Content-Type", type)
            }
        }
        return HttpRequest(url: target, method: options.method, headers: headers, body: body,
                           timeout: Double(options.timeout ?? 60_000) / 1000,
                           callTimeout: Double(options.callTimeout ?? 60_000) / 1000,
                           followRedirects: options.followRedirects ?? true, enabledCookieJar: enabledCookieJar)
    }

    public static func execute(url: String, options: UrlOptions = UrlOptions(), sourceHeaderJSON: String? = nil,
                               cookieStore: CookieStore? = nil, enabledCookieJar: Bool = false,
                               client: any HttpClient) async throws -> StrResponse {
        var remaining = max(0, options.retry)
        while true {
            try Task.checkCancellation()
            let cookie = await cookieStore?.getCookie(url: url)
            let request = try build(url: url, options: options, sourceHeaderJSON: sourceHeaderJSON, cookie: cookie,
                                    enabledCookieJar: enabledCookieJar)
            let response = try await client.send(request, cookieStore: cookieStore)
            if (200..<400).contains(response.status) || remaining == 0 { return try StrResponse(raw: response) }
            remaining -= 1
        }
    }

    private static let alphanumeric = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    private static func encodeParams(_ value: String, charset: String?, query: Bool) throws -> String {
        let explicit = !(charset ?? "").isEmpty
        let escape = charset == "escape"
        let querySafe = alphanumeric + "-._~!$%&()*+,/:;=?@[\\]^`{|}"
        if query && !escape {
            return try percent(value, charset: explicit ? charset! : "UTF-8", safe: querySafe, spacePlus: false)
        }
        return try value.components(separatedBy: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return try parts.map { part in
                let text = String(part)
                if escape {
                    return text.utf16.map { unit in
                        if unit < 128, (alphanumeric + "@*_+-./").utf8.contains(UInt8(unit)) { return String(UnicodeScalar(unit)!) }
                        return String(format: unit < 256 ? "%%%02X" : "%%u%04X", unit)
                    }.joined()
                }
                if !explicit && alreadyEncoded(text) { return text }
                return try percent(text, charset: explicit ? charset! : "UTF-8", safe: alphanumeric + "-._*", spacePlus: true)
            }.joined(separator: "=")
        }.joined(separator: "&")
    }

    private static func alreadyEncoded(_ text: String) -> Bool {
        text.range(of: #"^(?:[a-zA-Z0-9.*_\-]|%[a-fA-F0-9]{2})*$"#, options: .regularExpression) != nil
    }
    private static func percent(_ text: String, charset: String, safe: String, spacePlus: Bool) throws -> String {
        let encoding = try ResponseDecoder.encoding(for: charset)
        let allowed = Set(safe.utf8)
        return try text.unicodeScalars.map { scalar in
            if scalar.value < 128, allowed.contains(UInt8(scalar.value)) { return String(scalar) }
            if spacePlus && scalar.value == 32 { return "+" }
            guard let bytes = String(scalar).data(using: encoding) else { throw RequestError.unencodable(text) }
            return bytes.map { String(format: "%%%02X", $0) }.joined()
        }.joined()
    }
}
