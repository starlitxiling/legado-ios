#if DEBUG
import SwiftUI
import LegadoCore

struct ExploreGalleryView: View {
    @State private var container: AppContainer?
    @State private var error: UserFacingError?
    private let theme = ThemeStore(preferences: AppPreferences(defaults: UserDefaults(suiteName: "Legado.ExploreGallery")!))

    var body: some View {
        Group {
            if let container {
                NavigationStack { ExploreView(container: container) }
                    .environment(container).modifier(ThemeEnvironmentModifier(store: theme))
            } else if let error { Text(error.displayText) }
            else { ProgressView("加载中") }
        }.task {
            guard container == nil else { return }
            do {
                let container = try AppContainer.inMemory()
                for index in 1...3 {
                    var source = BookSourceRow()
                    source.bookSourceUrl = "https://explore\(index).test"; source.bookSourceName = "Sample Source \(index)"
                    source.bookSourceGroup = index == 3 ? "Other" : "Books"
                    source.exploreUrl = #"[{"title":"Popular","url":"/popular"},{"title":"New","url":"/new"},{"title":"Query","type":"text"},{"title":"Order","type":"select","chars":["Newest","Oldest"],"default":"Newest"},{"title":"Mode","type":"toggle","chars":["All","Finished"]},{"title":"Apply","type":"button","action":"infoMap.save();java.reUiView()"}]"#
                    source.mainJs = """
                    function explore(url,page) {
                      if(page>1)return [];
                      return [{bookUrl:'https://explore.test/book',name:'Sample Discovery Book',author:'Sample Author',kind:'Fiction',latestChapterTitle:'Chapter 12',intro:'A synthetic discovery result for interface testing.'}];
                    }
                    """
                    try await container.bookSources.insert(source)
                }
                self.container = container
            } catch { self.error = error.presentation(operation: "准备发现预览") }
        }
    }
}
#endif
