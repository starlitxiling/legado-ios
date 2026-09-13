import Foundation
import Observation
import LegadoCore

enum SourceEditError: LocalizedError {
    case missingNameOrURL, duplicateURL, invalidJSON, invalidValue(String), orderOverflow
    var errorDescription: String? {
        switch self {
        case .missingNameOrURL: return "书源名称和地址不能为空"
        case .duplicateURL: return "已存在相同地址的书源"
        case .invalidJSON: return "JSON 格式无效或列表为空"
        case .invalidValue(let field): return "字段格式不正确：\(field)"
        case .orderOverflow: return "排序编号超出范围，请先重新排序"
        }
    }
}

struct SourceFieldGroup: Identifiable {
    let title: String
    let fields: [String]
    var id: String { title }
}

@Observable @MainActor
final class BookSourceEditModel {
    private(set) var source: BookSource
    let originalURL: String?
    var jsonText: String
    var errorMessage: String?
    private let original: BookSource
    private var invalidFields: [String: String] = [:]

    init(source: BookSource = BookSource(), isNew: Bool = true) {
        self.source = source; original = source
        originalURL = isNew ? nil : source.bookSourceUrl
        jsonText = (try? SourceExporter.bookSource(source)) ?? "{}"
    }

    static let groups: [SourceFieldGroup] = {
        func keys(_ value: Any, prefix: String) -> [String] {
            Mirror(reflecting: value).children.compactMap { $0.label.map { prefix + "." + $0 } }
        }
        let login = ["loginUrl", "loginUi", "loginCheckJs"]
        let search = ["searchUrl"] + keys(SearchRule(), prefix: "ruleSearch")
        let explore = ["exploreUrl", "exploreScreen"] + keys(ExploreRule(), prefix: "ruleExplore")
        let excluded = Set(login + ["searchUrl", "exploreUrl", "exploreScreen", "ruleSearch", "ruleExplore",
                                    "ruleBookInfo", "ruleToc", "ruleContent", "ruleReview"])
        return [SourceFieldGroup(title: "基本", fields: Mirror(reflecting: BookSource()).children.compactMap(\.label).filter { !excluded.contains($0) }),
                SourceFieldGroup(title: "搜索", fields: search), SourceFieldGroup(title: "发现", fields: explore),
                SourceFieldGroup(title: "详情", fields: keys(BookInfoRule(), prefix: "ruleBookInfo")),
                SourceFieldGroup(title: "目录", fields: keys(TocRule(), prefix: "ruleToc")),
                SourceFieldGroup(title: "正文", fields: keys(ContentRule(), prefix: "ruleContent") + keys(ReviewRule(), prefix: "ruleReview")),
                SourceFieldGroup(title: "登录", fields: login)]
    }()

    func value(_ path: String) -> String {
        if let value = invalidFields[path] { return value }
        guard var current = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) else { return "" }
        for part in path.split(separator: ".") { current = (current as? [String: Any])?[String(part)] ?? NSNull() }
        if current is NSNull { return "" }
        if Self.booleans.contains(path), let number = current as? NSNumber { return number.boolValue ? "true" : "false" }
        return String(describing: current)
    }

    private static let booleans: Set<String> = ["enabled", "enabledExplore", "enabledCookieJar", "eventListener", "customButton", "ruleReview.enabled"]
    private static let integers: Set<String> = ["bookSourceType", "customOrder", "lastUpdateTime", "respondTime", "weight", "ruleContent.maxBatchSize"]

    func setValue(_ text: String, for path: String) throws {
        invalidFields[path] = text
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
        let parts = path.split(separator: ".").map(String.init)
        let value: Any
        if Self.booleans.contains(path) {
            if text.isEmpty && path == "enabledCookieJar" { value = NSNull() }
            else if text == "true" { value = true }
            else if text == "false" { value = false }
            else { throw SourceEditError.invalidValue(path) }
        } else if Self.integers.contains(path) {
            if text.isEmpty && path == "ruleContent.maxBatchSize" { value = NSNull() }
            else if let number = Int64(text) {
                if path != "lastUpdateTime" && path != "respondTime" && Int32(exactly: number) == nil {
                    throw SourceEditError.invalidValue(path)
                }
                value = number
            }
            else { throw SourceEditError.invalidValue(path) }
        } else { value = text }
        if parts.count == 2 {
            var nested = fields[parts[0]] as? [String: Any] ?? [:]
            nested[parts[1]] = value; fields[parts[0]] = nested
        } else { fields[path] = value }
        source = try JSONDecoder().decode(BookSource.self, from: JSONSerialization.data(withJSONObject: fields))
        jsonText = try SourceExporter.bookSource(source)
        invalidFields.removeValue(forKey: path)
    }

    func applyJSON(_ text: String) throws {
        let data = Data(text.utf8)
        let raw = try JSONSerialization.jsonObject(with: data)
        let parsed: BookSource
        if raw is [Any] {
            guard let first = try JSONDecoder().decode([BookSource].self, from: data).first else {
                throw SourceEditError.invalidJSON
            }
            parsed = first
        } else if raw is [String: Any] {
            parsed = try JSONDecoder().decode(BookSource.self, from: data)
        } else { throw SourceEditError.invalidJSON }
        let normalized = try SourceExporter.bookSource(parsed)
        source = parsed; jsonText = normalized; invalidFields = [:]
    }

    func validated(existingURLs: Set<String>, now: Int64) throws -> BookSource {
        if let field = invalidFields.keys.sorted().first { throw SourceEditError.invalidValue(field) }
        var saved = source
        guard let url = saved.bookSourceUrl, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let name = saved.bookSourceName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceEditError.missingNameOrURL
        }
        guard url == originalURL || !existingURLs.contains(url) else { throw SourceEditError.duplicateURL }
        if originalURL == nil || saved != original { saved.lastUpdateTime = now }
        return saved
    }

    func save(repository: BookSourceRepository, jsonMode: Bool, now: Int64) async throws {
        if jsonMode { try applyJSON(jsonText) }
        let rows = try await repository.list()
        let saved = try validated(existingURLs: Set(rows.map(\.bookSourceUrl)), now: now)
        try await repository.saveEdited(ManagementImport.row(saved, defaults: BookSourceRow()), replacing: originalURL)
    }
}
