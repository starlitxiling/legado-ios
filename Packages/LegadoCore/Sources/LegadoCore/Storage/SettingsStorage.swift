import Foundation
import GRDB

public extension AppDatabase {
    func vacuum() async throws {
        try await writer.vacuum()
    }

    func backupConfiguration(named name: String) async throws -> Data? {
        guard BackupFileManifest.configurationFiles.contains(name) else { throw BackupArchiveError.unsupportedFormat }
        return try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM backup_files WHERE name = ?", arguments: [name])
        }
    }
}
