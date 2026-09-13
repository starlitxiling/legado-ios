import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class BackupViewModel {
    static let restoredNotification = Notification.Name("Legado.backupRestored")
    static let maximumBytes = 256 * 1024 * 1024
    private(set) var files: [WebDavFile] = []
    private(set) var isBusy = false
    private(set) var report: BackupImportReport?
    var errorMessage: String?
    private var source: WebDavBackupSource?
    private let importer: BackupImporter
    private let didRestore: () -> Void

    init(database: AppDatabase, localDeviceID: String, didRestore: @escaping () -> Void = {}) {
        importer = BackupImporter(database: database, localDeviceID: localDeviceID)
        self.didRestore = didRestore
    }

    func configure(credentials: WebDavCredentials, httpClient: any HttpClient) throws {
        guard !isBusy else { return }
        let client = WebDavClient(baseURL: credentials.baseURL, username: credentials.username,
                                  password: credentials.password, httpClient: httpClient)
        _ = try client.url(path: "")
        source = WebDavBackupSource(client: client, maximumDownloadSize: Self.maximumBytes)
        files = []
    }

    func listBackups() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        files = []
        defer { isBusy = false }
        do {
            guard let source else { throw WebDavError.invalidURL }
            files = try await source.listBackups()
        } catch { errorMessage = error.localizedDescription }
    }

    func restore(_ file: WebDavFile) async {
        guard !isBusy else { return }
        await performRestore {
            guard let source = self.source else { throw WebDavError.invalidURL }
            return try await source.download(file)
        }
    }

    func restoreLocalData(_ data: Data) async {
        await performRestore { data }
    }

    func restoreLocalFile(_ url: URL) async {
        let maximumBytes = Self.maximumBytes
        await performRestore {
            try await Task.detached {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
                guard data.count <= maximumBytes else { throw WebDavError.responseTooLarge }
                return data
            }.value
        }
    }

    private func performRestore(_ load: () async throws -> Data) async {
        guard !isBusy else { return }
        isBusy = true
        report = nil
        errorMessage = nil
        defer {
            isBusy = false
            // 部分表可能已提交，包括取消或后续表失败的情形。
            NotificationCenter.default.post(name: Self.restoredNotification, object: nil)
            didRestore()
        }
        do {
            let data = try await load()
            try Task.checkCancellation()
            guard data.count <= Self.maximumBytes else { throw WebDavError.responseTooLarge }
            report = try await importer.importArchive(data)
        } catch { errorMessage = error.localizedDescription }
    }
}
