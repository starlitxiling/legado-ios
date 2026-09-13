import Foundation

public struct WebDavBackupSource: Sendable {
    private let client: WebDavClient
    private let directory: String
    private let maximumDownloadSize: Int

    public init(client: WebDavClient, directory: String = "legado", maximumDownloadSize: Int = 256 * 1024 * 1024) {
        self.client = client
        self.directory = directory
        self.maximumDownloadSize = maximumDownloadSize
    }

    public func listBackups() async throws -> [WebDavFile] {
        let url = try client.url(path: directory.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/")
        return try await client.propfind(url).filter {
            !$0.isDirectory && $0.displayName.hasSuffix(".zip") &&
                ($0.displayName.hasPrefix("backup") || $0.displayName.hasPrefix("legado"))
        }.sorted {
            let first = Self.backupDate($0.displayName) ?? $0.lastModified ?? .distantPast
            let second = Self.backupDate($1.displayName) ?? $1.lastModified ?? .distantPast
            if first != second { return first > second }
            return $0.displayName.compare($1.displayName, options: .numeric, locale: Locale(identifier: "en_US_POSIX")) == .orderedDescending
        }
    }

    public func download(_ file: WebDavFile) async throws -> Data {
        guard maximumDownloadSize >= 0, file.size <= maximumDownloadSize else { throw WebDavError.responseTooLarge }
        return try await client.get(file.url, maximumResponseBytes: maximumDownloadSize)
    }

    /// 返回独占的临时文件，由调用方在使用完后清理。
    public func downloadToTemporaryFile(_ file: WebDavFile) async throws -> URL {
        let data = try await download(file)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legado-backup-\(UUID().uuidString).zip")
        try data.write(to: url, options: [.atomic])
        return url
    }

    public func restore(_ file: WebDavFile, importer: BackupImporter) async throws -> BackupImportReport {
        try await importer.importArchive(download(file))
    }

    private static func backupDate(_ name: String) -> Date? {
        let prefix = name.hasPrefix("backup") ? "backup" : "legado"
        let text = String(name.dropFirst(prefix.count).dropLast(4))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["yyyy-MM-dd-HH-mm-ss", "yyyy-MM-dd", "yyyyMMddHHmmss", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        // Kotlin backupyyyy-MM-dd-deviceName.zip 中设备名不参与时间比较。
        if text.count > 10, text.dropFirst(10).hasPrefix("-") {
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: String(text.prefix(10)))
        }
        return nil
    }
}
