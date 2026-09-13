import Foundation

public struct SourceDebugLog: Equatable, Sendable {
    public let state: Int
    public let message: String

    public static func format(milliseconds: Int64, message: String) -> String {
        let value = max(0, milliseconds)
        return String(format: "[%02lld:%02lld.%03lld] %@", (value / 60_000) % 60,
                      (value / 1_000) % 60, value % 1_000, message)
    }
}

public final class SourceDebugger {
    private let client: any HttpClient
    private let clock: () -> Int64

    public init(client: any HttpClient, clock: @escaping () -> Int64 = {
        Int64(ProcessInfo.processInfo.systemUptime * 1000)
    }) {
        self.client = client; self.clock = clock
    }

    public func logs(source: BookSource, key: String) -> AsyncStream<SourceDebugLog> {
        AsyncStream { continuation in
            let task = Task {
                let start = clock()
                func log(_ message: String = "", state: Int = 1, showTime: Bool = true) {
                    guard !Task.isCancelled else { return }
                    continuation.yield(SourceDebugLog(state: state, message: showTime
                        ? SourceDebugLog.format(milliseconds: clock() - start, message: message) : message))
                }
                defer { continuation.finish() }
                let web = WebBook(source: source, client: client)
                do {
                    var book = Book(now: 0)
                    book.origin = source.bookSourceUrl
                    var directChapter: BookChapter?
                    var needsInfo = true
                    if key.hasPrefix("http://") || key.hasPrefix("https://") {
                        book.bookUrl = key
                        log("⇒开始访问详情页:\(key)")
                    } else if key.hasPrefix("++") && !key.contains("::") {
                        book.tocUrl = String(key.dropFirst(2)); needsInfo = false
                        log("⇒开始访目录页:\(book.tocUrl ?? "")")
                    } else if key.hasPrefix("--") && !key.contains("::") {
                        var chapter = BookChapter()
                        chapter.url = String(key.dropFirst(2)); chapter.title = "调试"
                        chapter.baseUrl = source.bookSourceUrl
                        directChapter = chapter; needsInfo = false
                        log("⇒开始访正文页:\(chapter.url ?? "")")
                    } else {
                        let results: [SearchBook]
                        if let separator = key.range(of: "::") {
                            let url = String(key[separator.upperBound...])
                            log("⇒开始访问发现页:\(url)"); log("︾开始解析发现页")
                            results = try await web.explore(url: url)
                        } else {
                            log("⇒开始搜索关键字:\(key)"); log("︾开始解析搜索页")
                            results = try await web.search(key: key)
                        }
                        guard let first = results.first else { log("︽未获取到书籍", state: -1); return }
                        log(key.contains("::") ? "︽发现页解析完成" : "︽搜索页解析完成")
                        log(showTime: false)
                        book.bookUrl = first.bookUrl; book.name = first.name; book.author = first.author
                        book.type = first.type; book.variable = first.variable
                        book.origin = first.origin; book.originName = first.originName; book.originOrder = first.originOrder
                        book.kind = first.kind; book.intro = first.intro; book.coverUrl = first.coverUrl
                        book.wordCount = first.wordCount; book.latestChapterTitle = first.latestChapterTitle
                        if let toc = first.tocUrl, !toc.isEmpty {
                            book.tocUrl = toc; needsInfo = false
                            log("≡已获取目录链接,跳过详情页"); log(showTime: false)
                        }
                    }
                    try Task.checkCancellation()
                    if needsInfo {
                        log("︾开始解析详情页")
                        book = try await web.bookInfo(book)
                        log("︽详情页解析完成"); log(showTime: false)
                        if book.type & 128 != 0 {
                            log("≡文件类书源跳过解析目录", state: 1000); return
                        }
                    }
                    var nextURL: String?
                    let chapter: BookChapter
                    if let directChapter { chapter = directChapter }
                    else {
                        log("︾开始解析目录页")
                        let chapters = try await web.chapterList(book: &book)
                        log("︽目录页解析完成"); log(showTime: false)
                        let toc = chapters.filter { !($0.isVolume && ($0.url ?? "").hasPrefix($0.title ?? "")) }
                        guard let first = toc.first else { log("≡没有正文章节", state: -1); return }
                        chapter = first
                        nextURL = toc.count > 1 ? toc[1].url : first.url
                    }
                    try Task.checkCancellation()
                    log("︾开始解析正文页")
                    let result = try await web.content(book: book, chapter: chapter, nextChapterUrl: nextURL)
                    log(result.rawContent)
                    log("︽正文页解析完成", state: 1000)
                } catch is CancellationError {
                } catch {
                    log(String(describing: error), state: -1)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
