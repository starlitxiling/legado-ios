import XCTest
import LegadoCore
@testable import SettingsBackupCheck

final class AppPreferencesTests: XCTestCase {
    @MainActor
    func testThemeApplicationPreservesModeWhenEffectiveAppearanceMatches() throws {
        let suite = "B13b.themeMode.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        for (mode, systemNight, targetNight, expected) in [
            ("0", false, false, "0"), ("0", true, true, "0"),
            ("3", true, false, "3"), ("1", true, false, "1"),
            ("2", false, true, "2"), ("0", true, false, "1"), ("3", false, true, "2")
        ] {
            preferences.set("themeMode", .string(mode))
            let theme = preferences.currentTheme(name: "测试", night: targetNight)
            try preferences.applyTheme(theme, systemIsNight: systemNight)
            XCTAssertEqual(preferences.string("themeMode"), expected, "\(mode),\(systemNight),\(targetNight)")
        }
    }

    @MainActor
    func testMissingRestoreKeysResetAndRespectIgnoredGroups() throws {
        let suite = "B13b.restoreMissing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        for ignored in [false, true] {
            preferences.backupSelection = BackupSelection(values: ["coverConfig": ignored, "readConfig": ignored])
            for key in ["coverFont", "readRecordCover", "readRecordCoverDark"] { preferences.set(key, .string("old")) }
            preferences.set("coverTitleAdaptive", .boolean(false))
            preferences.set("coverCustomFontSize", .boolean(true))
            preferences.set("mangaRightToLeft", .boolean(true))
            preferences.apply([:])
            for key in ["coverFont", "readRecordCover", "readRecordCoverDark"] {
                XCTAssertEqual(preferences.string(key), ignored ? "old" : "", key)
                if !ignored { XCTAssertNil(defaults.object(forKey: key), key) }
            }
            XCTAssertEqual(preferences.boolean("coverTitleAdaptive"), !ignored)
            XCTAssertEqual(preferences.boolean("coverCustomFontSize"), ignored)
            XCTAssertEqual(preferences.boolean("mangaRightToLeft"), ignored)
            preferences.apply(["coverTitleAdaptive": .boolean(false), "coverFont": .string("IncomingFont")])
            XCTAssertEqual(preferences.string("coverFont"), ignored ? "old" : "IncomingFont")
        }
    }
    @MainActor
    func testAndroidDefaultsAndXMLRoundTrip() throws {
        let suite = "B13b.defaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let expectedTrue = "coverShowName coverShowAuthor coverShowNameN coverShowAuthorN coverTitleAdaptive welcomeShowText welcomeShowIcon welcomeShowTextDark welcomeShowIconDark showDiscovery showRss replaceEnableDefault autoClearExpired showAddToShelfAlert showMangaUi jsSourceApiTokenRequired autoCheckNewBackup"
        let expectedFalse = "coverHorizontal coverKeepPunctuation coverCustomFontSize customWelcome auto_refresh onlyUpdateRead defaultToRead showDiscoveryFastScroller antiAlias readAloudByMediaButton ignoreAudioFocus recordLog recordHttpLog webDavBookAutoRestore syncBookProgressPlus"
        for key in expectedTrue.split(separator: " ") { XCTAssertEqual(preferences.snapshot[String(key)], .boolean(true), String(key)) }
        for key in expectedFalse.split(separator: " ") { XCTAssertEqual(preferences.snapshot[String(key)], .boolean(false), String(key)) }
        let integers: [String: Int32] = ["fontScale": 0, "backgroundImageBlurring": 0, "backgroundImageNightBlurring": 0,
            "coverTitleLargeSize": 100, "coverTitleSmallSize": 100, "coverAuthorLargeSize": 100, "coverAuthorSmallSize": 100,
            "welcomeShowTime": 500, "bitmapCacheSize": 50, "imageRetainNum": 0, "sourceEditMaxLine": .max]
        for (key, value) in integers { XCTAssertEqual(preferences.snapshot[key], .int(value), key) }
        for key in "backgroundImage backgroundImageNight welcomeImagePath welcomeImagePathDark coverFont userAgent customHosts jsSourceApiToken backupUri localPassword".split(separator: " ") {
            XCTAssertEqual(preferences.snapshot[String(key)], .string(""), String(key))
        }
        XCTAssertEqual(preferences.string("defaultHomePage"), "bookshelf")
        XCTAssertEqual(try AndroidPreferencesXML.decode(AndroidPreferencesXML.encode(preferences.snapshot)), preferences.snapshot)
        preferences.set("coverTitleLargeSize", .int(125))
        XCTAssertEqual(defaults.integer(forKey: "coverTitleLargeSize"), 125)
        XCTAssertEqual(BackupPreferences(defaults: defaults).integer("coverTitleLargeSize"), 125)
    }

    @MainActor
    func testCoverTextAndThemeSaveApply() throws {
        let suite = "B13b.theme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.coverText(title: "书：名！", author: "作者", night: false).title, "书名")
        preferences.set("coverShowNameN", .boolean(false))
        XCTAssertNil(preferences.coverText(title: "书", author: "作者", night: true).title)
        preferences.set("coverKeepPunctuation", .boolean(true))
        XCTAssertEqual(preferences.coverText(title: "书！", author: "作者", night: false).title, "书！")
        preferences.set("colorAccentNight", .int(-123))
        preferences.saveTheme(name: "测试", night: true)
        preferences.set("colorAccentNight", .int(0))
        try preferences.applyTheme(XCTUnwrap(preferences.themes.first { $0.themeName == "测试" }))
        XCTAssertEqual(preferences.integer("colorAccentNight"), -123)
        XCTAssertEqual(preferences.string("themeMode"), "2")
        XCTAssertEqual(AppPreferences(defaults: defaults).themes.count, 5)
    }

    @MainActor
    func testAllDefaultsAreCoveredAndPersistWithoutTypeLoss() throws {
        let suite = "B13b.all.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        var expected: [String: AndroidPreferenceValue] = [:]
        for key in "coverShowName coverShowAuthor coverShowNameN coverShowAuthorN coverTitleAdaptive welcomeShowText welcomeShowIcon welcomeShowTextDark welcomeShowIconDark showDiscovery showRss replaceEnableDefault autoClearExpired showAddToShelfAlert showMangaUi jsSourceApiTokenRequired autoCheckNewBackup autoBackup autoBackupWebDav syncBookProgress onlyLatestBackup".split(separator: " ") { expected[String(key)] = .boolean(true) }
        for key in "coverHorizontal coverKeepPunctuation coverCustomFontSize customWelcome useDefaultCover auto_refresh onlyUpdateRead defaultToRead showDiscoveryFastScroller antiAlias readAloudByMediaButton ignoreAudioFocus recordLog recordHttpLog webDavBookAutoRestore syncBookProgressPlus loadCoverOnlyWifi".split(separator: " ") { expected[String(key)] = .boolean(false) }
        for key in "backgroundImage backgroundImageNight welcomeImagePath welcomeImagePathDark coverFont userAgent customHosts jsSourceApiToken backupUri localPassword defaultCover defaultCoverDark readRecordCover readRecordCoverDark durThemeName durThemeNameNight".split(separator: " ") { expected[String(key)] = .string("") }
        for (key, value) in ["themeMode": "0", "language": "auto", "webDavDir": "legado", "defaultHomePage": "bookshelf", "launcherIcon": "ic_launcher"] { expected[key] = .string(value) }
        for (key, value): (String, Int32) in ["fontScale": 0, "backgroundImageBlurring": 0, "backgroundImageNightBlurring": 0,
            "coverTitleLargeSize": 100, "coverTitleSmallSize": 100, "coverAuthorLargeSize": 100, "coverAuthorSmallSize": 100,
            "welcomeShowTime": 500, "bitmapCacheSize": 50, "imageRetainNum": 0, "sourceEditMaxLine": .max,
            "preDownloadNum": 2, "threadCount": 32, "bookshelfSort": 0, "autoBackupIntervalDays": 1] { expected[key] = .int(value) }
        for (key, color): (String, UInt32) in ["colorPrimary": 0xff795548, "colorAccent": 0xffe53935,
            "colorBackground": 0xfff5f5f5, "colorBottomBackground": 0xffeeeeee, "colorPrimaryNight": 0xff546e7a,
            "colorAccentNight": 0xffd84315, "colorBackgroundNight": 0xff212121, "colorBottomBackgroundNight": 0xff303030] {
            expected[key] = .int(Int32(bitPattern: color))
        }
        XCTAssertEqual(preferences.snapshot, expected)
        for (key, value) in expected { preferences.set(key, value) }
        XCTAssertEqual(AppPreferences(defaults: defaults).snapshot, expected)
        XCTAssertEqual(try AndroidPreferencesXML.decode(AndroidPreferencesXML.encode(expected)), expected)
        XCTAssertEqual(BackupSelection.contentKeys.count, 12)
        XCTAssertEqual(BackupSelection.ignoreKeys.count, 10)
    }

    @MainActor
    func testDirectDefaultsChangesAndRestoreDoNotDrift() throws {
        let suite = "B13b.reload.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.set("themeMode", .string("1"))
        defaults.set("2", forKey: "themeMode")
        preferences.reload()
        XCTAssertEqual(preferences.string("themeMode"), "2")
        preferences.apply(["colorPrimary": .string("invalid"), "coverHorizontal": .boolean(true)])
        XCTAssertEqual(preferences.integer("colorPrimary"), Int(Int32(bitPattern: 0xff795548)))
        XCTAssertTrue(preferences.boolean("coverHorizontal"))
        try preferences.restoreThemes(Data("[{\"themeName\":\"Android\",\"primaryColor\":\"#000000\",\"accentColor\":\"#FFFFFF\",\"backgroundColor\":\"#FFFFFF\",\"bottomBackground\":\"#EEEEEE\"}]".utf8))
        XCTAssertEqual(preferences.themes.last?.themeName, "Android")
        preferences.set("defaultHomePage", .string("rss")); preferences.set("showRss", .boolean(false))
        XCTAssertEqual(preferences.initialHomePage, "bookshelf")
    }

    @MainActor
    func testUploadRuleValidationAndBackupSelection() async throws {
        let database = try AppDatabase.inMemory()
        let model = UploadRuleSettingsModel(database: database)
        model.text = "{\"uploadUrl\":\"https://example.invalid/upload\",\"downloadUrlRule\":\"$.url\",\"summary\":\"测试\",\"future\":12}"
        await model.save()
        let reader = UploadRuleSettingsModel(database: database)
        await reader.load()
        XCTAssertEqual(reader.text, model.text)
        model.text = "[]"
        await model.save()
        await reader.load()
        XCTAssertNotEqual(reader.text, "[]")
        let data = try await BackupExporter(database: database).export(selection: BackupSelection(values: ["backupRules": true]))
        XCTAssertNil(try BackupArchive(data: data).files["directLinkUploadRule.json"])
    }
}
