import Foundation
import LegadoCore

enum ScriptHostConfiguration {
    static func reading(defaults: UserDefaults, retained: Data?) throws -> String {
        let encoder = JSONEncoder()
        guard var values = try JSONSerialization.jsonObject(with: encoder.encode(ReadBookConfig())) as? [String: Any] else {
            throw JsEngineError.exception("Default reading configuration must be an object")
        }
        if let retained {
            let current: [String: Any]?
            if defaults.bool(forKey: "shareLayout") {
                guard let shared = try JSONSerialization.jsonObject(with: retained) as? [String: Any] else {
                    throw JsEngineError.exception("shareReadConfig.json must contain an object")
                }
                current = shared
            } else {
                guard let styles = try JSONSerialization.jsonObject(with: retained) as? [[String: Any]] else {
                    throw JsEngineError.exception("readConfig.json must contain an array of objects")
                }
                let index = defaults.integer(forKey: "readStyleSelect")
                current = styles.indices.contains(index) ? styles[index] : nil
            }
            if let current { values.merge(current) { _, new in new } }
        }
        for key in Array(values.keys) {
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        for (key, value) in CurrentBackupConfiguration.readerOverrides(defaults: defaults)
            where defaults.object(forKey: key) != nil {
            values[key] = value
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: values, options: .sortedKeys), as: UTF8.self)
    }
}
