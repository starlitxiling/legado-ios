import Foundation
import JavaScriptCore

public enum JsEngineError: Error, CustomStringConvertible {
    case unavailable
    case exception(String)
    case unimplemented(String)

    public var description: String {
        switch self {
        case .unavailable: return "无法创建 JavaScriptCore 上下文"
        case .exception(let message): return "JavaScript: \(message)"
        case .unimplemented(let method): return "未实现：\(method)"
        }
    }
}

final class JsSession {
    let context: JSContext
    let host: JavaHost
    init(context: JSContext, host: JavaHost) { self.context = context; self.host = host }
}

/// 一条规则流水线共享上下文；独立入口及宿主嵌套求值隔离上下文。
public final class JsEngine: SelectorEngine {
    public var baseUrl: String
    public var bindings: [String: Any]
    public var libraryInitializer: ((JSContext) throws -> Void)?
    public var logger: (String) -> Void
    public var timeZone: TimeZone
    public var httpClient: any HttpClient
    public var cookieStore: CookieStore
    public var cacheManager: CacheManager
    public var networkSource: AnalyzeUrlExecutor.Source
    public var rateLimiter: ConcurrentRateLimiter
    public var downloadStore: any HostDownloadStore
    public var networkConcurrency: Int = 32
    public static let sharedCookieStore = CookieStore()

    public init(baseUrl: String = "", bindings: [String: Any] = [:],
                timeZone: TimeZone = .current, logger: @escaping (String) -> Void = { _ in },
                httpClient: any HttpClient = URLSessionHttpClient(), cookieStore: CookieStore = JsEngine.sharedCookieStore,
                cacheManager: CacheManager = .shared, networkSource: AnalyzeUrlExecutor.Source = .init(),
                rateLimiter: ConcurrentRateLimiter = .shared, downloadStore: any HostDownloadStore = MemoryHostDownloadStore()) {
        self.baseUrl = baseUrl
        self.bindings = bindings
        self.timeZone = timeZone
        self.logger = logger
        self.httpClient = httpClient
        self.cookieStore = cookieStore
        self.cacheManager = cacheManager
        self.networkSource = networkSource
        self.rateLimiter = rateLimiter
        self.downloadStore = downloadStore
    }

    public func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        var values = context.scriptBindings
        values["baseUrl"] = context.scriptBaseUrl ?? baseUrl
        values["result"] = content
        values.merge(bindings) { _, new in new }
        let session: JsSession
        if let existing = context.scriptSession { session = existing }
        else {
            session = try makeSession(bindings: values, parser: context)
            context.scriptSession = session
        }
        for (key, value) in values { session.context.setObject(session.host.bridge(value), forKeyedSubscript: key as NSString) }
        return try run(rule, in: session)
    }

    public func evaluateScript(_ script: String, bindings: [String: Any] = [:], javaMapBindings: Set<String> = [], context parser: AnalyzeRule? = nil) throws -> Any? {
        let session = try makeSession(bindings: bindings, javaMapBindings: javaMapBindings, parser: parser)
        return Self.nativeValue(try run(script, in: session))
    }

    static func nativeValue(_ value: Any?) -> Any? {
        guard let value = value as? JSValue else { return value }
        if value.isNull || value.isUndefined { return nil }
        if value.isNumber { return value.toDouble() }
        return JavaHost.nativeValue(value.toObject())
    }

    private func run(_ script: String, in session: JsSession) throws -> JSValue? {
        session.context.exception = nil
        let value = session.context.evaluateScript(script)
        try Task.checkCancellation()
        if let exception = session.context.exception { throw JsEngineError.exception(exception.toString()) }
        guard let value, !value.isNull, !value.isUndefined else { return nil }
        return value
    }

    private func makeSession(bindings: [String: Any], javaMapBindings: Set<String> = [], parser: AnalyzeRule? = nil, url: Bool = false) throws -> JsSession {
        guard let context = JSContext() else { throw JsEngineError.unavailable }
        let networkEngine = networkCopy()
        networkEngine.baseUrl = bindings["baseUrl"] as? String ?? parser?.scriptBaseUrl ?? baseUrl
        let host = JavaHost(parser: parser, timeZone: timeZone, logger: logger, network: JavaHostNetwork(engine: networkEngine))
        host.install(in: context)
        var values: [String: Any] = ["result": NSNull(), "src": NSNull(), "baseUrl": baseUrl,
            "source": NSNull(), "book": NSNull(), "chapter": NSNull(), "chapters": NSNull(),
            "title": NSNull(), "nextChapterUrl": NSNull(), "rssArticle": NSNull(), "fromBookInfo": false]
        if url {
            values = ["baseUrl": baseUrl, "page": NSNull(), "key": NSNull(), "speakText": NSNull(),
                      "speakSpeed": NSNull(), "book": NSNull(), "source": NSNull(), "result": NSNull(), "infoMap": NSNull()]
        } else { values.merge(self.bindings) { _, new in new } }
        values.merge(bindings) { _, new in new }
        for (key, value) in values { context.setObject(host.bridge(value), forKeyedSubscript: key as NSString) }
        for key in javaMapBindings {
            guard values[key] is [String: Any] else { throw JsEngineError.exception("Java Map 绑定需要对象：\(key)") }
            let adapt = context.evaluateScript("""
            (function(value) {
                return new Proxy(value, { get: function(target, key) {
                    if (key === 'get') return function(name) {
                        return Object.prototype.hasOwnProperty.call(target, name) ? target[name] : null;
                    };
                    return target[key];
                }});
            })
            """)
            let mapped = adapt?.call(withArguments: [context.objectForKeyedSubscript(key)!])
            context.setObject(mapped, forKeyedSubscript: key as NSString)
        }
        try libraryInitializer?(context)
        if let exception = context.exception { throw JsEngineError.exception(exception.toString()) }
        return JsSession(context: context, host: host)
    }

    func networkCopy() -> JsEngine {
        let copy = JsEngine(baseUrl: baseUrl, bindings: bindings, timeZone: timeZone, logger: logger,
                            httpClient: httpClient, cookieStore: cookieStore, cacheManager: cacheManager,
                            networkSource: networkSource, rateLimiter: rateLimiter, downloadStore: downloadStore)
        copy.libraryInitializer = libraryInitializer
        copy.networkConcurrency = networkConcurrency
        return copy
    }

    func evaluateURLScript(_ script: String, bindings: [String: Any], result: Any? = nil) throws -> Any? {
        var values = bindings
        values["result"] = result ?? NSNull()
        if let extra = bindings["extraParams"] as? [String: String] {
            for (key, value) in extra { values[key] = key == "page" ? Int32(value).map { $0 as Any } ?? value : value }
        }
        return Self.nativeValue(try run(script, in: makeSession(bindings: values, url: true)))
    }

    /// 规格 §10.2：URL 模板的 result 为 null，分页等值由调用方显式绑定。
    public func interpolateURL(_ rule: String, bindings: [String: Any]) throws -> String {
        var values = bindings.filter { ["page", "key", "speakText", "speakSpeed", "book", "source", "infoMap"].contains($0.key) }
        if let extra = bindings["extraParams"] as? [String: String] {
            for (key, value) in extra { values[key] = key == "page" ? Int32(value).map { $0 as Any } ?? value : value }
        }
        values["infoMap"] = bindings["infoMap"] ?? NSNull()
        let session = try makeSession(bindings: values, url: true)
        let analyzer = RuleAnalyzer(rule, code: true)
        return try analyzer.innerRule(start: "{{", end: "}}") { script in
            let value = try self.run(script, in: session)
            if let number = integralScriptNumber(value) { return String(format: "%.0f", number) }
            return value.map { ruleText($0) } ?? ""
        }
    }
}
