import Foundation

public struct WebDavBackupUploader: Sendable {
    private let client: WebDavClient
    private let directory: String

    public init(client: WebDavClient, directory: String = "legado") {
        self.client = client; self.directory = directory
    }

    public func upload(_ data: Data, fileName: String) async throws {
        guard fileName == BackupExporter.normalizeFileName(fileName), fileName.hasPrefix("backup"), fileName.hasSuffix(".zip") else {
            throw WebDavError.invalidURL
        }
        let root = directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        try await client.ensureCollection(client.url(path: root + "/"))
        try Task.checkCancellation()
        try await client.put(data, to: client.url(path: root + "/" + fileName))
    }
}
