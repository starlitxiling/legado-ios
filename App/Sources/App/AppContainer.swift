import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class AppContainer {
    let database: AppDatabase
    let databaseLifecycle: DatabaseLifecycleCoordinator
    let httpClient: BoundedURLSessionHttpClient
    let bookshelf: BookshelfRepository
    let bookGroups: BookGroupRepository
    let bookSources: BookSourceRepository
    let chapters: ChapterRepository
    let bookmarks: BookmarkRepository
    let readProgress: ReadProgressRepository
    let replaceRules: ReplaceRuleRepository
    let searchCache: SearchCacheRepository
    let cookies: CookieRepository

    init(database: AppDatabase, httpClient: BoundedURLSessionHttpClient = .init()) {
        self.database = database
        databaseLifecycle = DatabaseLifecycleCoordinator(suspend: { database.suspend() },
                                                         resume: { database.resume() })
        self.httpClient = httpClient
        bookshelf = BookshelfRepository(database: database)
        bookGroups = BookGroupRepository(database: database)
        bookSources = BookSourceRepository(database: database)
        chapters = ChapterRepository(database: database)
        bookmarks = BookmarkRepository(database: database)
        readProgress = ReadProgressRepository(database: database)
        replaceRules = ReplaceRuleRepository(database: database)
        searchCache = SearchCacheRepository(database: database)
        cookies = CookieRepository(database: database)
    }

    static func live() throws -> AppContainer {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Legado", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppContainer(database: try .file(at: directory.appendingPathComponent("legado.sqlite").path))
    }

    static func inMemory() throws -> AppContainer {
        AppContainer(database: try .inMemory())
    }
}
