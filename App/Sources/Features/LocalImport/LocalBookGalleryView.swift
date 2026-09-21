#if DEBUG
import SwiftUI
import LegadoCore

struct LocalBookGalleryView: View {
    @State private var container: AppContainer?
    @State private var books: [String: BookRow] = [:]
    @State private var results: [String] = []
    @State private var status = "Loading fixtures"
    private let root = URL.documentsDirectory.appendingPathComponent("LocalBookRegression", isDirectory: true)

    var body: some View {
        NavigationStack {
            List {
                Text(status).accessibilityIdentifier("localbook.status")
                if let container {
                    forReader("epub", container: container)
                    forReader("pdf", container: container)
                    forReader("azw3", container: container)
                }
                ForEach(results, id: \.self) { Text($0) }
            }
            .navigationTitle("Local book regression")
        }
        .task { await load() }
    }

    @ViewBuilder private func forReader(_ format: String, container: AppContainer) -> some View {
        if let book = books[format] {
            NavigationLink("Open " + format.uppercased()) {
                ReaderView(destination: ReaderDestination(bookURL: book.bookUrl, chapterIndex: format == "epub" ? 1 : 0),
                    database: container.database, client: ReplayHttpClient(), cacheDirectory: root.appendingPathComponent("cache"))
                    .environment(container)
            }.accessibilityIdentifier("localbook.open." + format)
        }
    }

    @MainActor private func load() async {
        guard container == nil else { return }
        do {
            let container = try AppContainer.inMemory()
            for name in ["books", "cache"] {
                let path = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
            }
            let urls = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("input"), includingPropertiesForKeys: nil)
                .filter { LocalBook.fileExtensions.contains($0.pathExtension.lowercased()) || BookArchive.formats.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard Set(urls.map { $0.pathExtension.lowercased() }).count == 10 else {
                throw BookArchiveError.invalid("Expected one fixture for each of the ten local formats")
            }
            let model = LocalImportViewModel(database: container.database, booksDirectory: root.appendingPathComponent("books"))
            var seen = Set<String>()
            for url in urls {
                await model.importFiles([url], keepBoth: true)
                guard model.errors.isEmpty else { throw BookArchiveError.invalid(model.errors.joined(separator: "\n")) }
                let added = try await container.bookshelf.list().filter { !seen.contains($0.bookUrl) }
                guard !added.isEmpty else { throw BookArchiveError.invalid("No imported books: " + url.lastPathComponent) }
                for row in added {
                    let book = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(row))
                    let chapters = try LocalBook.chapterList(book: book)
                    guard let last = chapters.last, try !LocalBook.content(book: book, chapter: last).isEmpty else {
                        throw BookArchiveError.invalid("Empty final chapter: " + url.lastPathComponent)
                    }
                    seen.insert(row.bookUrl)
                }
                books[url.pathExtension.lowercased()] = added.first
                results.append(url.pathExtension.uppercased() + ": imported and final chapter read")
            }
            self.container = container
            status = "10 formats passed"
        } catch { status = error.localizedDescription }
    }
}
#endif
