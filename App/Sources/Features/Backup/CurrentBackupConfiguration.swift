import Foundation

@MainActor
enum CurrentBackupConfiguration {
    static func files(defaults: UserDefaults, preferences: BackupPreferences, retainedFiles: [String: Data] = [:]) throws -> [String: Data] {
        let settings = ReaderSettings.load(from: defaults)
        let read: [String: Any] = [
            "name": "iOS", "textSize": Int(settings.textSize), "titleSize": Int(settings.titleSize),
            "titleMode": settings.titleMode, "titleTopSpacing": Int(settings.titleTopSpacing),
            "titleBottomSpacing": Int(settings.titleBottomSpacing), "textFont": settings.textFont,
            "pageAnim": settings.pageAnim, "lineSpacingExtra": Int(settings.lineSpacingMultiplier * 10),
            "paragraphSpacing": Int(settings.paragraphSpacing), "paragraphIndent": settings.paragraphIndent,
            "paddingLeft": Int(settings.paddingLeft), "paddingRight": Int(settings.paddingRight),
            "paddingTop": Int(settings.paddingTop), "paddingBottom": Int(settings.paddingBottom)
        ]
        var styles = try retainedFiles["readConfig.json"].map { try JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? nil
        if styles?.isEmpty != false { styles = [[:]] }
        var currentStyles = styles ?? [[:]]
        let index = min(max(0, defaults.integer(forKey: "readStyleSelect")), currentStyles.count - 1)
        var current = currentStyles[index]
        for (key, value) in read where key != "name" || current[key] == nil { current[key] = value }
        for (suffix, fallback) in [("", "#EEEEEE"), ("Night", "#000000"), ("EInk", "#FFFFFF")] {
            let pathKey = "bgStr" + suffix, typeKey = "bgType" + suffix
            if let path = defaults.string(forKey: pathKey) {
                current[pathKey] = path
                current[typeKey] = (defaults.object(forKey: typeKey) as? NSNumber)?.intValue ?? (path.hasPrefix("#") ? 0 : 2)
            } else {
                if current[pathKey] == nil { current[pathKey] = fallback }
                if current[typeKey] == nil { current[typeKey] = 0 }
            }
        }
        currentStyles[index] = current
        let shared = try retainedFiles["shareReadConfig.json"].map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
        return [
            "readConfig.json": try JSONSerialization.data(withJSONObject: currentStyles, options: .sortedKeys),
            "shareReadConfig.json": try JSONSerialization.data(withJSONObject: shared ?? current, options: .sortedKeys),
            "themeConfig.json": try JSONEncoder().encode(preferences.themes)
        ]
    }
}
