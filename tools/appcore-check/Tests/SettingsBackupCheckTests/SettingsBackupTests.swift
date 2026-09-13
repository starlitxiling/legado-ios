import XCTest
import LegadoCore
@testable import SettingsBackupCheck

@MainActor
final class SettingsBackupTests: XCTestCase {
    private func isolatedPreferences() -> BackupPreferences {
        let suite = "SettingsBackupTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return BackupPreferences(defaults: defaults)
    }
    func testCredentialsRoundTripAndDelete() throws {
        let store = MemoryKeychain()
        let model = SettingsViewModel(store: store, httpClient: ReplayHttpClient())
        model.address = "https://example.invalid/dav"
        model.username = "reader"
        model.password = "secret"
        model.save()
        let loaded = SettingsViewModel(store: store, httpClient: ReplayHttpClient())
        XCTAssertEqual(loaded.address, model.address)
        XCTAssertEqual(loaded.username, "reader")
        XCTAssertEqual(loaded.password, "secret")
        loaded.clearCredentials()
        XCTAssertTrue(store.values.isEmpty)
    }

    func testDeviceIdentityPersistsWhenCredentialsAreCleared() throws {
        let store = MemoryKeychain()
        let first = try SettingsViewModel.localDeviceID(store: store)
        XCTAssertFalse(first.isEmpty)
        let settings = SettingsViewModel(store: store, httpClient: ReplayHttpClient())
        settings.clearCredentials()
        XCTAssertEqual(try SettingsViewModel.localDeviceID(store: store), first)
    }

    func testSecondCredentialWriteFailureNeverLeavesMixedAccount() {
        assertCredentialUpdate(failingWrite: 2)
    }

    func testThirdCredentialWriteFailureNeverLeavesMixedAccount() {
        assertCredentialUpdate(failingWrite: 3)
    }

    func testFirstCredentialWriteFailurePreservesWholeAccount() {
        assertCredentialUpdate(failingWrite: 1)
    }

    private func assertCredentialUpdate(failingWrite: Int, file: StaticString = #filePath, line: UInt = #line) {
        let store = MemoryKeychain()
        let model = SettingsViewModel(store: store, httpClient: ReplayHttpClient())
        model.address = "https://old.invalid/dav"
        model.username = "old-reader"
        model.password = "old-secret"
        model.save()
        XCTAssertNil(model.errorMessage, file: file, line: line)
        store.writeCount = 0
        store.failingWrite = failingWrite
        model.address = "https://new.invalid/dav"
        model.username = "new-reader"
        model.password = "new-secret"
        model.save()
        let loaded = SettingsViewModel(store: store, httpClient: ReplayHttpClient())
        let expected = model.errorMessage == nil ? "new" : "old"
        XCTAssertEqual(loaded.address, "https://\(expected).invalid/dav", file: file, line: line)
        XCTAssertEqual(loaded.username, "\(expected)-reader", file: file, line: line)
        XCTAssertEqual(loaded.password, "\(expected)-secret", file: file, line: line)
        XCTAssertEqual(store.writeCount, 1, file: file, line: line)
        XCTAssertEqual(store.values.count, 1, file: file, line: line)
        if failingWrite == 1 {
            XCTAssertNotNil(model.errorMessage, file: file, line: line)
        } else {
            XCTAssertNil(model.errorMessage, file: file, line: line)
        }
    }

    func testInvalidAddressDoesNotSendRequest() async {
        let replay = ReplayHttpClient()
        let settings = SettingsViewModel(store: MemoryKeychain(), httpClient: replay)
        settings.address = "file:///tmp/backup"
        await settings.testConnection()
        XCTAssertNotNil(settings.errorMessage)
        let requests = await replay.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(settings.isTesting)
    }

    func testReadOnlyRemoteRestore() async throws {
        let replay = ReplayHttpClient()
        let root = URL(string: "https://example.invalid/dav/")!
        let directory = root.appendingPathComponent("legado/")
        let file = directory.appendingPathComponent("backup2024-01-02.zip")
        let xml = Data("""
        <d:multistatus xmlns:d="DAV:"><d:response><d:href>\(file.absoluteString)</d:href><d:propstat><d:prop><d:displayname>backup2024-01-02.zip</d:displayname><d:resourcetype/><d:getcontentlength>100</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>
        """.utf8)
        await replay.enqueue(url: root, method: "PROPFIND", response: .init(status: 207, body: Data("<d:multistatus xmlns:d=\"DAV:\"/>".utf8), finalURL: root))
        await replay.enqueue(url: directory, method: "PROPFIND", response: .init(status: 207, body: xml, finalURL: directory))
        await replay.enqueue(url: file, response: .init(status: 200, body: try fixture("backup2024-01-02.zip"), finalURL: file))
        let settings = SettingsViewModel(store: MemoryKeychain(), httpClient: replay)
        settings.address = root.absoluteString
        settings.username = "reader"
        settings.password = "secret"
        await settings.testConnection()
        XCTAssertNil(settings.errorMessage)
        let database = try AppDatabase.inMemory()
        var notifications = 0
        let model = BackupViewModel(database: database, localDeviceID: "test-device", resourceDirectory: nil, preferences: isolatedPreferences(), didRestore: { notifications += 1 })
        try model.configure(credentials: settings.credentials(), httpClient: replay)
        await model.listBackups()
        XCTAssertEqual(model.files.count, 1)
        await model.restore(try XCTUnwrap(model.files.first))
        XCTAssertNil(model.errorMessage)
        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(report.importedCounts.count, 8)
        XCTAssertEqual(report.importedCounts["rssSources.json"], 0)
        XCTAssertEqual(report.importedCounts["config.xml"], 0)
        XCTAssertEqual(Set(report.skippedFiles), ["unknown.txt"])
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(notifications, 1)
        let books = try await BookshelfRepository(database: database).list()
        XCTAssertEqual(books.count, 1)
        let requests = await replay.requests
        let connectionRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(connectionRequest.url, root)
        XCTAssertEqual(connectionRequest.headers["Depth"], "0")
        XCTAssertEqual(connectionRequest.headers["Authorization"], "Basic cmVhZGVyOnNlY3JldA==")
        XCTAssertEqual(requests.map(\.method), ["PROPFIND", "PROPFIND", "GET"])
    }

    func testLocalPartialFailureAndInvalidArchive() async throws {
        let model = BackupViewModel(database: try .inMemory(), localDeviceID: "test-device", resourceDirectory: nil, preferences: isolatedPreferences())
        await model.restoreLocalFile(fixtureURL("malformed-json.zip"))
        XCTAssertEqual(model.report?.importedCounts["bookmark.json"], 1)
        XCTAssertNotNil(model.report?.failures["bookshelf.json"])
        await model.restoreLocalData(Data("invalid".utf8))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.report)
        XCTAssertFalse(model.isBusy)
    }

    func testRestoreRejectsReentry() async throws {
        let client = SuspendedDownload(data: try fixture("backup2024-01-02.zip"))
        let model = BackupViewModel(database: try .inMemory(), localDeviceID: "test-device", resourceDirectory: nil, preferences: isolatedPreferences())
        let root = URL(string: "https://example.invalid/")!
        try model.configure(credentials: .init(baseURL: root, username: "", password: ""), httpClient: client)
        let file = WebDavFile(url: root.appendingPathComponent("backup.zip"), displayName: "backup.zip")
        let first = Task { await model.restore(file) }
        await client.waitUntilStarted()
        XCTAssertTrue(model.isBusy)
        await model.restoreLocalData(Data("invalid".utf8))
        XCTAssertNil(model.errorMessage)
        await client.finish()
        await first.value
        XCTAssertEqual(model.report?.importedCounts.count, 8)
        XCTAssertFalse(model.isBusy)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    private func fixtureURL(_ name: String) -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Tests/Conformance/fixtures/backup/\(name)")
    }
}

private actor SuspendedDownload: ResponseLimitedHttpClient {
    let data: Data
    private var started = false
    private var observer: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    init(data: Data) { self.data = data }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { observer = $0 }
    }
    func finish() { pending?.resume(); pending = nil }
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        await withCheckedContinuation { continuation in
            pending = continuation
            started = true
            observer?.resume()
            observer = nil
        }
        return HttpResponse(status: 200, body: data, finalURL: request.url)
    }
    func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        try await send(request)
    }
}

private final class MemoryKeychain: KeychainStoring {
    enum Failure: Error { case injected }
    var values: [String: String] = [:]
    var writeCount = 0
    var failingWrite: Int?
    func read(account: String) throws -> String? { values[account] }
    func write(_ value: String, account: String) throws {
        writeCount += 1
        if writeCount == failingWrite { throw Failure.injected }
        values[account] = value
    }
    func delete(account: String) throws { values[account] = nil }
}
