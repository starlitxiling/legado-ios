#if DEBUG
import SwiftUI
import LegadoCore

struct BookDetailGalleryView: View {
    @State private var container: AppContainer?
    @State private var book: BookRow?
    @State private var error: String?
    private let theme = ThemeStore(preferences: AppPreferences(defaults: UserDefaults(suiteName: "Legado.DetailGallery")!))

    var body: some View {
        Group {
            if let container, let book {
                NavigationStack { BookDetailView(book: book, container: container) }
                    .environment(container).modifier(ThemeEnvironmentModifier(store: theme))
            } else if let error { Text(error) }
            else { ProgressView() }
        }.task {
            guard container == nil else { return }
            do {
                let container = try AppContainer.inMemory()
                for index in 1...2 {
                    var source = BookSourceRow()
                    source.bookSourceUrl = "https://detail\(index).test"; source.bookSourceName = "示例书源 \(index)"
                    source.mainJs = """
                    function search(key,page) { return [{bookUrl:baseUrl+'/book',name:'航海记',author:'林舟',latestChapterTitle:'第十二章 归来'}]; }
                    function getBookInfo(book) { return {intro:'这是一段合成的航海故事，用于验证书籍详情界面。'.repeat(20),tocUrl:baseUrl+'/toc',kind:'科幻,冒险'}; }
                    function getChapters(book) { return [{title:'第一章 启航',url:'1'},{title:'第二章 归来',url:'2'}]; }
                    function getContent(chapter,book,nextChapterUrl) { return '远方的港口亮起灯光，船只缓缓驶向大海。'.repeat(50); }
                    """
                    try await container.bookSources.insert(source)
                }
                let group = try await container.bookGroups.createGroup(name: "科幻")
                var book = BookRow(); book.bookUrl = "https://detail1.test/book"; book.origin = "https://detail1.test"
                book.originName = "示例书源 1"; book.name = "航海记"; book.author = "林舟"; book.kind = "科幻,冒险"
                book.latestChapterTitle = "第十二章 归来"; book.totalChapterNum = 12; book.group = group.groupId
                book.intro = String(repeating: "这是一段合成的航海故事，用于验证书籍详情界面。", count: 20)
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 220, height: 320))
                let data = renderer.pngData { context in
                    UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 220, height: 320))
                    ("航海记" as NSString).draw(at: CGPoint(x: 50, y: 120), withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.white])
                }
                let cover = URL.temporaryDirectory.appendingPathComponent("LegadoDetailGallery.png")
                try data.write(to: cover, options: .atomic); book.coverUrl = cover.absoluteString
                try await container.bookshelf.upsert(book)
                self.book = book; self.container = container
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
