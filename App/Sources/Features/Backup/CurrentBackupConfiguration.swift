import Foundation
import LegadoCore

@MainActor
enum CurrentBackupConfiguration {
    static func files(defaults: UserDefaults, preferences: BackupPreferences, retainedFiles: [String: Data] = [:]) throws -> [String: Data] {
        let read = try readerOverrides(defaults: defaults)
        var styles = try retainedFiles["readConfig.json"].map { try JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? nil
        if styles?.isEmpty != false {
            styles = try JSONSerialization.jsonObject(with: ReadBookConfig.exportThemes(ReadBookConfig.bundledStyles())) as? [[String: Any]]
        }
        var currentStyles = styles ?? [[:]]
        let index = min(max(0, defaults.integer(forKey: "readStyleSelect")), currentStyles.count - 1)
        var current = currentStyles[index]
        let useShared = defaults.bool(forKey: "shareLayout")
        let visualKeys: Set<String> = ["name", "bgStr", "bgStrNight", "bgStrEInk", "bgType", "bgTypeNight", "bgTypeEInk",
            "textColor", "textColorNight", "textColorEInk", "textAccentColor", "textAccentColorNight", "textAccentColorEInk",
            "darkStatusIcon", "darkStatusIconNight", "darkStatusIconEInk"]
        for (key, value) in read where (!useShared || visualKeys.contains(key)) && (key != "name" || current[key] == nil) { current[key] = value }
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
        var shared = try retainedFiles["shareReadConfig.json"].map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
        if useShared {
            var updated = shared ?? current
            for (key, value) in read where !visualKeys.contains(key) { updated[key] = value }
            shared = updated
        }
        return [
            "readConfig.json": try JSONSerialization.data(withJSONObject: currentStyles, options: .sortedKeys),
            "shareReadConfig.json": try JSONSerialization.data(withJSONObject: shared ?? current, options: .sortedKeys),
            "themeConfig.json": try JSONEncoder().encode(preferences.themes)
        ]
    }

    nonisolated static func readerOverrides(defaults: UserDefaults) throws -> [String: Any] {
        let settings = ReaderSettings.load(from: defaults)
        let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings.configuration)) as! [String: Any]
        return fields.filter { defaults.object(forKey: $0.key) != nil }
    }
}
