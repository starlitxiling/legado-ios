import Foundation

public enum RssReadContent: Equatable, Sendable {
    case html(String, baseURL: String?)
    case url(String)
}

public struct RssService: Sendable {
    private let client: any HttpClient
    private let database: AppDatabase?
    public init(client: any HttpClient, database: AppDatabase? = nil) { self.client = client; self.database = database }

    public func columns(source: RssSource) throws -> [RssColumn] {
        try source.resolveColumns(engine: engine(source: source, baseURL: source.sourceUrl))
    }

    public func articles(source: RssSource, sort: String, url: String, page: Int = 1,
                         existing: [RssArticle] = []) async throws -> RssPage {
        let engine = try engine(source: source, baseURL: source.sourceUrl)
        let response = try await request(url, source: source, engine: engine, page: page)
        var result = try RssParser().parse(response.body, source: source, sort: sort, baseURL: response.url, engine: engine)
        if source.ruleNextPage?.uppercased() == "PAGE" { result.nextPageURL = url }
        var seen = Set(existing.map(\.identity))
        result.articles = result.articles.filter { seen.insert($0.identity).inserted }
        if result.articles.isEmpty { result.nextPageURL = nil }
        return result
    }

    public func content(article: RssArticle, source: RssSource) async throws -> RssReadContent {
        if let description = article.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return target(description, article: article, source: source)
        }
        guard let rule = source.ruleContent, !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .url(article.link) }
        let engine = try engine(source: source, baseURL: article.link)
        engine.bindings["rssArticle"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(article))
        let variables = RuleVariableStore(article.variable.flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:])
        var queue = [article.link]
        var visited = Set<String>()
        var contents: [String] = []
        while !queue.isEmpty {
            try Task.checkCancellation()
            let url = queue.removeFirst()
            guard visited.insert(url).inserted else { continue }
            guard visited.count <= 100 else { throw RssError.paginationLimit }
            let response = try await request(url, source: source, engine: engine)
            visited.insert(response.url)
            let parser = RssParser.analyzer(response.body, baseURL: response.url, engine: engine, ruleData: variables)
            contents.append(try parser.getString(rule))
            if source.type == 0, article.type == 0, let next = source.nextContentUrl, !next.isEmpty {
                queue += (try parser.getStringList(next) ?? []).filter { !$0.isEmpty }.map { RssParser.absolute($0, base: response.url) }
            }
        }
        return target(contents.joined(separator: "\n"), article: article, source: source)
    }

    private func target(_ content: String, article: RssArticle, source: RssSource) -> RssReadContent {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return .url(value) }
        return .html(content, baseURL: source.loadWithBaseUrl ? article.link : nil)
    }

    func engine(source: RssSource, baseURL: String) throws -> JsEngine {
        let engine = JsEngine(baseUrl: baseURL, httpClient: client,
            networkSource: .init(key: source.sourceUrl, enabledCookieJar: source.enabledCookieJar ?? true, concurrentRate: source.concurrentRate))
        engine.bindings["source"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source))
        if let database {
            let bridge = SourceScriptBridge(source: loginSource(source), database: database, secrets: MemorySourceSecretStore())
            engine.sourceBindingInstaller = { [weak engine] in try bridge.install(in: $0, engine: engine) }
        }
        if let library = source.jsLib, !library.isEmpty {
            engine.libraryInitializer = { context in
                context.evaluateScript(library)
                if let error = context.exception { throw JsEngineError.exception(error.toString()) }
            }
        }
        if let header = source.header, !header.isEmpty {
            let text = header.hasPrefix("@js:") ? ruleText(try engine.evaluateScript(String(header.dropFirst(4)))) : header
            engine.networkSource.headers = try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
        }
        return engine
    }

    public func webRequest(url: String, source: RssSource) async throws -> HeadlessWebViewRequest {
        let engine = try engine(source: source, baseURL: source.sourceUrl)
        let executor = try AnalyzeUrlExecutor(url, engine: engine, bindings: engine.bindings)
        var headers = engine.networkSource.headers
        for (name, value) in executor.options.headers { headers.setHTTPHeader(name, value) }
        let cookie = await engine.cookieStore.getCookie(url: source.sourceUrl)
        return HeadlessWebViewRequest(url: executor.url, headers: headers, cookies: cookie, cacheFirst: source.cacheFirst,
            cookieStore: source.enabledCookieJar == false ? nil : engine.cookieStore, tag: source.sourceUrl)
    }

    private func loginSource(_ source: RssSource) -> BookSource {
        var value = BookSource()
        value.bookSourceUrl = source.sourceUrl; value.bookSourceName = source.sourceName
        value.loginUrl = source.loginUrl; value.loginUi = source.loginUi; value.loginCheckJs = source.loginCheckJs
        value.jsLib = source.jsLib; value.header = source.header; value.enabledCookieJar = source.enabledCookieJar
        value.concurrentRate = source.concurrentRate
        return value
    }

    private func request(_ url: String, source: RssSource, engine: JsEngine, page: Int = 1) async throws -> AnalyzeUrlExecutor.Response {
        var bindings = engine.bindings
        bindings["page"] = page
        let executor = try AnalyzeUrlExecutor(url, engine: engine, bindings: bindings)
        let needsCheck = source.loginCheckJs?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let login: SourceLogin? = needsCheck ? SourceLogin(database: try database ?? .inMemory(), client: client, cookies: engine.cookieStore) : nil
        func checked(_ response: AnalyzeUrlExecutor.Response) async throws -> AnalyzeUrlExecutor.Response {
            guard let login else { return response }
            let value = try await login.check(source: loginSource(source), response: StrResponse(raw: response.raw, body: response.body))
            return .init(raw: value.raw, body: value.body, callTime: response.callTime)
        }
        let response: AnalyzeUrlExecutor.Response
        do { response = try await checked(executor.getStrResponse()) }
        catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            let original = error
            guard login != nil, let address = URL(string: executor.url) else { throw original }
            do {
                let recovered = try await checked(.init(raw: .init(status: 500, finalURL: address), body: String(describing: original)))
                guard recovered.code != 500 else { throw original }
                response = recovered
            } catch { throw original }
        }
        guard response.isSuccessful else { throw RssError.httpStatus(response.code) }
        return response
    }
}
