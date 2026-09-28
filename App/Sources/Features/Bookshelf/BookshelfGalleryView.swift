#if DEBUG
import SwiftUI
import UIKit
import LegadoCore

struct BookshelfGalleryView: View {
    @State private var container: AppContainer?
    @State private var reading: (any BookshelfReading)?
    @State private var userError: UserFacingError?
    private var error: String? { userError?.displayText }
    private let preferences: AppPreferences
    private let theme: ThemeStore

    init() {
        let defaults = UserDefaults(suiteName: "Legado.BookshelfGallery")!
        if ProcessInfo.processInfo.arguments.contains("-reset-bookshelf-gallery") {
            defaults.removePersistentDomain(forName: "Legado.BookshelfGallery")
        }
        let preferences = AppPreferences(defaults: defaults)
        if ProcessInfo.processInfo.arguments.contains("-bookshelf-gallery-dark") { preferences.set("themeMode", .string("2")) }
        if ProcessInfo.processInfo.arguments.contains("-large-bookshelf-gallery") { preferences.set("showBookshelfFastScroller", .boolean(true)) }
        self.preferences = preferences
        theme = ThemeStore(preferences: preferences)
    }

    var body: some View {
        Group {
            if let container {
                NavigationStack {
                    BookshelfView(bookshelf: reading ?? container.bookshelf, groups: container.bookGroups, preferences: preferences)
                }.environment(container).modifier(ThemeEnvironmentModifier(store: theme))
            } else if let error { Text(error) }
            else { ProgressView("加载中") }
        }
        .task {
            guard container == nil else { return }
            do {
                let fixture = try await fixture()
                if ProcessInfo.processInfo.arguments.contains("-cancel-bookshelf-read") {
                    reading = CancellingGalleryBookshelf(base: fixture.bookshelf)
                }
                container = fixture
            }
            catch { userError = error.presentation(operation: "准备书架示例", subject: nil) }
        }
    }

    @MainActor private func fixture() async throws -> AppContainer {
        let slowRefresh = ProcessInfo.processInfo.arguments.contains("-slow-bookshelf-refresh")
        let container = try AppContainer(database: .inMemory(),
            httpClient: BoundedURLSessionHttpClient(protocolClasses: slowRefresh ? [GalleryRefreshProtocol.self] : []),
            sourceSecrets: MemorySourceSecretStore())
        if slowRefresh {
            var source = BookSourceRow(); source.bookSourceUrl = "https://fixture.test"
            source.ruleToc = #"{"chapterList":"tag.a","chapterName":"text","chapterUrl":"href"}"#
            try await container.bookSources.insert(source)
        }
        try await container.bookGroups.ensureBuiltinGroups()
        var group = BookGroupRow(); group.groupId = 1; group.groupName = "Sample Group"; group.bookSort = 0
        try await container.bookGroups.insert(group)
        if ProcessInfo.processInfo.arguments.contains("-multigroup-bookshelf-gallery") {
            for (id, name): (Int64, String) in [(2, "Second Group"), (4, "Third Group")] {
                var extra = BookGroupRow(); extra.groupId = id; extra.groupName = name
                try await container.bookGroups.insert(extra)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-empty-bookshelf-gallery") { return container }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bookshelf-gallery", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let colors: [UIColor] = [.systemBlue, .systemBrown, .systemGreen, .systemIndigo]
        let count = ProcessInfo.processInfo.arguments.contains("-large-bookshelf-gallery") ? 500 : 18
        for index in 0..<count {
            let title = String(format: "Sample Book %02d", index + 1)
            let file = folder.appendingPathComponent(String(index % 18) + ".png")
            if index < 18 {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 132, height: 180)).image { context in
                colors[index % colors.count].setFill()
                context.fill(CGRect(x: 0, y: 0, width: 132, height: 180))
                (title as NSString).draw(in: CGRect(x: 12, y: 28, width: 108, height: 100), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 21, weight: .semibold), .foregroundColor: UIColor.white])
            }
            guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: file, options: .atomic)
            }
            var book = BookRow(); book.bookUrl = "fixture:book:" + String(index); book.name = title
            book.author = "Sample Author"; book.origin = slowRefresh ? "https://fixture.test" : "fixture:source"; book.originName = "Fixture"
            if slowRefresh { book.tocUrl = "https://fixture.test/toc/" + String(index) }
            book.coverUrl = file.absoluteString; book.group = index < 9 ? 1 : 0; book.type = 8
            if index == 0, ProcessInfo.processInfo.arguments.contains("-multigroup-bookshelf-gallery") { book.group = 3 }
            book.totalChapterNum = 100; book.durChapterIndex = index * 5; book.durChapterPos = index == 0 ? 0 : 12
            book.durChapterTitle = "Chapter " + String(index * 5 + 1); book.latestChapterTitle = "Chapter 100"
            book.durChapterTime = Int64(1_000_000 - index); book.lastCheckTime = 1_000_000
            try await container.bookshelf.insert(book)
        }
        return container
    }
}

@MainActor
private final class CancellingGalleryBookshelf: BookshelfReading {
    private let base: BookshelfRepository
    private var cancelled = false

    init(base: BookshelfRepository) { self.base = base }

    func list(groupID: Int64, sort: BookshelfSort) async throws -> [BookRow] {
        if !cancelled {
            cancelled = true
            throw CancellationError()
        }
        return try await base.list(groupID: groupID, sort: sort)
    }
}
private final class GalleryRefreshProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
#endif
