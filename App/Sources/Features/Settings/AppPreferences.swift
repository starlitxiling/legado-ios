import Foundation
import LegadoCore

extension AppPreferences {
    static let shared = AppPreferences()

    static let settingDefaults: [String: AndroidPreferenceValue] = {
        var values = AndroidBackupPreferences.defaults
        values["launcherIcon"] = .string("ic_launcher")
        for key in "coverShowName coverShowAuthor coverShowNameN coverShowAuthorN coverTitleAdaptive welcomeShowText welcomeShowIcon welcomeShowTextDark welcomeShowIconDark replaceEnableDefault autoClearExpired showAddToShelfAlert showMangaUi jsSourceApiTokenRequired".split(separator: " ") {
            values[String(key)] = .boolean(true)
        }
        for key in "coverHorizontal coverKeepPunctuation coverCustomFontSize customWelcome useDefaultCover showDiscoveryFastScroller antiAlias readAloudByMediaButton ignoreAudioFocus recordLog recordHttpLog webDavBookAutoRestore".split(separator: " ") {
            values[String(key)] = .boolean(false)
        }
        for key in "backgroundImage backgroundImageNight welcomeImagePath welcomeImagePathDark coverFont userAgent customHosts jsSourceApiToken backupUri localPassword defaultCover defaultCoverDark readRecordCover readRecordCoverDark durThemeName durThemeNameNight".split(separator: " ") {
            values[String(key)] = .string("")
        }
        let numbers: [String: Int32] = ["fontScale": 0, "backgroundImageBlurring": 0, "backgroundImageNightBlurring": 0,
            "coverTitleLargeSize": 100, "coverTitleSmallSize": 100, "coverAuthorLargeSize": 100, "coverAuthorSmallSize": 100,
            "welcomeShowTime": 500, "bitmapCacheSize": 50, "imageRetainNum": 0, "sourceEditMaxLine": .max]
        for (key, value) in numbers { values[key] = .int(value) }
        for (key, value): (String, UInt32) in ["colorPrimary": 0xFF795548, "colorAccent": 0xFFE53935,
            "colorBackground": 0xFFF5F5F5, "colorBottomBackground": 0xFFEEEEEE,
            "colorPrimaryNight": 0xFF546E7A, "colorAccentNight": 0xFFD84315,
            "colorBackgroundNight": 0xFF212121, "colorBottomBackgroundNight": 0xFF303030] {
            values[key] = .int(Int32(bitPattern: value))
        }
        return values
    }()

    var backupSelection: BackupSelection {
        get {
            _ = configurationRevision
            guard let data = defaults.data(forKey: "Legado.restoreIgnore.json"),
                  let values = try? JSONDecoder().decode([String: Bool].self, from: data) else { return .init() }
            return BackupSelection(values: values)
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue.values), forKey: "Legado.restoreIgnore.json")
            configurationRevision += 1
        }
    }

    var themes: [AppThemeConfiguration] {
        _ = configurationRevision
        guard let data = defaults.data(forKey: "Legado.themeConfig.json"),
              let themes = try? JSONDecoder().decode([AppThemeConfiguration].self, from: data) else { return AppThemeConfiguration.builtins }
        return themes
    }

    func saveTheme(name: String, night: Bool) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var saved = themes
        let theme = currentTheme(name: name, night: night)
        if let index = saved.firstIndex(where: { $0.themeName == name }) { saved[index] = theme }
        else { saved.append(theme) }
        defaults.set(try? JSONEncoder().encode(saved), forKey: "Legado.themeConfig.json")
        configurationRevision += 1
    }

    func restoreThemes(_ data: Data) throws {
        let incoming = try JSONDecoder().decode([AppThemeConfiguration].self, from: data)
        var merged = themes
        for theme in incoming {
            guard [theme.primaryColor, theme.accentColor, theme.backgroundColor, theme.bottomBackground].allSatisfy({ AppThemeConfiguration.color($0) != nil }) else { throw AppThemeConfiguration.InvalidColor() }
            if let index = merged.firstIndex(where: { $0.themeName == theme.themeName }) { merged[index] = theme }
            else { merged.append(theme) }
        }
        defaults.set(try JSONEncoder().encode(merged), forKey: "Legado.themeConfig.json")
        configurationRevision += 1
    }

    func backupDirectory() throws -> URL? {
        guard let data = defaults.data(forKey: "Legado.backupBookmark") else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { defaults.set(try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "Legado.backupBookmark") }
        return url
    }

    func currentTheme(name: String, night: Bool) -> AppThemeConfiguration {
        let suffix = night ? "Night" : ""
        func color(_ key: String) -> String { String(format: "#%08X", UInt32(truncatingIfNeeded: integer(key + suffix))) }
        return AppThemeConfiguration(themeName: name, isNightTheme: night, primaryColor: color("colorPrimary"),
            accentColor: color("colorAccent"), backgroundColor: color("colorBackground"), bottomBackground: color("colorBottomBackground"),
            backgroundImgPath: string("backgroundImage" + suffix), backgroundImgBlur: integer("backgroundImage" + suffix + "Blurring"))
    }

    func applyTheme(_ theme: AppThemeConfiguration, systemIsNight: Bool = false) throws {
        let pairs = [("colorPrimary", theme.primaryColor), ("colorAccent", theme.accentColor),
                     ("colorBackground", theme.backgroundColor), ("colorBottomBackground", theme.bottomBackground)]
        let colors = try pairs.map { pair -> (String, Int32) in
            guard let color = AppThemeConfiguration.color(pair.1) else { throw AppThemeConfiguration.InvalidColor() }
            return (pair.0, color)
        }
        let suffix = theme.isNightTheme ? "Night" : ""
        for (key, color) in colors { set(key + suffix, .int(color)) }
        set("backgroundImage" + suffix, .string(theme.backgroundImgPath ?? ""))
        set("backgroundImage" + suffix + "Blurring", .int(Int32(clamping: theme.backgroundImgBlur)))
        set("durThemeName" + suffix, .string(theme.themeName))
        let currentIsNight: Bool
        switch string("themeMode") {
        case "1", "3": currentIsNight = false
        case "2": currentIsNight = true
        default: currentIsNight = systemIsNight
        }
        if currentIsNight != theme.isNightTheme {
            set("themeMode", .string(theme.isNightTheme ? "2" : "1"))
        }
    }

    func coverText(title: String, author: String, night: Bool) -> CoverText {
        let suffix = night ? "N" : ""
        let text = boolean("coverKeepPunctuation") ? title : title.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) }.map(String.init).joined()
        return CoverText(title: boolean("coverShowName" + suffix) ? text : nil,
                         author: boolean("coverShowAuthor" + suffix) ? author : nil)
    }

    var initialHomePage: String {
        let page = string("defaultHomePage")
        if page == "my" { return "my" }
        if page == "explore", boolean("showDiscovery") { return "explore" }
        if page == "rss", boolean("showRss") { return "rss" }
        return "bookshelf"
    }
}

struct CoverText: Equatable {
    let title: String?
    let author: String?
}

struct AppThemeConfiguration: Codable, Equatable {
    var themeName: String
    var isNightTheme: Bool
    var primaryColor: String
    var accentColor: String
    var backgroundColor: String
    var bottomBackground: String
    var transparentNavBar = false
    var backgroundImgPath: String? = nil
    var backgroundImgBlur = 0

    private enum CodingKeys: String, CodingKey {
        case themeName, isNightTheme, primaryColor, accentColor, backgroundColor, bottomBackground, transparentNavBar, backgroundImgPath, backgroundImgBlur
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeName = try container.decode(String.self, forKey: .themeName)
        isNightTheme = try container.decodeIfPresent(Bool.self, forKey: .isNightTheme) ?? false
        primaryColor = try container.decode(String.self, forKey: .primaryColor)
        accentColor = try container.decode(String.self, forKey: .accentColor)
        backgroundColor = try container.decode(String.self, forKey: .backgroundColor)
        bottomBackground = try container.decode(String.self, forKey: .bottomBackground)
        transparentNavBar = try container.decodeIfPresent(Bool.self, forKey: .transparentNavBar) ?? false
        backgroundImgPath = try container.decodeIfPresent(String.self, forKey: .backgroundImgPath)
        backgroundImgBlur = try container.decodeIfPresent(Int.self, forKey: .backgroundImgBlur) ?? 0
    }

    init(themeName: String, isNightTheme: Bool, primaryColor: String, accentColor: String, backgroundColor: String,
         bottomBackground: String, backgroundImgPath: String? = nil, backgroundImgBlur: Int = 0) {
        self.themeName = themeName; self.isNightTheme = isNightTheme; self.primaryColor = primaryColor
        self.accentColor = accentColor; self.backgroundColor = backgroundColor; self.bottomBackground = bottomBackground
        self.backgroundImgPath = backgroundImgPath; self.backgroundImgBlur = backgroundImgBlur
    }

    struct InvalidColor: Error {}
    static func color(_ value: String) -> Int32? {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard [6, 8].contains(hex.count), let number = UInt32(hex, radix: 16) else { return nil }
        return Int32(bitPattern: hex.count == 6 ? number | 0xFF000000 : number)
    }

    static let builtins = [
        AppThemeConfiguration(themeName: "默认", isNightTheme: false, primaryColor: "#795548", accentColor: "#E53935", backgroundColor: "#F5F5F5", bottomBackground: "#EEEEEE"),
        AppThemeConfiguration(themeName: "典雅蓝", isNightTheme: false, primaryColor: "#03A9F4", accentColor: "#AD1457", backgroundColor: "#F5F5F5", bottomBackground: "#EEEEEE"),
        AppThemeConfiguration(themeName: "黑白", isNightTheme: true, primaryColor: "#303030", accentColor: "#E0E0E0", backgroundColor: "#424242", bottomBackground: "#424242"),
        AppThemeConfiguration(themeName: "A屏黑", isNightTheme: true, primaryColor: "#000000", accentColor: "#FFFFFF", backgroundColor: "#000000", bottomBackground: "#000000")
    ]
}
