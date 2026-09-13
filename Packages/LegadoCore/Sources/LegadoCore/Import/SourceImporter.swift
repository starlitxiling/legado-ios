import Foundation

public enum JavaScriptSourceSupport: Equatable {
    case unsupported
}

public enum BookSourceSupport: Equatable {
    case supported
    case unsupportedJavaScript
}

public struct ImportedBookSource: Equatable {
    public let source: BookSource
    public let support: BookSourceSupport

    public init(source: BookSource) {
        self.source = source
        let hasScript = !(source.mainJs?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        support = hasScript ? .unsupportedJavaScript : .supported
    }
}

public enum BookSourceImportResult: Equatable {
    case sources([ImportedBookSource])
    case urls([String])
    /// 仅表示进入 Kotlin 的非 JSON 脚本分支，不代表脚本有效。
    case jsSource(JavaScriptSourceSupport)
    case invalid
}

public enum ReplaceRuleImportResult: Equatable {
    case rules([ReplaceRule])
    case invalid
}

/// 只解析文本，不请求 URL、不执行脚本、不写入数据库。
public struct SourceImporter {
    private let now: () -> Int64

    public init(now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis) {
        self.now = now
    }

    /// Kotlin: BookSourceImport.kt:88；ImportBookSourceViewModel.kt:277。
    public func parseBookSources(_ text: String) -> BookSourceImportResult {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .invalid }
        let isObject = text.hasPrefix("{") && text.hasSuffix("}")
        let isArray = text.hasPrefix("[") && text.hasSuffix("]")
        guard isObject || isArray else { return .jsSource(.unsupported) }
        do {
            let data = Data(text.utf8)
            let tree = try GsonValue.parse(data)
            let decoder = GsonJSONDecoder(now: now)
            switch tree {
            case .array:
                let sources = try decoder.decode([BookSource].self, from: data)
                guard sources.allSatisfy(Self.hasSourceURL) else { return .invalid }
                return .sources(sources.map(ImportedBookSource.init))
            case .object:
                if let urls = tree["sourceUrls"] {
                    guard case let .array(values) = urls else { return .invalid }
                    let strings = values.compactMap(\.stringValue)
                    guard strings.count == values.count,
                          strings.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return .invalid }
                    return .urls(strings)
                }
                let source = try decoder.decode(BookSource.self, from: data)
                return Self.hasSourceURL(source) ? .sources([ImportedBookSource(source: source)]) : .invalid
            default: return .invalid
            }
        } catch { return .invalid }
    }

    /// Kotlin: ReplaceAnalyzer.kt:9、25；网络 URL 与 URI 的读取由调用方负责。
    public func parseReplaceRules(_ text: String) -> ReplaceRuleImportResult {
        do {
            let tree = try GsonValue.parse(Data(text.utf8))
            switch tree {
            case let .array(values):
                var rules: [ReplaceRule] = []
                for value in values {
                    let rule = try replacement(value)
                    guard let pattern = rule.pattern else { throw invalidReplacement() }
                    let trailingPipe = pattern.hasSuffix("|") && !pattern.hasSuffix("\\|")
                    if !rule.isRegex || (!trailingPipe && (try? NSRegularExpression(pattern: pattern)) != nil) {
                        rules.append(rule)
                    }
                }
                return .rules(rules)
            case .object: return .rules([try replacement(tree)])
            default: return .invalid
            }
        } catch { return .invalid }
    }

    private static func hasSourceURL(_ source: BookSource) -> Bool {
        !(source.bookSourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func replacement(_ tree: GsonValue) throws -> ReplaceRule {
        guard case .object = tree else { throw invalidReplacement() }
        let decoder = GsonJSONDecoder(now: now)
        if let rule = try? decoder.decode(ReplaceRule.self, from: Data(tree.json.utf8)), let pattern = rule.pattern, !pattern.isEmpty {
            return rule
        }
        guard let pattern = tree["regex"]?.stringValue, !pattern.isEmpty else { throw invalidReplacement() }
        var rule = ReplaceRule(now: now())
        if let id = tree["id"]?.mappedLong { rule.id = id }
        rule.pattern = pattern
        rule.name = tree["replaceSummary"]?.stringValue ?? ""
        rule.replacement = tree["replacement"]?.stringValue ?? ""
        rule.scope = tree["useTo"]?.stringValue
        rule.isRegex = tree["isRegex"]?.stringValue?.lowercased() == "true"
        rule.isEnabled = tree["enable"]?.stringValue?.lowercased() == "true"
        rule.order = tree["serialNumber"]?.mappedInt ?? 0
        return rule
    }

    private func invalidReplacement() -> DecodingError {
        .dataCorrupted(.init(codingPath: [], debugDescription: "替换规则缺少 pattern 或 regex"))
    }
}
