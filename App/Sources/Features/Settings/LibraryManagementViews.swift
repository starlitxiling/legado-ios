import SwiftUI
import LegadoCore

struct LibraryHistoryView: View {
    let container: AppContainer
    let bookmarks: Bool
    @State private var items: [Item] = []
    @State private var error: String?
    private struct Item: Identifiable {
        let id: String
        let name: String
        let detail: String
        let destination: ReaderDestination?
    }
    var body: some View {
        List {
            ForEach(items) { item in
                if let destination = item.destination {
                    NavigationLink { ReaderView(destination: destination, database: container.database, client: container.httpClient) }
                        label: { row(item) }
                } else { row(item) }
            }
            if items.isEmpty { Text(bookmarks ? "尚无书签" : "尚无阅读记录").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }.legadoNavigationTitle(bookmarks ? "书签" : "阅读记录")
            .task { await load() }
    }
    private func row(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name).font(.headline)
            Text(item.detail).font(.caption).foregroundStyle(.secondary)
            if item.destination == nil { Text("书籍尚未加入书架").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func load() async {
        do {
            let books = try await container.bookshelf.all()
            func destination(_ name: String, _ author: String, _ index: Int) -> ReaderDestination? {
                let matches = books.filter { $0.name == name && $0.author == author }
                guard matches.count == 1 else { return nil }
                return ReaderDestination(bookURL: matches[0].bookUrl, chapterIndex: index < 0 ? nil : index)
            }
            if bookmarks {
                items = try await container.bookmarks.all().sorted { $0.time > $1.time }.map {
                    Item(id: String($0.time), name: $0.bookName, detail: [$0.chapterName, $0.bookText, $0.content].filter { !$0.isEmpty }.joined(separator: "\n"),
                         destination: destination($0.bookName, $0.bookAuthor, $0.chapterIndex))
                }
            } else {
                items = try await Repository<ReadRecordRow>(database: container.database).all().sorted { $0.lastRead > $1.lastRead }.map {
                    let date = Date(timeIntervalSince1970: Double($0.lastRead) / 1000).formatted(date: .abbreviated, time: .shortened)
                    return Item(id: $0.deviceId + "|" + $0.bookName + "|" + $0.author, name: $0.bookName,
                         detail: [$0.lastChapterTitle ?? "", date, "阅读 " + String($0.readTime / 60000) + " 分钟"].joined(separator: "\n"),
                         destination: destination($0.bookName, $0.resolvedAuthor ?? $0.author, $0.lastChapterIndex))
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct LibraryFilesView: View {
    let container: AppContainer
    @State private var books: [BookRow] = []
    @State private var error: String?
    var body: some View {
        List {
            NavigationLink("导入本地书") { LocalImportView(database: container.database) }
            ForEach(books, id: \.bookUrl) { book in
                if let url = URL(string: book.bookUrl), url.isFileURL {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.name).font(.headline)
                        Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        ShareLink("分享文件", item: url)
                    }
                }
            }
            if books.isEmpty { Text("尚无本地书籍").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }.legadoNavigationTitle("文件管理")
            .task { await load() }
            .onAppear { Task { await load() } }
    }
    private func load() async {
        do { books = try await container.bookshelf.all().filter { URL(string: $0.bookUrl)?.isFileURL == true } }
        catch { self.error = error.localizedDescription }
    }
}
