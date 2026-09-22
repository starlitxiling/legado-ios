#if DEBUG
import SwiftUI
import UniformTypeIdentifiers
import LegadoCore

struct ErrorPresentationGallery: View {
    @State private var error = URLError(.timedOut).presentation(operation: "加载正文", subject: "测试书籍", actions: [.retry])
    @State private var retryCount = 0
    @State private var showsImporter = false

    var body: some View {
        NavigationStack {
            VStack {
                Text("重试次数：\(retryCount)")
                Button("选择文件") { showsImporter = true }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("错误提示")
                .errorBanner(error, dismiss: { error = nil }) { action in
                    if action == .retry { retryCount += 1; error = nil }
                }
                .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
                    if case .failure(let failure) = result { error = failure.presentation(operation: "选择文件") }
                }
        }
    }
}

struct ReaderFailureGallery: View {
    private func directoryBook(_ book: Book) -> Book {
        var value = book; value.bookUrl = "https://reader-offline.test/directory-only"; return value
    }
    @State private var container: AppContainer?
    @State private var book: Book?
    @State private var source: BookSource?
    @State private var error: UserFacingError?
    private let cacheDirectory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    var body: some View {
        NavigationStack {
            if let container, let book, let source {
                List {
                    NavigationLink("断网正文") {
                        ReaderView(destination: ReaderDestination(bookURL: book.bookUrl ?? ""), database: container.database,
                                   client: ReaderOfflineClient(), cacheDirectory: cacheDirectory).environment(container)
                    }
                    NavigationLink("失败目录") {
                        TocView(book: directoryBook(book), source: source, container: container, client: ReaderOfflineClient()) { _ in }
                    }
                }.environment(container)
            } else { ProgressView() }
        }.errorBanner(error, dismiss: { error = nil })
            .task {
                guard container == nil else { return }
                do {
                    let container = try AppContainer.inMemory()
                    var book = Book(); book.name = "断网测试书"; book.bookUrl = "https://reader-offline.test/book"
                    book.origin = "https://reader-offline.test"; book.tocUrl = "https://reader-offline.test/toc"
                    try await container.bookshelf.insert(DiscoveryStorage.row(book, defaults: BookRow()))
                    var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl ?? ""; chapter.url = "https://reader-offline.test/chapter"
                    chapter.title = "第一章 断网"; try await container.chapters.insert(chapter)
                    var source = BookSource(); source.bookSourceUrl = book.origin; source.bookSourceName = "断网书源"
                    source.ruleContent = ContentRule(); source.ruleContent?.content = "body@text"
                    source.ruleToc = TocRule(); source.ruleToc?.chapterList = "a"
                    try await container.bookSources.insert(DiscoveryStorage.row(source, defaults: BookSourceRow()))
                    var candidate = source; candidate.bookSourceUrl = "https://candidate-offline.test"; candidate.bookSourceName = "候选书源"
                    candidate.searchUrl = "https://candidate-offline.test/search"
                    try await container.bookSources.insert(DiscoveryStorage.row(candidate, defaults: BookSourceRow()))
                    self.book = book; self.source = source; self.container = container
                } catch { self.error = error.presentation(operation: "准备测试书籍") }
            }
    }
}

private struct ReaderOfflineClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse { throw URLError(.notConnectedToInternet) }
}
#endif
