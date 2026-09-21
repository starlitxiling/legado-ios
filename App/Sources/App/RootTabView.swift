import SwiftUI

struct RootTabView: View {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var restoreRevision = 0
    @State private var exploreRevision = 0
    @State private var preferences = AppPreferences.shared
    @State private var selectedPage = AppPreferences.shared.initialHomePage

    private var pages: [(id: String, title: String)] {
        var values = [("bookshelf", "书架")]
        if preferences.boolean("showDiscovery") { values.append(("explore", "发现")) }
        if preferences.boolean("showRss") { values.append(("rss", "订阅")) }
        values.append(("my", "我的"))
        return values
    }

    var body: some View {
        TabView(selection: $selectedPage) {
            NavigationStack {
                BookshelfView(bookshelf: container.bookshelf, groups: container.bookGroups)
                    .id(restoreRevision)
                    .background(tabObserver)
            }
            .tabItem { Image(systemName: "books.vertical").accessibilityLabel("书架") }
            .tag("bookshelf")
            if preferences.boolean("showDiscovery") {
                NavigationStack {
                    ExploreView(container: container).id(restoreRevision)
                        .background(tabObserver)
                }
                .id(exploreRevision)
                .tabItem { Image(systemName: "safari").accessibilityLabel("发现") }
                .tag("explore")
            }
            if preferences.boolean("showRss") {
                NavigationStack {
                    RssSourceListView(container: container).id(restoreRevision)
                        .background(tabObserver)
                }
                .tabItem { Image(systemName: "dot.radiowaves.left.and.right").accessibilityLabel("订阅") }
                .tag("rss")
            }
            NavigationStack {
                SettingsView(container: container).background(tabObserver)
            }
            .tabItem { Image(systemName: "person.crop.circle").accessibilityLabel("我的") }
            .tag("my")
        }
        .onReceive(NotificationCenter.default.publisher(for: BackupViewModel.restoredNotification)) { _ in
            preferences.reload()
            restoreRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: MainTabObserver.reselectedNotification)) { event in
            if event.object as? String == "explore" { exploreRevision += 1 }
        }
        .onChange(of: preferences.boolean("showDiscovery")) { _, enabled in
            if !enabled, selectedPage == "explore" { selectedPage = "bookshelf" }
        }
        .onChange(of: preferences.boolean("showRss")) { _, enabled in
            if !enabled, selectedPage == "rss" { selectedPage = "bookshelf" }
        }
        .task {
            while !Task.isCancelled {
                if scenePhase == .active && preferences.boolean("autoTaskService") { await container.autoTasks.runDue() }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .modifier(AppThemeModifier(preferences: preferences))
    }

    private var tabObserver: some View { MainTabObserver(pages: pages) }
}
