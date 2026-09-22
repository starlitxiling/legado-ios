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
    var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
    private let original: BookSource
    private var invalidFields: [String: String] = [:]

    init(source: BookSource = BookSource(), isNew: Bool = true) {
        self.source = source; original = source
        originalURL = isNew ? nil : source.bookSourceUrl
        jsonText = (try? SourceExporter.bookSource(source)) ?? "{}"
    }

    static let groups: [SourceFieldGroup] = {
        func group(_ title: String, _ prefix: String, _ fields: [String]) -> SourceFieldGroup {
            SourceFieldGroup(title: title, fields: fields.map { prefix.isEmpty ? $0 : prefix + "." + $0 })
        }
        let list = ["bookList","name","author","kind","wordCount","lastChapter","intro","coverUrl","bookUrl"]
        return [
            group("基本", "", ["bookSourceUrl","bookSourceName","bookSourceGroup","bookSourceComment","loginUrl","loginUi","loginCheckJs","coverDecodeJs","bookUrlPattern","header","variableComment","concurrentRate","jsLib"]),
            SourceFieldGroup(title: "搜索", fields: ["searchUrl","ruleSearch.checkKeyWord"] + list.map { "ruleSearch." + $0 }),
            SourceFieldGroup(title: "发现", fields: ["exploreUrl"] + list.map { "ruleExplore." + $0 }),
            group("详情", "ruleBookInfo", ["init","name","author","kind","wordCount","lastChapter","intro","coverUrl","tocUrl","canReName","downloadUrls"]),
            group("目录", "ruleToc", ["preUpdateJs","chapterList","chapterName","chapterUrl","formatJs","isVolume","updateTime","isVip","isPay","nextTocUrl"]),
            group("正文", "ruleContent", ["content","nextContentUrl","subContent","replaceRegex","title","sourceRegex","imageStyle","imageDecode","webJs","payAction","callBackJs","contentBatch","maxBatchSize"]),
            group("段评", "ruleReview", ["reviewSummaryUrl","summaryListRule","summaryParagraphIndexRule","summaryCountRule","summaryParagraphDataRule","reviewDetailUrl","reviewDetailNextPageUrl","detailListRule","detailIdRule","detailAvatarRule","detailNameRule","detailBadgeRule","detailContentRule","reviewQuoteUrl","replyListRule","replyIdRule","replyAvatarRule","replyNameRule","replyBadgeRule","replyContentRule"])
        ]
    }()

    static func label(_ path: String) -> String {
        let key = String(path.split(separator: ".").last ?? "")
        return ["bookSourceUrl":"源 URL","bookSourceName":"源名称","bookSourceGroup":"源分组","bookSourceComment":"源注释",
            "loginUrl":"登录 URL","loginUi":"登录 UI","loginCheckJs":"登录检查 JS","coverDecodeJs":"封面解密","bookUrlPattern":"书籍 URL 正则",
            "header":"请求头","variableComment":"变量说明","concurrentRate":"并发率","jsLib":"JS 库","searchUrl":"搜索地址","checkKeyWord":"校验关键字",
            "exploreUrl":"发现地址","bookList":"书籍列表","name":"书名","author":"作者","kind":"分类","wordCount":"字数","lastChapter":"最新章节",
            "intro":"简介","coverUrl":"封面","bookUrl":"详情页 URL","init":"预处理","tocUrl":"目录 URL","canReName":"允许改名","downloadUrls":"下载 URL",
            "preUpdateJs":"更新前 JS","chapterList":"目录列表","chapterName":"章节名称","chapterUrl":"章节 URL","formatJs":"格式化","isVolume":"Volume 标识",
            "updateTime":"章节信息","isVip":"VIP 标识","isPay":"购买标识","nextTocUrl":"下一页","content":"正文","nextContentUrl":"下一页 URL",
            "subContent":"副文","replaceRegex":"替换","title":"章节名称","sourceRegex":"资源正则","imageStyle":"图片样式","imageDecode":"图片解密",
            "webJs":"WebView JS","payAction":"购买操作","callBackJs":"回调","contentBatch":"批量正文","maxBatchSize":"最大批量",
            "reviewSummaryUrl":"统计地址","summaryListRule":"统计列表","summaryParagraphIndexRule":"段落序号","summaryCountRule":"评论数量","summaryParagraphDataRule":"段落数据",
            "reviewDetailUrl":"详情地址","reviewDetailNextPageUrl":"详情下一页","detailListRule":"评论列表","detailIdRule":"评论 ID","detailAvatarRule":"评论头像",
            "detailNameRule":"评论昵称","detailBadgeRule":"评论徽章","detailContentRule":"评论正文","reviewQuoteUrl":"回复地址","replyListRule":"回复列表",
            "replyIdRule":"回复 ID","replyAvatarRule":"回复头像","replyNameRule":"回复昵称","replyBadgeRule":"回复徽章","replyContentRule":"回复正文"][key] ?? key
    }

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
