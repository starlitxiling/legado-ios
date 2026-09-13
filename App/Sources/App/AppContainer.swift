import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class AppContainer {
    let database: AppDatabase
    let databaseLifecycle: DatabaseLifecycleCoordinator
    let httpClient: SourceLoginHttpClient
    let sourceLogin: SourceLogin
    let sourceChecker: SourceChecker
    let bookshelf: BookshelfRepository
    let bookGroups: BookGroupRepository
    let bookSources: BookSourceRepository
    let chapters: ChapterRepository
    let bookmarks: BookmarkRepository
    let readProgress: ReadProgressRepository
    let replaceRules: ReplaceRuleRepository
    let searchCache: SearchCacheRepository
    let cookies: CookieRepository
    let headlessWebView: HeadlessWebViewScheduler
    let browserInteraction: BrowserInteraction
    let downloads: DownloadCenterModel
    let backgroundRefresh: BookshelfBackgroundRefresh
    let audioPlayback = AVPlayerAudioPlayer()
    let webService: WebServiceController

    init(database: AppDatabase, httpClient: BoundedURLSessionHttpClient = .init()) {
        self.database = database
        let httpClient = PreferenceHttpClient(underlying: httpClient,
            userAgent: { UserDefaults.standard.string(forKey: "userAgent") ?? "" },
            recordResponse: { request, response in
                if UserDefaults.standard.bool(forKey: "recordHttpLog") {
                    NSLog("HTTP %@ %d %@", request.method, response.status, response.finalURL.host ?? "")
                }
            })
        let browserInteraction = BrowserInteraction()
        self.browserInteraction = browserInteraction
        let headlessWebView = HeadlessWebViewScheduler(loader: HeadlessWebView(), maximumConcurrentLoads: 2,
            isForeground: { await MainActor.run { HeadlessWebView.keyWindow != nil } })
        self.headlessWebView = headlessWebView
        WebViewServices.shared.install(loader: headlessWebView, interaction: browserInteraction,
            userAgent: {
                let configured = UserDefaults.standard.string(forKey: "userAgent")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return configured.isEmpty ? try await HeadlessWebView.defaultUserAgent() : configured
            })
        databaseLifecycle = DatabaseLifecycleCoordinator(suspend: { database.suspend() },
                                                         resume: { database.resume() })
        let sourceSecrets = SourceLoginKeychainStore()
        self.httpClient = SourceLoginHttpClient(database: database, underlying: httpClient, secrets: sourceSecrets)
        sourceLogin = SourceLogin(database: database, client: httpClient, secrets: sourceSecrets)
        sourceChecker = SourceChecker(client: httpClient, database: database, secrets: sourceSecrets)
        bookshelf = BookshelfRepository(database: database)
        bookGroups = BookGroupRepository(database: database)
        bookSources = BookSourceRepository(database: database)
        chapters = ChapterRepository(database: database)
        bookmarks = BookmarkRepository(database: database)
        readProgress = ReadProgressRepository(database: database)
        replaceRules = ReplaceRuleRepository(database: database)
        searchCache = SearchCacheRepository(database: database)
        cookies = CookieRepository(database: database)
        downloads = DownloadCenterModel(database: database, client: self.httpClient,
            threadCount: UserDefaults.standard.object(forKey: "threadCount") as? Int ?? 32)
        backgroundRefresh = BookshelfBackgroundRefresh(database: database, client: self.httpClient)
        webService = WebServiceController.live(database: database, client: self.httpClient)
    }

    static func live() throws -> AppContainer {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Legado", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = AppContainer(database: try .file(at: directory.appendingPathComponent("legado.sqlite").path))
        container.backgroundRefresh.register()
        return container
    }

    static func inMemory() throws -> AppContainer {
        AppContainer(database: try .inMemory())
    }
}
