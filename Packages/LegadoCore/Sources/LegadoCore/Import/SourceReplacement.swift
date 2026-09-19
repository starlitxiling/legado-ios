import Foundation

public enum SourceReplacementError: Error, Equatable, LocalizedError {
    case invalidBookSource
    case invalidRssSource
    case failedRule(Int64)

    public var errorDescription: String? {
        switch self {
        case .invalidBookSource: return "书源替换结果不是有效书源，请检查替换规则或关闭导入净化。"
        case .invalidRssSource: return "RSS 替换结果不是有效订阅源，请检查替换规则或关闭导入净化。"
        case let .failedRule(id): return "书源替换规则 \(id) 执行失败，请检查其表达式和替换内容。"
        }
    }
}

public struct SourceReplacement {
    private let processor: ContentProcessor

    public init(rules: [ReplaceRule]) { processor = ContentProcessor(rules: rules) }

    public func apply(_ source: BookSource) throws -> BookSource {
        guard let json = try replace(source, name: source.bookSourceName ?? "", url: source.bookSourceUrl ?? "") else { return source }
        guard let data = json.data(using: .utf8), (try? GsonValue.parse(data)) != nil,
              case let .sources(values) = SourceImporter().parseBookSources(json), values.count == 1 else {
            throw SourceReplacementError.invalidBookSource
        }
        return values[0].source
    }

    public func apply(_ source: RssSource) throws -> RssSource {
        guard let json = try replace(source, name: source.sourceName, url: source.sourceUrl) else { return source }
        guard case let .sources(values) = SourceImporter().parseRssSources(json), values.count == 1 else {
            throw SourceReplacementError.invalidRssSource
        }
        return values[0]
    }

    private func replace<T: Encodable>(_ source: T, name: String, url: String) throws -> String? {
        let rules = processor.rules.filter { matches($0, name: name, url: url) }
        guard !rules.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var json = String(decoding: try encoder.encode(source), as: UTF8.self)
        for rule in rules {
            try Task.checkCancellation()
            do { json = try processor.apply(rule, to: json) }
            catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                throw SourceReplacementError.failedRule(rule.id)
            }
        }
        return json
    }

    private func matches(_ rule: ReplaceRule, name: String, url: String) -> Bool {
        guard rule.isEnabled, rule.scopeSource, !(rule.pattern ?? "").isEmpty else { return false }
        func contains(_ scope: String) -> Bool {
            [name, url].contains { value in
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && scope.range(of: value, options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) != nil
            }
        }
        return (rule.scope?.isEmpty != false || contains(rule.scope ?? ""))
            && (rule.excludeScope?.isEmpty != false || !contains(rule.excludeScope ?? ""))
    }
}
