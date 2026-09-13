import Foundation
import SwiftSoup

public struct MediaResource: Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]
    public let imageRule: String
    public init(url: URL, headers: [String: String] = [:], imageRule: String? = nil) {
        self.url = url; self.headers = headers
        if let imageRule { self.imageRule = imageRule; return }
        guard !headers.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: ["headers": headers], options: .sortedKeys),
              let json = String(data: data, encoding: .utf8) else { self.imageRule = url.absoluteString; return }
        self.imageRule = url.absoluteString + "," + json
    }
}

public enum MediaContentResolver {
    public static func images(_ content: String, baseURL: String) throws -> [MediaResource] {
        var result: [MediaResource] = []
        for line in content.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if value.range(of: "<img", options: .caseInsensitive) != nil {
                let normalized = HtmlFormatter.formatKeepImg(value, redirectUrl: URL(string: baseURL))
                for element in try SwiftSoup.parseBodyFragment(escapeImageOptions(normalized)).select("img[src]").array() {
                    result.append(try image(try element.attr("src"), baseURL: baseURL))
                }
            } else if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("/") || value.hasPrefix("data:image/") {
                result.append(try image(value, baseURL: baseURL))
            }
        }
        return result
    }

    private static func escapeImageOptions(_ html: String) throws -> String {
        // Legado 允许 src 中直接嵌入 JSON 引号；先保护该属性，再交给 HTML 解析器。
        let pattern = try NSRegularExpression(pattern: #"<img[^>]*\ssrc\s*=\s*['"]([^'"{>]*\{(?:[^{}]|\{[^}>]+\})+\})['"][^>]*>"#,
                                              options: .caseInsensitive)
        var escaped = html
        let text = html as NSString
        for match in pattern.matches(in: html, range: NSRange(location: 0, length: text.length)).reversed() {
            let value = text.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
            escaped = (escaped as NSString).replacingCharacters(in: match.range(at: 1), with: value)
        }
        return escaped
    }

    private static func image(_ value: String, baseURL: String) throws -> MediaResource {
        var value = try HTML4Entities.unescape(value)
        var headers: [String: String] = [:]
        var wrappedHeaders = false
        if let start = value.range(of: "{{"), value.hasSuffix("}}") {
            wrappedHeaders = true
            let json = String(value[start.upperBound..<value.index(value.endIndex, offsetBy: -2)])
            // 双花括号包裹的内容可以是 JSON 对象，也可以是对象的键值体。
            let data = Data((json.hasPrefix("{") ? json : "{" + json + "}").utf8)
            headers = try JSONDecoder().decode([String: String].self, from: data)
            value = String(value[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasSuffix(",") { value.removeLast() }
        }
        let parsed = UrlOptions.parse(value)
        guard parsed.status != .invalid else { throw UrlOptions.OptionError.invalidJSON }
        for (key, value) in parsed.options.headers { headers.setHTTPHeader(key, value) }
        guard let url = URL(string: try HTML4Entities.unescape(parsed.url), relativeTo: URL(string: baseURL))?.absoluteURL,
              ["http", "https", "data"].contains(url.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
        let fullRule = url.absoluteString + String(value.dropFirst(parsed.url.count))
        return MediaResource(url: url, headers: headers, imageRule: wrappedHeaders ? nil : fullRule)
    }

    public static func audio(source: BookSource, book: Book, chapter: BookChapter,
                             client: any HttpClient, cookies: CookieStore = CookieStore()) async throws -> MediaResource {
        let raw = try await WebBook(source: source, client: client, cookies: cookies).content(book: book, chapter: chapter, includeTitle: false).rawContent
        return try await audioAddress(raw, source: source, book: book, chapter: chapter, client: client, cookies: cookies)
    }

    public static func audioAddress(_ rule: String, source: BookSource, book: Book, chapter: BookChapter,
                                    client: any HttpClient, cookies: CookieStore = CookieStore()) async throws -> MediaResource {
        let client = (client as? any SourceSessionClientProviding)?.client(for: source) ?? client
        let base = WebBookContext.absolute(chapter.url ?? "", base: chapter.baseUrl ?? book.tocUrl ?? source.bookSourceUrl ?? "")
        let context = WebBookContext(source: source, client: client, book: book, cookies: cookies)
        let engine = try context.engine(baseURL: base)
        let bindings: [String: Any] = ["book": try WebBookContext.object(book),
            "chapter": try WebBookContext.object(chapter), "source": try WebBookContext.object(source)]
        let executor = try AnalyzeUrlExecutor(rule, engine: engine, bindings: bindings)
        var address = executor.url
        if executor.options.useWebView { address = try await executor.getStrResponse().body }
        guard let url = URL(string: address), ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else {
            throw URLError(.badURL)
        }
        var headers = engine.networkSource.headers
        if let session = client as? any SourceScriptClient { headers = try session.loginHeaders(url: address, headers: headers) }
        for (key, value) in executor.options.headers { headers.setHTTPHeader(key, value) }
        if source.enabledCookieJar ?? true, headers.httpHeader("Cookie") == nil {
            let cookie = await cookies.getCookie(url: address)
            if !cookie.isEmpty { headers.setHTTPHeader("Cookie", cookie) }
        }
        return MediaResource(url: url, headers: headers)
    }
}
