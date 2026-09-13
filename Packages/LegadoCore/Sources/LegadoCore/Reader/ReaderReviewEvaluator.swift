import Foundation

public struct ReaderReviewSummary: Equatable, Sendable {
    public var counts: [Int: Int] = [:]
    public var keys: [Int: String] = [:]
}

public struct ReaderReviewItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var content: String
    public var avatar: String
}

/// 只求值段评规则；不会执行发布、投票和删除请求。
public enum ReaderReviewEvaluator {
    private static func parseInt(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let integer = Int32(value) { return Int(integer) }
        guard let number = Double(value) else { return nil }
        if number.isNaN { return 0 }
        if number >= Double(Int32.max) { return Int(Int32.max) }
        if number <= Double(Int32.min) { return Int(Int32.min) }
        return Int(number)
    }
    private static func parser(_ body: String, supplied: AnalyzeRule?) -> AnalyzeRule {
        let parser = supplied ?? AnalyzeRule(engines: [.default: AnalyzeByJSoup(), .xpath: AnalyzeByXPath(), .json: AnalyzeByJSonPath()])
        parser.setContent(body)
        return parser
    }

    public static func summary(body: String, rule: ReviewRule, parser supplied: AnalyzeRule? = nil) throws -> ReaderReviewSummary {
        guard rule.enabled, let list = rule.summaryListRule, !list.isEmpty,
              let indexRule = rule.summaryParagraphIndexRule, !indexRule.isEmpty else { return ReaderReviewSummary() }
        let parser = parser(body, supplied: supplied)
        let items = try parser.getElements(list)
        var result = ReaderReviewSummary()
        for (offset, item) in items.enumerated() {
            parser.setContent(item)
            let indexValue = try? parser.getString(indexRule)
            let index = indexValue.flatMap(parseInt) ?? offset + 1
            let count = (try? parser.getString(rule.summaryCountRule)).flatMap(parseInt) ?? 0
            guard index != 0, count > 0 else { continue }
            result.counts[index] = count
            let key = try? parser.getString(rule.summaryParagraphDataRule)
            result.keys[index] = key.flatMap { $0.isEmpty ? nil : $0 } ?? indexValue ?? String(index)
        }
        return result
    }

    public static func details(body: String, rule: ReviewRule, parser supplied: AnalyzeRule? = nil) throws -> [ReaderReviewItem] {
        guard rule.enabled, let list = rule.detailListRule, !list.isEmpty else { return [] }
        let parser = parser(body, supplied: supplied)
        return try parser.getElements(list).enumerated().map { offset, item in
            parser.setContent(item)
            return ReaderReviewItem(id: (try? parser.getString(rule.detailIdRule)).flatMap { $0.isEmpty ? nil : $0 } ?? String(offset),
                name: (try? parser.getString(rule.detailNameRule)) ?? "",
                content: (try? parser.getString(rule.detailContentRule)) ?? "",
                avatar: (try? parser.getString(rule.detailAvatarRule)) ?? "")
        }
    }
}
