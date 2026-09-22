#if DEBUG
import SwiftUI
import LegadoCore

struct SourceGalleryView: View {
    @State private var container: AppContainer?
    @State private var error: UserFacingError?
    private let theme = ThemeStore(preferences: AppPreferences(defaults: UserDefaults(suiteName: "Legado.SourceGallery")!))
    var body: some View {
        Group {
            if let container {
                NavigationStack {
                    SourcesView(repository: container.bookSources, replaceRules: container.replaceRules,
                        httpClient: ReplayHttpClient(), sourceLogin: container.sourceLogin, sourceChecker: container.sourceChecker)
                }.environment(container).modifier(ThemeEnvironmentModifier(store: theme))
            } else if let error { Text(error.displayText) } else { ProgressView() }
        }.task {
            guard container == nil else { return }
            do {
                let container = try AppContainer.inMemory()
                for index in 1...3 {
                    var source = BookSourceRow(); source.bookSourceUrl = "https://source\(index).test"; source.bookSourceName = "示例书源 \(index)"
                    source.bookSourceGroup = index == 3 ? nil : "常用"; source.enabled = index != 3; source.customOrder = index
                    source.exploreUrl = index == 1 ? "精选::/list" : nil
                    if index == 2 { source.mainJs = "function search(key,page) { return []; }" }
                    try await container.bookSources.insert(source)
                }
                var book = BookRow(); book.bookUrl = "https://source1.test/book"; book.origin = "https://source1.test"; book.name = "Book"
                try await container.bookshelf.insert(book)
                self.container = container
            } catch { self.error = error.presentation(operation: "准备书源预览") }
        }
    }
}
#endif
