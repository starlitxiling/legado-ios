import Foundation

public struct CoverSearchRule: Codable, Equatable {
    public var enable: Bool
    public var searchUrl: String
    public var coverRule: String
    public var concurrentRate: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var header: String?
    public var jsLib: String?
    public var enabledCookieJar: Bool?

    public init(enable: Bool = true, searchUrl: String, coverRule: String) {
        self.enable = enable; self.searchUrl = searchUrl; self.coverRule = coverRule
        enabledCookieJar = false
    }

    public static var androidDefault: CoverSearchRule {
        try! JSONDecoder().decode(CoverSearchRule.self, from: Data(androidDefaultJSON.utf8))
    }

    private static let androidDefaultJSON = #"""
{
  "enable": true,
  "searchUrl": "data:;base64,{{java.base64Encode(key)}},{\"type\":\"lyc\"}",
  "coverRule": "@js:\r\nvar key = java.hexDecodeToString(result);\r\nvar url1 = `https://pre-api.tuishujun.com/api/searchBook?search_value=${key}&page=1&pageSize=20`;\r\nvar url2 = `http://m.ypshuo.com/api/novel/search?keyword=${key}&searchType=1&page=1`;\r\nvar [rr1, rr2] = java.ajaxAll([url1, url2]).map(r => r.body());\r\nfunction jjson(str, rule) {\r\n    try {\r\n        return com.jayway.jsonpath.JsonPath.read(str, rule);\r\n    } catch (e) {\r\n        return [];\r\n    }\r\n}\r\nrr1 = jjson(rr1, '$.data.data[*]');\r\nrr2 = jjson(rr2, '$.data.data[*]');\r\nvar na = String(book.name),\r\n    au = String(book.author);\r\nfunction search() {\r\n    for (let char of rr1) {\r\n        //本地书名包含搜索结果书名\r\n        if (na.includes(char.title + '')) {\r\n            let au2 = char.author_nickname + '';\r\n            //作者匹配\r\n            if (au.includes(au2) || au2.includes(au)) {\r\n                return char.cover;\r\n            }\r\n        }\r\n    }\r\n    for (let char of rr2) {\r\n        if (na.includes(char.novel_name + '')) {\r\n            let au2 = char.author_name + '';\r\n            if (au.includes(au2) || au2.includes(au)) {\r\n                return char.novel_img;\r\n            }\r\n        }\r\n    }\r\n    return '';\r\n}\r\nsearch()"
}
"""#

    public func search(book: Book, client: any HttpClient) async throws -> String? {
        guard enable, !searchUrl.isEmpty, !coverRule.isEmpty else { return nil }
        var source = BookSource()
        source.bookSourceUrl = searchUrl; source.bookSourceName = "CoverRule"
        source.concurrentRate = concurrentRate; source.loginUrl = loginUrl; source.loginUi = loginUi
        source.header = header; source.jsLib = jsLib; source.enabledCookieJar = enabledCookieJar ?? false
        let context = WebBookContext(source: source, client: client, book: book)
        let response = try await context.request(searchUrl, baseURL: searchUrl, bindings: ["key": book.name ?? ""])
        let parser = try context.parser(response.body, baseURL: response.url)
        let value = try parser.getString(coverRule, isURL: true)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return WebBookContext.absolute(value, base: response.url)
    }
}

/// 网络策略在实际发送请求时生效，磁盘缓存与 data URL 不受限制。
public struct CoverNetworkClient: HttpClient {
    private let underlying: any HttpClient
    private let allowed: Bool
    public init(underlying: any HttpClient, allowed: Bool) {
        self.underlying = underlying; self.allowed = allowed
    }
    public func send(_ request: HttpRequest) async throws -> HttpResponse {
        guard allowed else { throw URLError(.notConnectedToInternet) }
        return try await underlying.send(request)
    }
    public func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse {
        guard allowed else { throw URLError(.notConnectedToInternet) }
        return try await underlying.send(request, cookieStore: cookieStore)
    }
}
