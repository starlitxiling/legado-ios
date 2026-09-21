import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class SourcesViewModel {
    private(set) var sources: [BookSourceRow] = []
    private(set) var importPreview: ManagementImportPreview?
    private(set) var isBusy = false
    var errorMessage: String?
    var keyword = ""
    var selectedGroup: String?
    var keepEnable = false
    var useSourceReplacement = false
    var filter: SourceFilter = .all
    var statusFilter: SourceStatusFilter = .all
    private(set) var metadata: [String: SourceManagementMetadata] = [:]
    var sort: SourceSort = .custom
    var ascending = true
    var selectedImportURLs: Set<String> = []
    var importGroup = ""
    var selectedURLs: Set<String> = []

    private let repository: BookSourceRepository
    private let httpClient: any ResponseLimitedHttpClient
    private let importer: SourceImporter
    private var pendingSources: [BookSourceRow] = []

    init(repository: BookSourceRepository, httpClient: any ResponseLimitedHttpClient,
         importer: SourceImporter = SourceImporter()) {
        self.repository = repository
        self.httpClient = httpClient
        self.importer = importer
    }

    var groups: [String] { Set(sources.flatMap { ManagementImport.groups($0.bookSourceGroup) }).sorted() }
    var filteredSources: [BookSourceRow] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return SourceManagement.sorted(sources.filter { source in
            filter.includes(source) && matchesStatus(source.bookSourceUrl) &&
            (selectedGroup == nil || ManagementImport.groups(source.bookSourceGroup).contains(selectedGroup!)) &&
            (query.hasPrefix("group:") ? SourceManagement.groups(source.bookSourceGroup).contains(String(query.dropFirst(6))) :
                query.isEmpty || [source.bookSourceName, source.bookSourceUrl, source.bookSourceGroup ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }, by: sort, ascending: ascending)
    }

    private func matchesStatus(_ url: String) -> Bool {
        let state = metadata[url]?.check
        switch statusFilter {
        case .all: return true
        case .passed: return state?.succeeded == true
        case .failed: return state != nil && state?.succeeded == false
        case .untested: return state == nil
        }
    }

    func reorder(_ url: String, before target: String) async {
        guard url != target else { return }
        await perform {
            try await self.repository.editSources { rows in
                var rows = SourceManagement.sorted(rows, by: .custom)
                guard let from = rows.firstIndex(where: { $0.bookSourceUrl == url }) else { return rows }
                let moving = rows.remove(at: from)
                guard let to = rows.firstIndex(where: { $0.bookSourceUrl == target }) else { return rows }
                rows.insert(moving, at: to)
                return rows.enumerated().map { index, row in var row = row; row.customOrder = index; return row }
            }
            self.sources = try await self.repository.list()
        }
    }

    func batchEnabled(_ enabled: Bool) async {
        let selected = selectedURLs
        await perform {
            try await self.repository.editSources { SourceManagement.setEnabled($0, selected: selected, enabled: enabled) }
            self.sources = try await self.repository.list()
        }
    }

    func move(selected: Set<String>, toTop: Bool) async {
        await perform {
            try await self.repository.editSources { try SourceManagement.move($0, selected: selected, toTop: toTop) }
            self.sources = try await self.repository.list()
        }
    }

    func batchExploreEnabled(_ enabled: Bool) async {
        let selected = selectedURLs
        await perform {
            try await self.repository.editSources { SourceManagement.setExploreEnabled($0, selected: selected, enabled: enabled) }
            self.sources = try await self.repository.list()
        }
    }

    func changeGroup(_ group: String, removing: Bool) async {
        let selected = selectedURLs
        let changes = SourceManagement.groups(group)
        await perform {
            try await self.repository.editSources { rows in
                rows.map { row in
                    guard selected.contains(row.bookSourceUrl) else { return row }
                    var value = row
                    var groups = SourceManagement.groups(value.bookSourceGroup)
                    if removing { groups.removeAll { changes.contains($0) } }
                    else { groups += changes.filter { !groups.contains($0) } }
                    value.bookSourceGroup = groups.joined(separator: ",")
                    return value
                }
            }
            self.sources = try await self.repository.list()
        }
    }

    func exportText(selected: Set<String>? = nil) throws -> String {
        let values = filteredSources.filter { selected == nil || selected!.contains($0.bookSourceUrl) }
        return try SourceExporter.bookSources(values.map {
            try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode($0))
        })
    }

    func load() async {
        await perform {
            self.sources = try await self.repository.list()
            self.metadata = try await self.repository.managementMetadata()
        }
    }

    func setEnabled(_ source: BookSourceRow, enabled: Bool) async {
        await perform {
            guard var current = try await self.repository.get(bookSourceUrl: source.bookSourceUrl) else { return }
            current.enabled = enabled
            try await self.repository.update(current)
            self.sources = try await self.repository.list()
        }
    }

    func delete(_ source: BookSourceRow) async {
        await perform {
            try await self.repository.delete(source)
            self.sources = try await self.repository.list()
        }
    }

    func renameGroup(_ old: String, to new: String) async {
        await perform {
            try await self.repository.editSources { rows in rows.map { row in
                var row = row
                var groups = SourceManagement.groups(row.bookSourceGroup)
                if let index = groups.firstIndex(of: old) {
                    groups.remove(at: index)
                    if !new.isEmpty && !groups.contains(new) { groups.insert(new, at: min(index, groups.count)) }
                    row.bookSourceGroup = groups.joined(separator: ",")
                }
                return row
            } }
            self.sources = try await self.repository.list()
        }
    }

    func cancelImport() {
        guard !isBusy else { return }
        pendingSources = []
        importPreview = nil
        errorMessage = nil
    }

    func prepareImport(text: String) async {
        await perform {
            self.clearPreview()
            try await self.prepare(ManagementImport.text(Data(text.utf8)))
        }
    }

    func prepareImport(url: String) async {
        await perform {
            self.clearPreview()
            let text = try await ManagementImport.download(url, client: self.httpClient)
            try await self.prepare(text)
        }
    }

    func confirmImport() async {
        guard importPreview != nil else { return }
        await perform {
            let keepEnable = self.keepEnable
            let local = Dictionary(uniqueKeysWithValues: try await self.repository.list().map { ($0.bookSourceUrl, $0) })
            let merged = self.pendingSources.filter { self.selectedImportURLs.contains($0.bookSourceUrl) }.map { imported in
                var source = imported
                if let existing = local[source.bookSourceUrl] {
                    source.customOrder = existing.customOrder
                    if keepEnable {
                        source.enabled = existing.enabled
                        source.enabledExplore = existing.enabledExplore
                    }
                }
                let addedGroups = SourceManagement.groups(self.importGroup)
                if !addedGroups.isEmpty {
                    var groups = SourceManagement.groups(source.bookSourceGroup)
                    groups += addedGroups.filter { !groups.contains($0) }
                    source.bookSourceGroup = groups.joined(separator: ",")
                }
                return source
            }
            try await self.repository.upsert(merged)
            self.clearPreview()
            self.sources = try await self.repository.list()
        }
    }

    private func prepare(_ text: String) async throws {
        let imported: [ImportedBookSource]
        switch importer.parseBookSources(text) {
        case .sources(let values): imported = values
        case .jsSource:
            if ManagementImport.isJavaScript(text) { throw ManagementImportError.unsupportedScript }
            throw ManagementImportError.invalidSourceText(String(text.prefix(80)))
        case .urls: throw ManagementImportError.urlCollection
        case .invalid: throw ManagementImportError.invalidSourceText(String(text.prefix(80)))
        }
        let replacement = useSourceReplacement ? try await repository.sourceReplacement() : SourceReplacement(rules: [])
        var unique: [String: ImportedBookSource] = [:]
        for item in imported {
            let source = try replacement.apply(item.source)
            unique[source.bookSourceUrl!] = ImportedBookSource(source: source)
        }
        let rows = try unique.values.map {
            try ManagementImport.row($0.source, defaults: BookSourceRow())
        }.sorted { ($0.customOrder, $0.bookSourceUrl) < ($1.customOrder, $1.bookSourceUrl) }
        let existingRows = try await repository.list()
        let existing = Set(existingRows.map(\.bookSourceUrl))
        let local = Dictionary(uniqueKeysWithValues: existingRows.map { ($0.bookSourceUrl, $0) })
        let overwritten = rows.filter { existing.contains($0.bookSourceUrl) }.count
        pendingSources = rows
        selectedImportURLs = Set(rows.map(\.bookSourceUrl))
        importPreview = ManagementImportPreview(newCount: rows.count - overwritten,
                                               overwriteCount: overwritten, unsupportedCount: 0,
                                               jsSourceCount: rows.filter { !($0.mainJs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
                                               items: try rows.map { row in
                                                   let same = try local[row.bookSourceUrl].map { try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode($0)) == JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(row)) } ?? false
                                                   return ManagementImportItem(id: row.bookSourceUrl, title: row.bookSourceName,
                                                       status: local[row.bookSourceUrl] == nil ? "新增" : same ? "相同" : "更新")
                                               })
    }

    private func clearPreview() {
        pendingSources = []
        importPreview = nil
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }
}
