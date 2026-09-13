import Foundation

public enum RuleSubImportError: Error {
    case invalidRules, invalidURL, httpStatus(Int), unsupportedType(Int), unsupportedScript
}

public enum RuleSubContent {
    case books([ImportedBookSource])
    case rss([RssSource])
    case replacements([ReplaceRule])
}

public extension SourceImporter {
    func parseRuleSubs(_ text: String) throws -> [RuleSub] {
        let data = Data(text.utf8)
        let tree = try GsonValue.parse(data)
        let decoder = GsonJSONDecoder(now: now)
        let values: [RuleSub]
        switch tree {
        case .object: values = [try decoder.decode(RuleSub.self, from: data)]
        case .array: values = try decoder.decode([RuleSub].self, from: data)
        default: throw RuleSubImportError.invalidRules
        }
        guard values.allSatisfy({ !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && [0, 1, 2].contains($0.type) }) else {
            throw RuleSubImportError.invalidRules
        }
        return values
    }

    func importRuleSubs(from url: URL, client: any HttpClient) async throws -> [RuleSub] {
        try parseRuleSubs(await subscriptionText(from: url, client: client))
    }

    func fetchSubscription(_ subscription: RuleSub, client: any HttpClient) async throws -> RuleSubContent {
        guard subscription.js?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            throw RuleSubImportError.unsupportedScript
        }
        guard let url = URL(string: subscription.url) else { throw RuleSubImportError.invalidURL }
        let text = try await subscriptionText(from: url, client: client)
        switch subscription.type {
        case 0:
            guard case let .sources(values) = parseBookSources(text) else { throw RuleSubImportError.invalidRules }
            return .books(values)
        case 1:
            guard case let .sources(values) = parseRssSources(text) else { throw RuleSubImportError.invalidRules }
            return .rss(values)
        case 2:
            guard case let .rules(values) = parseReplaceRules(text) else { throw RuleSubImportError.invalidRules }
            return .replacements(values)
        default: throw RuleSubImportError.unsupportedType(subscription.type)
        }
    }

    private func subscriptionText(from url: URL, client: any HttpClient) async throws -> String {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw RuleSubImportError.invalidURL
        }
        let response = try await client.send(HttpRequest(url: url))
        guard (200..<300).contains(response.status) else { throw RuleSubImportError.httpStatus(response.status) }
        return String(decoding: response.body, as: UTF8.self)
    }
}
