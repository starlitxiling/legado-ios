import Foundation
import LegadoCore
import GRDB

@main
struct BackupImportCheck {
    static func main() async {
        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.first == "--" { arguments.removeFirst() }
            let password = ProcessInfo.processInfo.environment["LEGADO_BACKUP_PASSWORD"]
            let missingPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            var selection = BackupSelection(values: ["ignoreCookies": missingPassword, "ignoreSourceVariables": missingPassword])
            for (flag, key) in [("--ignore-cookies", "ignoreCookies"), ("--ignore-source-variables", "ignoreSourceVariables")] {
                if arguments.contains(flag) { selection.values[key] = true; arguments.removeAll { $0 == flag } }
            }
            guard arguments.count == 1, !arguments[0].hasPrefix("--") else {
                FileHandle.standardError.write(Data("Usage: BackupImportCheck [--ignore-cookies] [--ignore-source-variables] <local-backup.zip>\nOptional environment: LEGADO_BACKUP_PASSWORD\n".utf8))
                exit(2)
            }
            let database = try AppDatabase.inMemory()
            let archive = try BackupArchive(data: Data(contentsOf: URL(fileURLWithPath: arguments[0])))
            let importer = BackupImporter(database: database, localDeviceID: "backup-import-check", password: password)
            let report = try await importer.importArchive(archive, selection: selection)
            for name in report.importedCounts.keys.sorted() {
                print("Imported \(name): \(report.importedCounts[name]!)")
            }
            let counts = try await database.write { db in
                let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
                return try tables.map { name in
                    let identifier = name.replacingOccurrences(of: "\"", with: "\"\"")
                    return (name, try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(identifier)\"") ?? 0)
                }
            }
            let baseline = ["books", "book_sources", "replace_rules", "readRecord", "bookmarks", "book_groups"]
            for (name, count) in counts where !baseline.contains(name) { print("Table \(name): \(count)") }
            for name in baseline {
                if let count = counts.first(where: { $0.0 == name })?.1 { print("Table \(name): \(count)") }
            }
            for (name, key) in [("cookies.json", "ignoreCookies"), ("runtimeSourceCache.json", "ignoreSourceVariables")] where archive.files[name] == nil && selection.values[key] == true {
                print("Policy \(name): \(missingPassword ? "no password provided; " : "")\(key)=true; entry absent")
            }
            print("Servers imported: \(report.importedCounts["servers.json"].map(String.init) ?? "absent")")
            print("Skipped files: \(report.skippedFiles.count)")
            for name in report.skippedFiles.sorted() {
                if let key = ["cookies.json": "ignoreCookies", "runtimeSourceCache.json": "ignoreSourceVariables"][name] {
                    print("Skipped \(name): \(missingPassword ? "no password provided; " : "")\(key)=true")
                } else {
                    print("Skipped \(name): \(report.skippedReasons[name] ?? "unsupported or excluded entry")")
                }
            }
            print("Failed files: \(report.failures.count)")
            for name in report.failures.keys.sorted() { print("Failed \(name): \(report.failures[name]!)") }
            print("Result: \(report.failures.isEmpty ? "OK" : "FAILED")")
            if !report.failures.isEmpty { exit(1) }
        } catch {
            FileHandle.standardError.write(Data("Backup import failed: \(String(describing: error))\n".utf8))
            exit(1)
        }
    }
}
