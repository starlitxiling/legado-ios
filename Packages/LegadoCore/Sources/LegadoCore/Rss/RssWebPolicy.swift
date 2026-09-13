import Foundation

public struct RssWebPolicy: Sendable {
    private let source: RssSource
    public init(source: RssSource) { self.source = source }

    private func entries(_ value: String?) -> [String] {
        (value ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private func matches(_ url: String, pattern: String) -> Bool {
        if url.hasPrefix(pattern) { return true }
        return url.range(of: "^(?:" + pattern + ")$", options: .regularExpression) != nil
    }
    public func allowsResource(_ url: String) -> Bool {
        let blacklist = entries(source.contentBlacklist)
        if !blacklist.isEmpty { return !blacklist.contains { matches(url, pattern: $0) } }
        let whitelist = entries(source.contentWhitelist)
        return whitelist.isEmpty || whitelist.contains { matches(url, pattern: $0) }
    }
    public func shouldOverride(_ url: String, client: any HttpClient) throws -> Bool {
        guard let script = source.shouldOverrideUrlLoading, !script.isEmpty else { return false }
        let engine = try RssService(client: client).engine(source: source, baseURL: source.sourceUrl)
        let value = try engine.evaluateScript(script, bindings: ["url": url])
        return (value as? Bool) == true || (value as? String)?.lowercased() == "true"
    }

    /// WebKit 在网络层过滤子资源；前缀与正则分别生成规则，避免混用转义语义。
    public func contentRulesJSON() throws -> String {
        var rules: [[String: Any]] = []
        let blacklist = entries(source.contentBlacklist)
        let whitelist = entries(source.contentWhitelist)
        func append(_ patterns: [String], action: String) {
            for pattern in patterns {
                for filter in ["^" + NSRegularExpression.escapedPattern(for: pattern), "^" + pattern + "$"] {
                    rules.append(["trigger": ["url-filter": filter], "action": ["type": action]])
                }
            }
        }
        if !blacklist.isEmpty { append(blacklist, action: "block") }
        else if !whitelist.isEmpty {
            rules.append(["trigger": ["url-filter": ".*"], "action": ["type": "block"]])
            append(whitelist, action: "ignore-previous-rules")
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
    }
}
