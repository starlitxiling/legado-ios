import SwiftUI
import LegadoCore

struct RssFavoritesView: View {
    let repository: RssRepository
    let client: any HttpClient
    @State private var stars: [RssStar] = []
    @State private var sources: [RssSource] = []
    @State private var error: String?
    var body: some View {
        List {
            ForEach(stars, id: \.article.identity) { star in
                NavigationLink {
                    RssReadView(article: star.article, source: sources.first { $0.sourceUrl == star.origin } ?? RssSource(sourceUrl: star.origin), repository: repository, client: client)
                } label: { Text(star.title) }
                .swipeActions {
                    Button("取消收藏", role: .destructive) {
                        Task {
                            do { try await repository.setStar(star.article, starred: false, time: 0); await reload() }
                            catch { self.error = String(describing: error) }
                        }
                    }
                }
            }
            if stars.isEmpty { Text("暂无收藏").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("RSS 收藏")
        .task { await reload() }
        .refreshable { await reload() }
    }
    private func reload() async {
        do { stars = try await repository.stars(); sources = try await repository.sources() }
        catch { self.error = String(describing: error) }
    }
}
