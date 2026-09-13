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
    private var uploader: WebDavBackupUploader?
    private var progressSync: BookProgressSync?
    private let database: AppDatabase
    private let exportDirectory: URL?
    private let resourceDirectory: URL?
    let preferences: BackupPreferences
    private(set) var exportedFile: URL?
    private(set) var statusMessage: String?
    var newBackupName: String?
    private let importer: BackupImporter
    private let didRestore: () -> Void
    private let operationMutex: BackupOperationMutex

    init(database: AppDatabase, localDeviceID: String, resourceDirectory: URL? = BackupResources.defaultDirectory, preferences: BackupPreferences? = nil, exportDirectory: URL? = nil, operationMutex: BackupOperationMutex = .shared, didRestore: @escaping () -> Void = {}) {
        self.database = database
        self.exportDirectory = exportDirectory
        self.resourceDirectory = resourceDirectory
        self.operationMutex = operationMutex
        self.preferences = preferences ?? BackupPreferences()
        importer = BackupImporter(database: database, localDeviceID: localDeviceID, resourceDirectory: resourceDirectory)
        self.didRestore = didRestore
    }

    func configure(credentials: WebDavCredentials, httpClient: any HttpClient) throws {
        guard !isBusy else { return }
        preferences.reload()
        let client = WebDavClient(baseURL: credentials.baseURL, username: credentials.username,
                                  password: credentials.password, httpClient: httpClient)
        _ = try client.url(path: "")
        let directory = preferences.string("webDavDir")
        source = WebDavBackupSource(client: client, directory: directory, maximumDownloadSize: Self.maximumBytes)
        uploader = WebDavBackupUploader(client: client, directory: directory)
        progressSync = BookProgressSync(client: client, directory: directory)
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

    func checkNewBackup() async {
        guard preferences.boolean("autoCheckNewBackup"), source != nil else { return }
        await listBackups()
        let lastKnown = max(preferences.lastBackup, Int64(preferences.defaults.double(forKey: "Legado.lastRestore")))
        newBackupName = files.filter { ($0.lastModified?.timeIntervalSince1970 ?? 0) * 1000 > Double(lastKnown) }
            .max { ($0.lastModified ?? .distantPast) < ($1.lastModified ?? .distantPast) }?.displayName
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

    func createBackup(upload: Bool, now: Date = Date()) async {
        await performBackup(upload: upload, now: now, automatic: false)
    }

    private func performBackup(upload: Bool, now: Date, automatic: Bool) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; statusMessage = nil
        defer { isBusy = false }
        do {
            try await operationMutex.withLock { @MainActor in
                self.preferences.reload()
                if automatic {
                    guard BackupExporter.shouldBackup(enabled: self.preferences.boolean("autoBackup"), now: Int64(now.timeIntervalSince1970 * 1000), lastBackup: self.preferences.lastBackup, intervalDays: self.preferences.integer("autoBackupIntervalDays")) else { return }
                }
                try await self.writeBackup(upload: automatic ? self.preferences.boolean("autoBackupWebDav") : upload, now: now)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func writeBackup(upload: Bool, now: Date) async throws {
        let exporter = BackupExporter(database: database, now: { now }, resourceDirectory: resourceDirectory)
        let name = exporter.fileName(deviceName: preferences.string("webDavDeviceName"))
        var retainedFiles: [String: Data] = [:]
        for file in ["readConfig.json", "shareReadConfig.json"] {
            retainedFiles[file] = try await database.backupConfiguration(named: file)
        }
        let data = try await exporter.export(preferences: preferences.currentPreferenceSnapshot(), videoPreferences: preferences.videoSnapshot,
            currentConfigurationFiles: preferences.currentConfigurationFiles(retainedFiles: retainedFiles), selection: preferences.backupSelection)
        let directory = try exportDirectory ?? preferences.backupDirectory() ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Backups", isDirectory: true)
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(preferences.boolean("onlyLatestBackup") ? "backup.zip" : name)
        try data.write(to: file, options: .atomic)
        exportedFile = file
        if upload {
            guard let uploader else { throw WebDavError.invalidURL }
            try await uploader.upload(data, fileName: name)
        }
        preferences.lastBackup = Int64(now.timeIntervalSince1970 * 1000)
        statusMessage = upload ? "备份已上传" : "本地备份已生成"
    }

    func automaticBackup(now: Date = Date()) async {
        await performBackup(upload: false, now: now, automatic: true)
    }

    func synchronizeProgress(now: Date = Date()) async {
        guard !isBusy, preferences.boolean("syncBookProgress"), let progressSync else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            let repository = BookshelfRepository(database: database)
            let books = try await repository.all()
            let restored = try await progressSync.downloadAll(books, now: Int64(now.timeIntervalSince1970 * 1000))
            var changed = false
            for (book, merged) in zip(books, restored) {
                try Task.checkCancellation()
                if merged.syncTime != book.syncTime {
                    try await BookProgressSync.save(merged, replacing: book, database: database)
                    changed = true
                }
            }
            statusMessage = "阅读进度已同步"
            if changed { NotificationCenter.default.post(name: Self.restoredNotification, object: nil) }
        } catch { errorMessage = error.localizedDescription }
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
            try await operationMutex.withLock { @MainActor in
                let data = try await load()
                try Task.checkCancellation()
                guard data.count <= Self.maximumBytes else { throw WebDavError.responseTooLarge }
                let archive = try BackupArchive(data: data)
                self.report = try await self.importer.importArchive(archive, selection: self.preferences.backupSelection)
                if self.report?.importedFiles.contains("themeConfig.json") == true, let themes = try await self.database.backupConfiguration(named: "themeConfig.json") {
                    do { try self.preferences.restoreThemes(themes) }
                    catch { self.errorMessage = "主题列表恢复失败：" + error.localizedDescription }
                }
                if let restoredPreferences = self.report?.preferences { self.preferences.apply(restoredPreferences) }
                if let videoPreferences = self.report?.videoPreferences { self.preferences.videoSnapshot = videoPreferences }
                if self.report?.failures.isEmpty == true { self.preferences.defaults.set(Date().timeIntervalSince1970 * 1000, forKey: "Legado.lastRestore") }
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
