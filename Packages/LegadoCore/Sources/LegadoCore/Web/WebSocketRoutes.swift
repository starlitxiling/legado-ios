import Foundation

public enum WebSocketRouteEvent: Equatable, Sendable {
    case text(String)
    case close(UInt16, String)
}

public struct WebSocketRoutes {
    public static let paths: Set<String> = ["/bookSourceDebug", "/rssSourceDebug", "/searchBook"]
    public typealias Logs = AsyncStream<SourceDebugLog>
    public typealias SearchResults = AsyncThrowingStream<[SearchBook], Error>
    private let bookDebug: (String, String) async throws -> Logs?
    private let rssDebug: (String) async throws -> Logs?
    private let search: (String) -> SearchResults

    public init(bookDebug: @escaping (String, String) async throws -> Logs?,
                rssDebug: @escaping (String) async throws -> Logs?, search: @escaping (String) -> SearchResults) {
        self.bookDebug = bookDebug; self.rssDebug = rssDebug; self.search = search
    }

    public func events(path: String, message: Data) -> AsyncStream<WebSocketRouteEvent> {
        AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                guard Self.paths.contains(path), let object = try? JSONSerialization.jsonObject(with: message),
                      let values = object as? [String: String] else {
                    continuation.yield(.close(1008, "认证数据格式错误")); return
                }
                let searching = path == "/searchBook"
                let end = searching ? "Search finish" : "调试结束"
                func blank(_ key: String) -> Bool { values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }
                if (!searching && blank("tag")) || (path != "/rssSourceDebug" && blank("key")) {
                    continuation.yield(.text("不能为空")); continuation.yield(.close(1000, end)); return
                }
                do {
                    if searching {
                        var snapshot = WebSocketSearchSnapshot()
                        for try await books in search(values["key"]!) {
                            try Task.checkCancellation()
                            let merged = snapshot.merge(books, key: values["key"]!)
                            continuation.yield(.text(String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)))
                        }
                    } else {
                        let logs = path == "/bookSourceDebug"
                            ? try await bookDebug(values["tag"]!, values["key"]!)
                            : try await rssDebug(values["tag"]!)
                        if let logs {
                            for await log in logs {
                                try Task.checkCancellation()
                                if [10, 20, 30, 40].contains(log.state) { continue }
                                continuation.yield(.text(log.message))
                                if log.state == -1 || log.state == 1000 { break }
                            }
                        } else { continuation.yield(.text(path == "/bookSourceDebug" ? "书源不存在" : "订阅源不存在")) }
                    }
                    if !Task.isCancelled { continuation.yield(.close(1000, end)) }
                } catch is CancellationError {
                } catch {
                    if !Task.isCancelled { continuation.yield(.close(searching ? 1000 : 1011, searching ? String(describing: error) : "调试失败")) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func live(database: AppDatabase, client: any HttpClient,
                            searchOptions: @escaping () -> WebSocketSearchOptions = { .init() }) -> WebSocketRoutes {
        let sources = BookSourceRepository(database: database)
        let rss = RssRepository(database: database)
        return WebSocketRoutes(bookDebug: { tag, key in
            guard let row = try await sources.get(bookSourceUrl: tag) else { return nil }
            let source = try WebApiCodec.entity(row, as: BookSource.self)
            return SourceDebugger(client: client).logs(source: source, key: key)
        }, rssDebug: { tag in
            guard let source = try await rss.sources().first(where: { $0.sourceUrl == tag }) else { return nil }
            return rssLogs(source: source, service: rss.service(client: client))
        }, search: { key in
            let options = searchOptions()
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let all = try await sources.list().map { try WebApiCodec.entity($0, as: BookSource.self) }
                        let batches = WebSocketSearch.batches(sources: options.select(all), key: key, options: options) { source, key, precise in
                            try await WebBook(source: source, client: client, precisionSearch: precise).search(key: key)
                        }
                        for try await books in batches {
                            try Task.checkCancellation()
                            continuation.yield(books)
                        }
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        })
    }

    private static func rssLogs(source: RssSource, service: RssService) -> Logs {
        AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                let start = ProcessInfo.processInfo.systemUptime
                func log(_ text: String, state: Int = 1, showTime: Bool = true) {
                    guard !Task.isCancelled else { return }
                    continuation.yield(.init(state: state, message: showTime ? SourceDebugLog.format(
                        milliseconds: Int64((ProcessInfo.processInfo.systemUptime - start) * 1000), message: text) : text))
                }
                do {
                    log("︾开始解析")
                    let column = try service.columns(source: source).first
                    let page = try await service.articles(source: source, sort: column?.name ?? "", url: column?.url ?? source.sourceUrl, debugLog: { log($0) })
                    try Task.checkCancellation()
                    if let article = page.articles.first {
                        if !(source.ruleArticles ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                            (source.ruleDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            log("︽列表页解析完成")
                            log("", showTime: false)
                            if (source.ruleContent ?? "").isEmpty {
                                log("⇒内容规则为空，默认获取整个网页", state: 1000); return
                            }
                            log("︾开始解析内容页")
                            switch try await service.content(article: article, source: source, debugLog: { log($0) }) {
                            case .html(let text, _): log(text)
                            case .url(let url): log(url)
                            }
                            log("︽内容页解析完成", state: 1000); return
                        } else { log("⇒存在描述规则，不解析内容页") }
                    } else { log("⇒列表页解析成功，为空") }
                    log("︽解析完成", state: 1000)
                } catch is CancellationError {
                } catch { log(String(describing: error), state: -1) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
