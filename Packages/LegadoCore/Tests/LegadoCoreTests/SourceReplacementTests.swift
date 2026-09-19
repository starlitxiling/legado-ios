import XCTest
@testable import LegadoCore

final class SourceReplacementTests: XCTestCase {
    private func rule(_ id: Int64, pattern: String, replacement: String) -> ReplaceRule {
        var rule = ReplaceRule(); rule.id = id; rule.order = Int(id); rule.isRegex = false
        rule.scopeSource = true; rule.scopeContent = false; rule.pattern = pattern; rule.replacement = replacement
        return rule
    }

    func testSourceRulesUseOriginalIdentityLiteralScopesAndOrder() throws {
        var source = BookSource(); source.bookSourceUrl = "https://source.test"; source.bookSourceName = "Seed_%"
        source.ruleContent = ContentRule(); source.ruleContent?.content = "#old@text"
        var first = rule(1, pattern: "Seed_%", replacement: "Renamed"); first.scope = "SEED_%"
        var second = rule(2, pattern: "#old@text", replacement: "#new@text"); second.scope = "seed_%"
        var excluded = rule(3, pattern: "#new@text", replacement: "bad"); excluded.excludeScope = "HTTPS://SOURCE.TEST"
        var otherScope = rule(4, pattern: "#new@text", replacement: "bad"); otherScope.scope = "seed___"
        var bodyOnly = rule(5, pattern: "#new@text", replacement: "bad"); bodyOnly.scopeSource = false; bodyOnly.scopeContent = true
        let updated = try SourceReplacement(rules: [second, first, excluded, otherScope, bodyOnly]).apply(source)
        XCTAssertEqual(updated.bookSourceName, "Renamed")
        XCTAssertEqual(updated.ruleContent?.content, "#new@text")
        XCTAssertEqual(source.ruleContent?.content, "#old@text")
    }

    func testInvalidJSONAndEmptyURLAbortAndRSSUsesSameRules() throws {
        var source = BookSource(); source.bookSourceUrl = "https://source.test"; source.bookSourceName = "Seed"
        XCTAssertThrowsError(try SourceReplacement(rules: [rule(1, pattern: "{", replacement: "broken")]).apply(source))
        XCTAssertThrowsError(try SourceReplacement(rules: [rule(1, pattern: "https://source.test", replacement: "")]).apply(source))
        var rss = RssSource(); rss.sourceUrl = "https://rss.test"; rss.sourceName = "Seed"
        XCTAssertEqual(try SourceReplacement(rules: [rule(1, pattern: "Seed", replacement: "New")]).apply(rss).sourceName, "New")
    }

    func testRepositorySelectsOnlyEnabledSourceRules() async throws {
        let database = try AppDatabase.inMemory()
        let repository = ReplaceRuleRepository(database: database)
        var source = ReplaceRuleRow(); source.id = 1; source.scopeSource = true; source.order = 2
        var body = source; body.id = 2; body.scopeSource = false
        var disabled = source; disabled.id = 3; disabled.isEnabled = false
        var earlier = source; earlier.id = 4; earlier.order = 1
        try await repository.upsert([source, body, disabled, earlier])
        let selected = try await repository.listSourceRules()
        XCTAssertEqual(selected.map(\.id), [4, 1])
    }
}
