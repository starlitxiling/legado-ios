import Foundation
import LegadoCore

@main
struct WebDavSmoke {
    static func main() async {
        var stage = "读取环境配置"
        do { try await run(stage: &stage) }
        catch {
            FileHandle.standardError.write(Data("只读冒烟失败（\(stage)）：\(safeErrorDescription(error))\n".utf8))
            exit(1)
        }
    }

    private static func safeErrorDescription(_ error: Error) -> String {
        if let error = error as? WebDavError {
            switch error {
            case .invalidURL: return "WebDavError.invalidURL"
            case .foreignOrigin: return "WebDavError.foreignOrigin"
            case .httpStatus(let status): return "WebDavError.httpStatus(\(status))"
            case .invalidXML: return "WebDavError.invalidXML"
            case .responseTooLarge: return "WebDavError.responseTooLarge（下载上限 256 MiB）"
            case .responseLimitUnavailable: return "WebDavError.responseLimitUnavailable（客户端缺少响应限流能力）"
            }
        }
        if let error = error as? URLError { return "URLError(code: \(error.code.rawValue))" }
        if let error = error as? SmokeError { return "SmokeError.\(error)" }
        // 任意第三方错误的 description 可能携带 URL、请求头或备份内容。
        return String(describing: type(of: error))
    }

    private static func run(stage: inout String) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["LEGADO_WEBDAV_URL"], let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme), url.host != nil,
              let user = environment["LEGADO_WEBDAV_USER"], !user.isEmpty,
              let password = environment["LEGADO_WEBDAV_PASSWORD"], !password.isEmpty else {
            throw SmokeError.missingEnvironment
        }
        let client = WebDavClient(baseURL: url, username: user, password: password, httpClient: BoundedURLSessionHttpClient())
        let source = WebDavBackupSource(client: client)
        stage = "PROPFIND 列举 legado 目录"
        let files = try await source.listBackups()
        print("legado 目录中的备份数量：\(files.count)")
        for file in files { print("\(file.displayName)（\(file.size) 字节）") }
        guard let latest = files.first else { throw SmokeError.noBackup }
        stage = "GET 下载备份，列表大小 \(latest.size) 字节"
        let temporary = try await source.downloadToTemporaryFile(latest)
        print("已下载备份至临时文件：\(temporary.path)")
        stage = "本地解包与内存数据库导入"
        let database = try AppDatabase.inMemory()
        let importer = BackupImporter(database: database, localDeviceID: "webdav-readonly-smoke")
        let report = try await importer.importArchive(Data(contentsOf: temporary))
        print("books：\(try await BookshelfRepository(database: database).all().count)")
        print("chapters：\(try await ChapterRepository(database: database).all().count)")
        print("book_sources：\(try await BookSourceRepository(database: database).all().count)")
        print("replace_rules：\(try await ReplaceRuleRepository(database: database).all().count)")
        print("readRecord：\(try await ReadProgressRepository(database: database).all().count)")
        print("bookmarks：\(try await BookmarkRepository(database: database).all().count)")
        print("book_groups：\(try await BookGroupRepository(database: database).all().count)")
        print("cookies：\(try await CookieRepository(database: database).all().count)")
        print("searchBooks：\(try await SearchCacheRepository(database: database).all().count)")
        print("跳过文件：\(report.skippedFiles.joined(separator: ", "))")
        print("失败文件：\(report.failures.keys.sorted().joined(separator: ", "))")
        if !report.failures.isEmpty { throw SmokeError.importFailed }
    }

    private enum SmokeError: Error { case missingEnvironment, noBackup, importFailed }
}
