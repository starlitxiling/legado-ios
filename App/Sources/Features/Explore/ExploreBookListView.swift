import SwiftUI
import LegadoCore

struct ExploreBookListView: View {
    let container: AppContainer
    private let kinds: [ExploreKind]
    @State private var selected: ExploreKind
    @State private var model: ExploreViewModel
    @Environment(\.themeColors) private var colors

    init(source: BookSource, kind: ExploreKind, container: AppContainer, kinds: [ExploreKind] = []) {
        self.container = container
        self.kinds = kinds.filter { $0.type == "url" && !$0.isHeading }
        _selected = State(initialValue: kind)
        _model = State(initialValue: ExploreViewModel(source: source, client: container.httpClient))
    }

    var body: some View {
        List {
            ForEach(model.books, id: \.bookUrl) { book in
                NavigationLink {
                    BookDetailView(results: [book], container: container)
                } label: { SearchResultRow(book: book) }
                .listRowInsets(EdgeInsets())
                .onAppear {
                    if book.bookUrl == model.books.last?.bookUrl, model.errorMessage == nil {
                        Task { await model.loadNextPage() }
                    }
                }
            }
            if model.isLoading { LoadingView() }
            if let error = model.errorMessage { Text(error).foregroundStyle(colors.error) }
            if model.hasMore && !model.isLoading {
                Button(model.errorMessage == nil ? "加载更多" : "重试") { Task { await model.loadNextPage() } }
            }
            if !model.hasMore { EmptyText(text: model.books.isEmpty ? "暂无书籍" : "已加载全部书籍") }
        }.listStyle(.plain)
        .refreshable { await model.select(selected) }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                categoryTabs
                if model.isLoading { RefreshProgressBar() }
            }.background(colors.background)
        }
        .legadoNavigationTitle(selected.title)
        .task(id: selected) { await model.select(selected) }
    }

    @ViewBuilder private var categoryTabs: some View {
        if kinds.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(kinds.indices, id: \.self) { index in
                        let kind = kinds[index]
                        Button { selected = kind } label: {
                            Text(kind.title).font(.system(size: 14))
                                .foregroundStyle(selected == kind ? colors.accent : colors.textSecondary)
                                .padding(.horizontal, 12).frame(height: 40)
                                .overlay(alignment: .bottom) {
                                    if selected == kind { Rectangle().fill(colors.accent).frame(height: 2) }
                                }
                        }.buttonStyle(.plain).accessibilityIdentifier("explore.tab." + kind.title)
                    }
                }.frame(height: 40)
            }.frame(height: 40)
        }
    }

}
