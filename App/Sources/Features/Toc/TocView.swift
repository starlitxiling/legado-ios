import SwiftUI
import LegadoCore

struct TocView: View {
    @State private var model: TocViewModel
    private let onSelectChapter: (Int) -> Void

    init(book: Book, source: BookSource, container: AppContainer,
         onSelectChapter: @escaping (Int) -> Void) {
        self.onSelectChapter = onSelectChapter
        _model = State(initialValue: TocViewModel(book: book, source: source, chapters: container.chapters,
            bookshelf: container.bookshelf, client: container.httpClient, database: container.database))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if model.isLoading { ProgressView("正在加载目录") }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button("重试") { Task { await model.refresh() } }
                }
                ForEach(model.displayedChapters, id: \.index) { chapter in
                    Button { onSelectChapter(chapter.index) } label: {
                        HStack {
                            Text(chapter.title)
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
        .navigationTitle("目录")
    }
}
