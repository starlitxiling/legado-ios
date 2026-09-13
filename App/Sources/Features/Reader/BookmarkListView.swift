import SwiftUI
import LegadoCore

struct BookmarkListView: View {
    let model: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button("添加当前位置书签", systemImage: "bookmark") { Task { await model.addBookmark() } }
                ForEach(model.bookmarks, id: \.time) { bookmark in
                    Button {
                        Task { await model.openBookmark(bookmark); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.chapterName)
                            Text(bookmark.bookText).font(.caption).lineLimit(3)
                            if !bookmark.content.isEmpty { Text(bookmark.content).foregroundStyle(.secondary) }
                        }
                    }
                    .swipeActions { Button("删除", role: .destructive) { Task { await model.deleteBookmark(bookmark) } } }
                }
            }
            .navigationTitle("书签")
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}
