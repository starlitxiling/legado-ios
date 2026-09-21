#if DEBUG
import SwiftUI
import UIKit
import LegadoCore

struct SearchGalleryView: View {
    @State private var container: AppContainer?
    @State private var model: SearchViewModel?
    @State private var error: String?
    private let preferences: AppPreferences
    private let theme: ThemeStore

    init() {
        let defaults = UserDefaults(suiteName: "Legado.SearchGallery")!
        if ProcessInfo.processInfo.arguments.contains("-reset-search-gallery") { defaults.removePersistentDomain(forName: "Legado.SearchGallery") }
        let preferences = AppPreferences(defaults: defaults)
        self.preferences = preferences
        theme = ThemeStore(preferences: preferences)
    }

    var body: some View {
        Group {
            if let container, let model {
                NavigationStack { SearchView(container: container, model: model, preferences: preferences) }
                    .environment(container).modifier(ThemeEnvironmentModifier(store: theme))
            } else if let error { Text(error) }
            else { ProgressView("加载中") }
        }.task {
            guard container == nil else { return }
            do { try await prepare() } catch { self.error = error.localizedDescription }
        }
    }

    @MainActor private func prepare() async throws {
        let container = try AppContainer.inMemory()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 220)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 220))
            ("Reading" as NSString).draw(at: CGPoint(x: 14, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.white])
        }
        let cover = FileManager.default.temporaryDirectory.appendingPathComponent("search-gallery-cover.png")
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: cover, options: .atomic)
        for (index, host) in ["a", "b"].enumerated() {
            var source = BookSource(); source.bookSourceUrl = "https://\(host).fixture.test"; source.bookSourceName = "Source " + host.uppercased()
            source.bookSourceGroup = index == 0 ? "Fiction" : "History"; source.searchUrl = "/search"
            source.ruleSearch = SearchRule(); source.ruleSearch?.bookList = "tag.article"; source.ruleSearch?.name = "tag.h2@text"
            source.ruleSearch?.author = "tag.b@text"; source.ruleSearch?.bookUrl = "tag.a@href"
            source.ruleSearch?.coverUrl = "tag.img@src"; source.ruleSearch?.intro = "tag.p@text"
            source.ruleSearch?.kind = "tag.i@text"; source.ruleSearch?.lastChapter = "tag.small@text"
            try await container.bookSources.insert(DiscoveryStorage.row(source, defaults: BookSourceRow()))
        }
        var book = BookRow(); book.bookUrl = "fixture:shelf"; book.name = "Ocean Journey"; book.author = "A. Writer"; book.coverUrl = cover.absoluteString
        try await container.bookshelf.insert(book)
        var record = ReadRecordRow(); record.bookName = "Mountain Stories"; record.author = "B. Writer"; record.readTime = 100
        try await container.readProgress.insert(record)
        let keywords = SearchKeywordRepository(database: container.database)
        try await keywords.record("Ocean", at: 2); try await keywords.record("Adventure", at: 1)
        let html = ["Ocean Journey", "Mountain Stories", "History Notebook"].enumerated().map { index, name in
            "<article><h2>\(name)</h2><b>\(["A.", "B.", "C."][index]) Writer</b><a href='/book/\(index)'>Link</a><img src='\(cover.absoluteString)'><i>Fiction,Adventure</i><small>Chapter 100</small><p>A journey through unfamiliar places. This sample description verifies the three-line introduction in search results.</p></article>"
        }.joined()
        model = SearchViewModel(sources: container.bookSources, client: SearchGalleryClient(body: html), keywords: keywords,
            bookshelf: container.bookshelf, records: container.readProgress)
        self.container = container
    }
}

private struct SearchGalleryClient: HttpClient {
    let body: String
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        try Task.checkCancellation()
        guard request.url.host?.hasSuffix(".fixture.test") == true else { throw URLError(.unsupportedURL) }
        return .init(status: 200, body: Data(body.utf8), finalURL: request.url)
    }
}
#endif
