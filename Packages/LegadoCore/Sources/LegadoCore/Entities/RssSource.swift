import Foundation
import GRDB

public struct RssSource: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "rssSources"
    public var sourceUrl: String = ""
    public var sourceName: String = ""
    public var sourceIcon: String = ""
    public var sourceGroup: String? = nil
    public var sourceComment: String? = nil
    public var enabled: Bool = true
    public var variableComment: String? = nil
    public var jsLib: String? = nil
    public var enabledCookieJar: Bool? = true
    public var concurrentRate: String? = nil
    public var header: String? = nil
    public var loginUrl: String? = nil
    public var loginUi: String? = nil
    public var loginCheckJs: String? = nil
    public var coverDecodeJs: String? = nil
    public var sortUrl: String? = nil
    public var singleUrl: Bool = false
    public var articleStyle: Int = 0
    public var ruleArticles: String? = nil
    public var ruleNextPage: String? = nil
    public var ruleTitle: String? = nil
    public var rulePubDate: String? = nil
    public var ruleDescription: String? = nil
    public var ruleImage: String? = nil
    public var ruleLink: String? = nil
    public var ruleContent: String? = nil
    public var nextContentUrl: String? = nil
    public var contentWhitelist: String? = nil
    public var contentBlacklist: String? = nil
    public var shouldOverrideUrlLoading: String? = nil
    public var style: String? = nil
    public var enableJs: Bool = true
    public var loadWithBaseUrl: Bool = true
    public var injectJs: String? = nil
    public var preloadJs: String? = nil
    public var startHtml: String? = nil
    public var startStyle: String? = nil
    public var startJs: String? = nil
    public var showWebLog: Bool = false
    public var lastUpdateTime: Int64 = 0
    public var customOrder: Int = 0
    public var type: Int = 0
    public var preload: Bool = false
    public var cacheFirst: Bool = false
    public var searchUrl: String? = nil
    public init(sourceUrl: String = "", sourceName: String = "") { self.sourceUrl = sourceUrl; self.sourceName = sourceName }
    private enum CodingKeys: String, CodingKey {
        case sourceUrl, sourceName, sourceIcon, sourceGroup, sourceComment, enabled, variableComment, jsLib, enabledCookieJar, concurrentRate, header, loginUrl, loginUi, loginCheckJs, coverDecodeJs, sortUrl, singleUrl, articleStyle, ruleArticles, ruleNextPage, ruleTitle, rulePubDate, ruleDescription, ruleImage, ruleLink, ruleContent, nextContentUrl, contentWhitelist, contentBlacklist, shouldOverrideUrlLoading, style, enableJs, loadWithBaseUrl, injectJs, preloadJs, startHtml, startStyle, startJs, showWebLog, lastUpdateTime, customOrder, type, preload, cacheFirst, searchUrl
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceUrl = try c.gsonString(forKey: .sourceUrl) ?? ""
        sourceName = try c.gsonString(forKey: .sourceName) ?? ""
        sourceIcon = try c.gsonString(forKey: .sourceIcon) ?? ""
        sourceGroup = try c.gsonString(forKey: .sourceGroup)
        sourceComment = try c.gsonString(forKey: .sourceComment)
        enabled = try c.gsonBool(forKey: .enabled) ?? true
        variableComment = try c.gsonString(forKey: .variableComment)
        jsLib = try c.gsonString(forKey: .jsLib)
        enabledCookieJar = c.contains(.enabledCookieJar) ? try c.gsonBool(forKey: .enabledCookieJar) : true
        concurrentRate = try c.gsonString(forKey: .concurrentRate)
        header = try c.gsonString(forKey: .header)
        loginUrl = try c.gsonString(forKey: .loginUrl)
        loginUi = try c.gsonString(forKey: .loginUi)
        loginCheckJs = try c.gsonString(forKey: .loginCheckJs)
        coverDecodeJs = try c.gsonString(forKey: .coverDecodeJs)
        sortUrl = try c.gsonString(forKey: .sortUrl)
        singleUrl = try c.gsonBool(forKey: .singleUrl) ?? false
        articleStyle = try c.gsonInt(forKey: .articleStyle) ?? 0
        ruleArticles = try c.gsonString(forKey: .ruleArticles)
        ruleNextPage = try c.gsonString(forKey: .ruleNextPage)
        ruleTitle = try c.gsonString(forKey: .ruleTitle)
        rulePubDate = try c.gsonString(forKey: .rulePubDate)
        ruleDescription = try c.gsonString(forKey: .ruleDescription)
        ruleImage = try c.gsonString(forKey: .ruleImage)
        ruleLink = try c.gsonString(forKey: .ruleLink)
        ruleContent = try c.gsonString(forKey: .ruleContent)
        nextContentUrl = try c.gsonString(forKey: .nextContentUrl)
        contentWhitelist = try c.gsonString(forKey: .contentWhitelist)
        contentBlacklist = try c.gsonString(forKey: .contentBlacklist)
        shouldOverrideUrlLoading = try c.gsonString(forKey: .shouldOverrideUrlLoading)
        style = try c.gsonString(forKey: .style)
        enableJs = try c.gsonBool(forKey: .enableJs) ?? true
        loadWithBaseUrl = try c.gsonBool(forKey: .loadWithBaseUrl) ?? true
        injectJs = try c.gsonString(forKey: .injectJs)
        preloadJs = try c.gsonString(forKey: .preloadJs)
        startHtml = try c.gsonString(forKey: .startHtml)
        startStyle = try c.gsonString(forKey: .startStyle)
        startJs = try c.gsonString(forKey: .startJs)
        showWebLog = try c.gsonBool(forKey: .showWebLog) ?? false
        lastUpdateTime = try c.gsonLong(forKey: .lastUpdateTime) ?? 0
        customOrder = try c.gsonInt(forKey: .customOrder) ?? 0
        type = try c.gsonInt(forKey: .type) ?? 0
        preload = try c.gsonBool(forKey: .preload) ?? false
        cacheFirst = try c.gsonBool(forKey: .cacheFirst) ?? false
        searchUrl = try c.gsonString(forKey: .searchUrl)
    }
    public init(row: Row) {
        sourceUrl = row["sourceUrl"]
        sourceName = row["sourceName"]
        sourceIcon = row["sourceIcon"]
        sourceGroup = row["sourceGroup"]
        sourceComment = row["sourceComment"]
        enabled = row["enabled"]
        variableComment = row["variableComment"]
        jsLib = row["jsLib"]
        enabledCookieJar = row["enabledCookieJar"]
        concurrentRate = row["concurrentRate"]
        header = row["header"]
        loginUrl = row["loginUrl"]
        loginUi = row["loginUi"]
        loginCheckJs = row["loginCheckJs"]
        coverDecodeJs = row["coverDecodeJs"]
        sortUrl = row["sortUrl"]
        singleUrl = row["singleUrl"]
        articleStyle = row["articleStyle"]
        ruleArticles = row["ruleArticles"]
        ruleNextPage = row["ruleNextPage"]
        ruleTitle = row["ruleTitle"]
        rulePubDate = row["rulePubDate"]
        ruleDescription = row["ruleDescription"]
        ruleImage = row["ruleImage"]
        ruleLink = row["ruleLink"]
        ruleContent = row["ruleContent"]
        nextContentUrl = row["nextContentUrl"]
        contentWhitelist = row["contentWhitelist"]
        contentBlacklist = row["contentBlacklist"]
        shouldOverrideUrlLoading = row["shouldOverrideUrlLoading"]
        style = row["style"]
        enableJs = row["enableJs"]
        loadWithBaseUrl = row["loadWithBaseUrl"]
        injectJs = row["injectJs"]
        preloadJs = row["preloadJs"]
        startHtml = row["startHtml"]
        startStyle = row["startStyle"]
        startJs = row["startJs"]
        showWebLog = row["showWebLog"]
        lastUpdateTime = row["lastUpdateTime"]
        customOrder = row["customOrder"]
        type = row["type"]
        preload = row["preload"]
        cacheFirst = row["cacheFirst"]
        searchUrl = row["searchUrl"]
    }
}

public struct RssColumn: Equatable, Sendable, Identifiable {
    public let name: String
    public let url: String
    public var id: String { name + "::" + url }
}

public extension RssSource {
    var columns: [RssColumn] {
        (try? resolveColumns(engine: JsEngine(baseUrl: sourceUrl))) ?? [RssColumn(name: "", url: sourceUrl)]
    }

    func resolveColumns(engine: JsEngine) throws -> [RssColumn] {
        var text = sortUrl ?? ""
        do {
            if text.hasPrefix("@js:") {
                text = ruleText(try engine.evaluateScript(String(text.dropFirst(4))))
            } else if text.hasPrefix("<js>") {
                if let end = text.range(of: "</js>", options: .backwards) {
                    text = ruleText(try engine.evaluateScript(String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound])))
                } else { text = "" }
            }
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            text = ""
        }
        let values = text.replacingOccurrences(of: "&&", with: "\n").components(separatedBy: .newlines).compactMap { line -> RssColumn? in
            guard let separator = line.range(of: "::") else { return nil }
            let name = line[..<separator.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let url = line[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            let hasRule = url.contains("{{") || url.contains(",{") || url.contains("<") || url.hasPrefix("@js:")
            return RssColumn(name: name, url: hasRule ? url : RssParser.absolute(url, base: sourceUrl))
        }
        return values.isEmpty ? [RssColumn(name: "", url: sourceUrl)] : values
    }
    var groups: [String] {
        (sourceGroup ?? "").components(separatedBy: CharacterSet(charactersIn: ",;，；\n")).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }
}
