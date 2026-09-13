import SwiftUI
import LegadoCore

struct RssArticlesView: View {
    @State private var model: RssArticlesModel
    let client: any HttpClient
    init(source: RssSource, repository: RssRepository, client: any HttpClient) {
        self.client = client
        _model = State(initialValue: RssArticlesModel(source: source, repository: repository, client: client))
    }
    var body: some View {
        List {
            if model.columns.count > 1 {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(model.columns.enumerated()), id: \.offset) { index, column in
                            Button(column.name) { model.columnIndex = index }
                                .buttonStyle(.bordered).tint(index == model.columnIndex ? .accentColor : .secondary)
                        }
                    }
                }
            }
            ForEach(model.articles, id: \.identity) { article in
                NavigationLink {
                    RssReadView(article: article, source: model.source, repository: model.repository, client: client)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title).foregroundStyle(article.read ? .secondary : .primary)
                        if model.source.articleStyle != 4, let date = article.pubDate { Text(date).font(.caption).foregroundStyle(.secondary) }
                        if [1, 2].contains(model.source.articleStyle), let description = article.description {
                            Text(description).font(.caption).lineLimit(3).foregroundStyle(.secondary)
                        }
                        if [2, 3].contains(model.source.articleStyle), let image = article.image, let url = URL(string: image) {
                            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(maxHeight: 180)
                        }
                    }
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
            if model.loading { ProgressView() }
            else if model.nextURL != nil { Button("加载更多") { Task { await model.loadMore() } } }
        }
        .navigationTitle(model.source.sourceName)
        .task(id: model.columnIndex) { await model.refresh() }
        .refreshable { await model.refresh() }
    }
}
