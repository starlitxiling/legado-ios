import SwiftUI
import LegadoCore

struct TocView: View {
    @State private var model: TocViewModel
    private let onSelectChapter: (Int) -> Void

    init(book: Book, source: BookSource, container: AppContainer, client: (any HttpClient)? = nil,
         onSelectChapter: @escaping (Int) -> Void) {
        self.onSelectChapter = onSelectChapter
        _model = State(initialValue: TocViewModel(book: book, source: source, chapters: container.chapters,
            bookshelf: container.bookshelf, client: client ?? container.httpClient, database: container.database))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if model.isLoading { ProgressView("正在加载目录") }
                ForEach(model.displayedChapters, id: \.index) { chapter in
                    Button { onSelectChapter(chapter.index) } label: {
                        HStack {
                            Text(chapter.title)
                            if model.cachedChapterIndices.contains(chapter.index) {
                                Image(systemName: "circle.fill").font(.system(size: 5)).accessibilityLabel("已缓存")
                            }
                            Spacer()
                            if chapter.isVip { Text("VIP").font(.caption).foregroundStyle(.orange) }
                            if chapter.index == model.currentChapterIndex {
                                Image(systemName: "bookmark.fill").accessibilityLabel("当前章节")
                            }
                        }
                    }
                    .disabled(chapter.isVolume)
                    .id(chapter.index)
                }
            }
            .refreshable { await model.refresh() }
            .safeAreaInset(edge: .bottom) {
                Text("已缓存 \(model.cachedChapterIndices.count) / \(model.chapters.count) 章").font(.caption).padding()
            }
            .toolbar {
                Button(model.isReversed ? "正序" : "倒序") { model.isReversed.toggle() }
                Button("定位当前章") {
                    if let index = model.currentChapterIndex { proxy.scrollTo(index, anchor: .center) }
                }
                .disabled(model.currentChapterIndex == nil)
            }
            .task {
                await model.load()
                if let index = model.currentChapterIndex { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .errorBanner(model.userError, dismiss: model.dismissError) { action in
            if action == .retry { Task { await model.refresh() } }
        }
        .legadoNavigationTitle("目录")
    }
}
