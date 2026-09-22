import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class ReplaceRulesViewModel {
    private(set) var rules: [ReplaceRuleRow] = []
    private(set) var importPreview: ManagementImportPreview?
    private(set) var isBusy = false
    var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
    func dismissError() { userError = nil }
    var keyword = ""
    var selectedGroup: String?

    private let repository: ReplaceRuleRepository
    private let httpClient: any ResponseLimitedHttpClient
    private let now: () -> Int64
    private var pendingRules: [ReplaceRuleRow] = []

    init(repository: ReplaceRuleRepository, httpClient: any ResponseLimitedHttpClient,
         now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis) {
        self.repository = repository
        self.httpClient = httpClient
        self.now = now
    }

    var groups: [String] { Set(rules.flatMap { ManagementImport.groups($0.group) }).sorted() }
    var filteredRules: [ReplaceRuleRow] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return rules.filter { rule in
            (selectedGroup == nil || ManagementImport.groups(rule.group).contains(selectedGroup!)) &&
            (query.isEmpty || [rule.name, rule.pattern, rule.group ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    func load() async { await perform(operation: "读取替换规则", subject: nil) { self.rules = try await self.repository.list() } }

    func setEnabled(_ rule: ReplaceRuleRow, enabled: Bool) async {
        await perform(operation: "切换替换规则状态", subject: rule.name) {
            guard let id = rule.id, var current = try await self.repository.get(id: id) else { return }
            current.isEnabled = enabled
            try await self.repository.update(current)
            self.rules = try await self.repository.list()
        }
    }

    func delete(_ rule: ReplaceRuleRow) async {
        await perform(operation: "删除替换规则", subject: rule.name) {
            try await self.repository.delete(rule)
            self.rules = try await self.repository.list()
        }
    }

    func cancelImport() {
        guard !isBusy else { return }
        clearPreview()
        userError = nil
    }

    func prepareImport(text: String) async {
        await perform(operation: "解析导入替换规则", subject: nil) {
            self.clearPreview()
            try await self.prepare(ManagementImport.text(Data(text.utf8)))
        }
    }

    func prepareImport(url: String) async {
        await perform(operation: "下载导入替换规则", subject: url) {
            self.clearPreview()
            let text = try await ManagementImport.download(url, client: self.httpClient)
            try await self.prepare(text)
        }
    }

    func confirmImport() async {
        guard importPreview != nil else { return }
        await perform(operation: "保存导入替换规则", subject: nil) {
            try await self.repository.upsert(self.pendingRules)
            self.clearPreview()
            self.rules = try await self.repository.list()
        }
    }

    private func prepare(_ text: String) async throws {
        // 同一次导入中缺省 ID 的规则需要各自的主键，不能共享毫秒时间戳。
        var nextID = now()
        let importer = SourceImporter(now: { defer { nextID += 1 }; return nextID })
        guard case let .rules(imported) = importer.parseReplaceRules(text) else {
            throw ManagementImportError.invalidText
        }
        var unique: [Int64: ReplaceRuleRow] = [:]
        var automatic: [ReplaceRuleRow] = []
        for rule in imported {
            var row = try ManagementImport.row(rule, defaults: ReplaceRuleRow())
            if rule.id == 0 {
                row.id = nil
                automatic.append(row)
            } else {
                unique[rule.id] = row
            }
        }
        // 先保存显式主键，再分配自增主键，避免自增值撞到同批显式 ID。
        let rows = unique.values.sorted { ($0.order, $0.id ?? 0) < ($1.order, $1.id ?? 0) } + automatic
        let existing = Set(try await repository.list().compactMap(\.id))
        let overwritten = rows.filter { $0.id.map(existing.contains) ?? false }.count
        pendingRules = rows
        importPreview = ManagementImportPreview(newCount: rows.count - overwritten,
                                               overwriteCount: overwritten, unsupportedCount: 0)
    }

    private func clearPreview() {
        pendingRules = []
        importPreview = nil
    }

    private func perform(operation: String, subject: String?, _ action: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        userError = nil
        defer { isBusy = false }
        do { try await action() }
        catch { userError = error.presentation(operation: operation, subject: subject) }
    }
}
