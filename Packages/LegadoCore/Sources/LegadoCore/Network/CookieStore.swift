import Foundation

public actor CookieStore {
    private var cookies: [String: String] = [:]
    public init() {}

    public static func hostKey(_ url: String) -> String {
        let address = url.range(of: "@js:", options: .caseInsensitive).map { String(url[..<$0.lowerBound]) } ?? url
        guard address.lowercased().hasPrefix("http://") || address.lowercased().hasPrefix("https://"),
              let parsed = URL(string: address), let host = parsed.host, !host.isEmpty else { return url }
        if host.contains(":") { return host.hasPrefix("[") ? host : "[\(host)]" }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return host }
        return PublicSuffixDomain.effectiveTldPlusOne(host) ?? host
    }

    public func setCookie(url: String, cookie: String?) { cookies[Self.hostKey(url)] = cookie ?? "" }
    public func replaceCookie(url: String, cookie: String) {
        guard !url.isEmpty, !cookie.isEmpty else { return }
        let key = Self.hostKey(url)
        cookies[key] = Self.mergeCookieValues(cookies[key] ?? "", cookie)
    }
    public func getCookie(url: String) -> String { Self.mergeCookies("", cookies[Self.hostKey(url)] ?? "") }
    public func getKey(url: String, key: String) -> String { Self.cookieToMap(getCookie(url: url))[key] ?? "" }
    public func removeCookie(url: String) { cookies.removeValue(forKey: Self.hostKey(url)) }
    public func clear() { cookies.removeAll() }

    func loadRequest(_ request: HttpRequest) -> HttpRequest {
        guard request.enabledCookieJar else { return request }
        var result = request
        let value = Self.mergeCookies(request.headers.httpHeader("Cookie") ?? "", getCookie(url: request.url.absoluteString))
        if !value.isEmpty { result.headers.setHTTPHeader("Cookie", value) }
        return result
    }

    func saveResponse(_ response: HttpResponse) {
        guard let header = response.headers.httpHeader("Set-Cookie") else { return }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: response.finalURL)
        replaceCookie(url: response.finalURL.absoluteString, cookie: parsed.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
    }

    public static func cookieToMap(_ cookie: String) -> [String: String] {
        Dictionary(pairs(cookie), uniquingKeysWith: { _, new in new })
    }
    public static func mapToCookie(_ cookieMap: [String: String]) -> String? {
        guard !cookieMap.isEmpty else { return nil }
        return cookieMap.keys.sorted().map { "\($0)=\(cookieMap[$0]!)" }.joined(separator: "; ")
    }
    public static func mergeCookieValues(_ oldCookie: String, _ cookie: String) -> String {
        oldCookie.isEmpty ? cookie : mergeCookies(oldCookie, cookie)
    }
    public static func mergeCookies(_ oldCookie: String, _ cookie: String) -> String {
        var entries: [(String, String)] = []
        for (key, value) in pairs(oldCookie) + pairs(cookie) {
            if let index = entries.firstIndex(where: { $0.0 == key }) { entries[index].1 = value }
            else { entries.append((key, value)) }
        }
        return entries.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }
    private static func pairs(_ cookie: String) -> [(String, String)] {
        cookie.components(separatedBy: ";").compactMap { pair in
            guard let equal = pair.firstIndex(of: "=") else { return nil }
            let trim = CharacterSet(charactersIn: "\u{0}"..." ")
            let key = String(pair[..<equal]).trimmingCharacters(in: trim)
            let value = String(pair[pair.index(after: equal)...]).trimmingCharacters(in: trim)
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (key, value)
        }
    }
}
