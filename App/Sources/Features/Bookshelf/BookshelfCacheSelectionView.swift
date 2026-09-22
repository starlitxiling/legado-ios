import SwiftUI
import LegadoCore

struct BookshelfCacheSelectionView: View {
    let repository: BookshelfRepository
    let downloads: DownloadCenterModel
    let groupID: Int64
    @State private var books: [BookRow] = []
    @State private var userError: UserFacingError?
    private var error: String? { userError?.displayText }
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
                do { books = try await repository.list(groupID: groupID) }
                catch { userError = error.presentation(operation: "读取待缓存书籍", subject: nil) }
            }
        }
    }
}
