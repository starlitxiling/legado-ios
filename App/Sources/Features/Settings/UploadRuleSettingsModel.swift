import Foundation
import Observation
import GRDB
import LegadoCore

@Observable @MainActor
final class UploadRuleSettingsModel {
    var text = ""
    var address = ""
    var message: String?
    private let database: AppDatabase
    init(database: AppDatabase) { self.database = database }

    func load() async {
        do {
            let data = try await database.backupConfiguration(named: "directLinkUploadRule.json")
            text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        } catch { message = error.localizedDescription }
    }

    func save() async {
        do {
            let data = Data(text.utf8)
            guard data.count <= 16 * 1024 * 1024,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uploadURL = object["uploadUrl"] as? String, !uploadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  object["downloadUrlRule"] is String, object["summary"] is String else { throw BackupArchiveError.unsupportedFormat }
            try await database.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO backup_files (name, data) VALUES ('directLinkUploadRule.json', ?)", arguments: [data])
            }
            message = "上传规则已保存"
        } catch { message = error.localizedDescription }
    }
}
