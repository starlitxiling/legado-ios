import Foundation
import Observation
import LegadoCore

@Observable @MainActor
final class RulesManagementModel {
    enum Kind { case txt, dictionary }
    let kind: Kind
    private(set) var txtRules: [TxtTocRule] = []
    private(set) var dictRules: [DictRule] = []
    var txtDraft = TxtTocRule(id: 0, name: "", rule: "")
    var dictDraft = DictRule()
    var jsonText = ""
    var errorMessage: String?
    private(set) var isBusy = false
    private let txtRepository: TxtTocRuleRepository
    private let dictRepository: DictRuleRepository
    private var originalName: String?

    init(kind: Kind, database: AppDatabase) {
        self.kind = kind
        txtRepository = TxtTocRuleRepository(database: database)
        dictRepository = DictRuleRepository(database: database)
    }

    func load() async {
        await perform {
            self.txtRules = try await self.txtRepository.list()
            self.dictRules = try await self.dictRepository.list()
        }
    }

    func newRule(now: Int64) {
        let occupied = Set(txtRules.map(\.id))
        var id = now
        while occupied.contains(id) && id < Int64.max { id += 1 }
        txtDraft = TxtTocRule(id: id, name: "", rule: "")
        dictDraft = DictRule(); originalName = nil; errorMessage = nil
    }

    func edit(_ rule: DictRule) { dictDraft = rule; originalName = rule.name; errorMessage = nil }
    func edit(_ rule: TxtTocRule) { txtDraft = rule; errorMessage = nil }

    func saveDraft() async -> Bool {
        guard !isBusy else { return false }
        await perform {
            if self.kind == .txt {
                guard !self.txtDraft.name.isEmpty, !self.txtDraft.rule.isEmpty else { throw SourceEditError.invalidValue("名称和规则") }
                try await self.txtRepository.save(self.txtDraft)
                self.txtRules = try await self.txtRepository.list()
            } else {
                try await self.dictRepository.saveEdited(self.dictDraft, replacing: self.originalName)
                self.dictRules = try await self.dictRepository.list()
            }
        }
        return errorMessage == nil
    }

    func setEnabled(_ rule: TxtTocRule, enabled: Bool) async {
        await perform {
            var value = rule; value.enable = enabled
            try await self.txtRepository.save(value)
            self.txtRules = try await self.txtRepository.list()
        }
    }

    func setEnabled(_ rule: DictRule, enabled: Bool) async {
        await perform {
            var value = rule; value.enabled = enabled
            try await self.dictRepository.save(value)
            self.dictRules = try await self.dictRepository.list()
        }
    }

    func delete(_ rule: TxtTocRule) async {
        await perform { try await self.txtRepository.delete(id: rule.id); self.txtRules = try await self.txtRepository.list() }
    }

    func delete(_ rule: DictRule) async {
        await perform { try await self.dictRepository.delete(name: rule.name); self.dictRules = try await self.dictRepository.list() }
    }

    func importJSON(now: Int64) async -> Bool {
        guard !isBusy else { return false }
        await perform {
            let raw = try JSONSerialization.jsonObject(with: Data(self.jsonText.utf8))
            guard let objects = (raw as? [[String: Any]]) ?? (raw as? [String: Any]).map({ [$0] }) else {
                throw SourceEditError.invalidJSON
            }
            if self.kind == .txt {
                var occupied = Set(self.txtRules.map(\.id))
                for object in objects {
                    if let id = object["id"], !(id is NSNull) {
                        let data = try JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed])
                        occupied.insert(try JSONDecoder().decode(Int64.self, from: data))
                    }
                }
                var nextID = now
                let values = try objects.map { object -> TxtTocRule in
                    var fields = object
                    if fields["id"] == nil || fields["id"] is NSNull {
                        while occupied.contains(nextID) {
                            guard nextID < Int64.max else { throw SourceEditError.orderOverflow }
                            nextID += 1
                        }
                        fields["id"] = nextID; occupied.insert(nextID)
                    }
                    return try JSONDecoder().decode(TxtTocRule.self, from: JSONSerialization.data(withJSONObject: fields))
                }
                try await self.txtRepository.save(values)
                self.txtRules = try await self.txtRepository.list()
            } else {
                let values = try JSONDecoder().decode([DictRule].self, from: JSONSerialization.data(withJSONObject: objects))
                try await self.dictRepository.save(values)
                self.dictRules = try await self.dictRepository.list()
            }
        }
        return errorMessage == nil
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }
}
