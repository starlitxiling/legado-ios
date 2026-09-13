import Foundation
import Observation
import LegadoCore

@Observable @MainActor
final class ReplaceRuleEditModel {
    var rule: ReplaceRuleRow
    var jsonText = ""
    var errorMessage: String?
    private let originalID: Int64?

    init(rule: ReplaceRuleRow = ReplaceRuleRow()) { self.rule = rule; originalID = rule.id }

    func validate() throws {
        guard !rule.pattern.isEmpty else { throw SourceEditError.invalidValue("pattern") }
        if rule.isRegex {
            _ = try NSRegularExpression(pattern: rule.pattern)
            if rule.pattern.hasSuffix("|") && !rule.pattern.hasSuffix("\\|") { throw SourceEditError.invalidValue("pattern") }
        }
    }

    func applyJSON() throws {
        let data = Data(jsonText.utf8)
        guard (try JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw SourceEditError.invalidJSON }
        let entity = try JSONDecoder().decode(ReplaceRule.self, from: data)
        var parsed: ReplaceRuleRow = try ManagementImport.row(entity, defaults: ReplaceRuleRow())
        parsed.id = originalID
        rule = parsed
    }

    func save(repository: ReplaceRuleRepository) async throws {
        try validate()
        if rule.order == Int(Int32.min) {
            let rows = try await repository.list()
            let maximum = rows.map(\.order).max() ?? -1
            guard maximum < Int(Int32.max) else { throw SourceEditError.orderOverflow }
            rule.order = maximum + 1
        }
        rule = try await repository.upsert(rule)
    }

    static func export(_ rows: [ReplaceRuleRow]) throws -> String {
        try SourceExporter.replaceRules(rows.map { row in
            var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as! [String: Any]
            fields["order"] = fields.removeValue(forKey: "sortOrder")
            return try JSONDecoder().decode(ReplaceRule.self, from: JSONSerialization.data(withJSONObject: fields))
        })
    }
}
