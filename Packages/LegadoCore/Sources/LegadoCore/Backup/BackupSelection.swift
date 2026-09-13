import Foundation

/// Android restoreIgnore.json 的值表示排除；三个默认不备份的内容需显式设为 false。
public struct BackupSelection: Equatable, Sendable {
    public var values: [String: Bool]
    public init(values: [String: Bool] = [:]) { self.values = values }

    public static let contentKeys = ["backupBookshelf", "backupAnnotations", "backupSources", "backupRules", "backupHistory", "backupReadRecordCovers", "backupSettings", "backupPersistedCovers", "backupOtherCovers", "backupBackgrounds", "backupCookies", "backupSourceVariables"]
    public static let ignoreKeys = ["readConfig", "themeMode", "themeConfig", "coverConfig", "bookshelfLayout", "showRss", "threadCount", "localBook", "ignoreCookies", "ignoreSourceVariables"]

    public func includes(_ key: String) -> Bool {
        if ["backupCookies", "backupSourceVariables", "backupReadRecordCovers"].contains(key) { return values[key] == false }
        return values[key] != true
    }

    public func includesFile(_ name: String) -> Bool {
        let groups: [String: [String]] = [
            "backupBookshelf": ["bookshelf.json", "bookGroup.json", "bookMemo.json"],
            "backupAnnotations": ["bookmark.json", "highlight.json", "highlightRule.json"],
            "backupSources": ["bookSource.json", "rssSources.json", "rssStar.json", "sourceSub.json"],
            "backupRules": ["replaceRule.json", "txtTocRule.json", "httpTTS.json", "keyboardAssists.json", "dictRule.json", "autoTask.json", "servers.json", "directLinkUploadRule.json", "coverRule.json"],
            "backupHistory": ["readRecord.json", "searchHistory.json"],
            "backupSettings": ["readConfig.json", "shareReadConfig.json", "themeConfig.json", "config.xml", "videoConfig.xml"],
            "backupCookies": ["cookies.json"], "backupSourceVariables": ["runtimeSourceCache.json"]
        ]
        if let group = groups.first(where: { $0.value.contains(name) }) { return includes(group.key) }
        if name.hasPrefix("readRecordCover") { return includes("backupReadRecordCovers") && includes("backupHistory") }
        if name.hasPrefix("covers/") { return includes(BackupResources.persisted(name) ? "backupPersistedCovers" : "backupOtherCovers") }
        if name.hasPrefix("background") || name.hasPrefix("bg/") { return includes("backupBackgrounds") }
        if name == "coverFont.ttf" { return includes("backupSettings") }
        return true
    }

    public func ignoresFile(_ name: String) -> Bool {
        switch name {
        case "cookies.json": return values["ignoreCookies"] == true
        case "runtimeSourceCache.json": return values["ignoreSourceVariables"] == true
        case "readConfig.json", "shareReadConfig.json": return values["readConfig"] == true
        case "themeConfig.json": return values["themeConfig"] == true
        default: return false
        }
    }

    public func allowsPreference(_ key: String) -> Bool {
        if AndroidBackupPreferences.ignoredKeys.contains(key) { return false }
        if ["themeMode", "bookshelfLayout", "showRss", "threadCount"].contains(key), values[key] == true { return false }
        if values["themeConfig"] == true, Self.themeKeys.contains(key) { return false }
        if values["coverConfig"] == true, Self.coverKeys.contains(key) { return false }
        if values["readConfig"] == true, Self.readKeys.contains(key) { return false }
        return true
    }

    private static let themeKeys: Set<String> = ["colorPrimary", "colorAccent", "colorBackground", "colorBottomBackground", "backgroundImage", "backgroundImageBlurring", "transparentNavBar", "colorPrimaryNight", "colorAccentNight", "colorBackgroundNight", "colorBottomBackgroundNight", "backgroundImageNight", "backgroundImageNightBlurring", "transparentNavBarNight"]
    private static let coverKeys: Set<String> = ["readRecordCover", "readRecordCoverDark", "useDefaultCover", "loadCoverOnlyWifi", "coverShowName", "coverShowAuthor", "coverShowNameN", "coverShowAuthorN", "coverHorizontal", "coverTitleAdaptive", "coverKeepPunctuation", "coverFont", "coverCustomFontSize", "coverTitleLargeSize", "coverTitleSmallSize", "coverAuthorLargeSize", "coverAuthorSmallSize"]
    private static let readKeys: Set<String> = ["readStyleSelect", "comicStyleSelect", "mangaRightToLeft", "showBookMemo", "shareLayout", "hideStatusBar", "hideNavigationBar", "autoReadSpeed", "readerMenuConfig", "showReadTitleChapterNameOnly", "clickActionTL", "clickActionTC", "clickActionTR", "clickActionML", "clickActionMC", "clickActionMR", "clickActionBL", "clickActionBC", "clickActionBR"]
}
