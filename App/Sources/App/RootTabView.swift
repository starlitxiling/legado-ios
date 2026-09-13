import SwiftUI

struct RootTabView: View {
    let container: AppContainer
    @State private var restoreRevision = 0

    var body: some View {
        TabView {
            NavigationStack {
                BookshelfView(bookshelf: container.bookshelf, groups: container.bookGroups)
                    .id(restoreRevision)
            }
            .tabItem { Label("书架", systemImage: "books.vertical") }
            placeholder("搜索", image: "magnifyingglass", message: "搜索功能将在后续版本提供")
            NavigationStack {
                SourcesView(repository: container.bookSources, replaceRules: container.replaceRules,
                            httpClient: ImportHttpClient())
                    .id(restoreRevision)
            }
            .tabItem { Label("书源", systemImage: "tray.full") }
            NavigationStack {
                SettingsView(container: container)
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .onReceive(NotificationCenter.default.publisher(for: BackupViewModel.restoredNotification)) { _ in
            restoreRevision += 1
        }
    }

    private func placeholder(_ title: String, image: String, message: String) -> some View {
        NavigationStack {
            EmptyStateView(title: title, systemImage: image, message: message)
                .navigationTitle(title)
        }
        .tabItem { Label(title, systemImage: image) }
    }
}
