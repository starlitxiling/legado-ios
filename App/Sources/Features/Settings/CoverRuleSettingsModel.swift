import Foundation
import Observation
import GRDB
import LegadoCore

@Observable @MainActor
final class CoverRuleSettingsModel {
    var text = ""
    var message: String?
    private let database: AppDatabase
    init(database: AppDatabase) { self.database = database }
    func load() async {
        do {
            text = try await database.backupConfiguration(named: "coverRule.json")
                .map { String(decoding: $0, as: UTF8.self) } ?? String(decoding: JSONEncoder().encode(CoverSearchRule.androidDefault), as: UTF8.self)
        } catch { message = error.localizedDescription }
    }
    func save() async {
        do {
            let data = Data(text.utf8)
            let rule = try JSONDecoder().decode(CoverSearchRule.self, from: data)
            guard !rule.searchUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !rule.coverRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupArchiveError.unsupportedFormat
            }
            try await database.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO backup_files (name, data) VALUES ('coverRule.json', ?)", arguments: [data])
            }
            message = "封面规则已保存"
        } catch { message = error.localizedDescription }
    }
}
