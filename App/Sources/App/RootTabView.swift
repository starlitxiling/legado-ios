import SwiftUI

struct RootTabView: View {
    let container: AppContainer
    @State private var restoreRevision = 0
    @State private var preferences = AppPreferences.shared
    @State private var selectedPage = AppPreferences.shared.initialHomePage

    var body: some View {
        TabView(selection: $selectedPage) {
            NavigationStack {
                BookshelfView(bookshelf: container.bookshelf, groups: container.bookGroups)
                    .id(restoreRevision)
            }
            .tabItem { Label("书架", systemImage: "books.vertical") }
            .tag("bookshelf")
            if preferences.boolean("showDiscovery") {
            NavigationStack {
                ExploreView(container: container).id(restoreRevision)
            }
            .tabItem { Label("发现", systemImage: "safari") }
            .tag("explore")
            }
            if preferences.boolean("showRss") {
            NavigationStack {
                RssSourceListView(container: container).id(restoreRevision)
            }
            .tabItem { Label("RSS", systemImage: "dot.radiowaves.left.and.right") }
            .tag("rss")
            }
            placeholder("搜索", image: "magnifyingglass", message: "搜索功能将在后续版本提供")
                .tag("search")
            NavigationStack {
                SourcesView(repository: container.bookSources, replaceRules: container.replaceRules,
                            httpClient: ImportHttpClient(), sourceLogin: container.sourceLogin,
                            sourceChecker: container.sourceChecker)
                    .id(restoreRevision)
            }
            .tabItem { Label("书源", systemImage: "tray.full") }
            .tag("sources")
            NavigationStack {
                SettingsView(container: container)
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag("my")
        }
        .onReceive(NotificationCenter.default.publisher(for: BackupViewModel.restoredNotification)) { _ in
            preferences.reload()
            restoreRevision += 1
        }
        .onChange(of: preferences.boolean("showDiscovery")) { _, enabled in
            if !enabled, selectedPage == "explore" { selectedPage = "bookshelf" }
        }
        .onChange(of: preferences.boolean("showRss")) { _, enabled in
            if !enabled, selectedPage == "rss" { selectedPage = "bookshelf" }
        }
        .modifier(AppThemeModifier(preferences: preferences))
    }

    private func placeholder(_ title: String, image: String, message: String) -> some View {
        NavigationStack {
            EmptyStateView(title: title, systemImage: image, message: message)
                .navigationTitle(title)
        }
        .tabItem { Label(title, systemImage: image) }
    }
}
