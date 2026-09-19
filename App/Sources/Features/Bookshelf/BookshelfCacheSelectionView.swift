import SwiftUI
import LegadoCore

struct BookshelfCacheSelectionView: View {
    let repository: BookshelfRepository
    let downloads: DownloadCenterModel
    @State private var books: [BookRow] = []
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("下载中心") { DownloadCenterView(model: downloads) }
                ForEach(books, id: \.bookUrl) { book in
                    NavigationLink(book.name) { BookCacheExportView(book: book, model: downloads) }
                }
                if let error { Text(error) }
            }
            .legadoNavigationTitle("缓存 / 导出")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
            .task {
                do { books = try await repository.list() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
