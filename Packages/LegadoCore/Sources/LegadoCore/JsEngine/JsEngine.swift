import Foundation
import JavaScriptCore

public enum JsEngineError: Error, CustomStringConvertible, LocalizedError {
    case unavailable
    case exception(String)
    case unimplemented(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "无法创建书源脚本运行环境"
        case .exception(let message): return "书源脚本执行出错：" + Self.userDetail(message)
        case .unimplemented(let method): return "书源脚本调用了尚未支持的方法：\(method)"
        }
    }

    static func userDetail(_ message: String) -> String {
        let prefixes: [(String, String)] = [
            ("Unsupported ", "不支持的"), ("Invalid ", "无效的"), ("Truncated DER", "密钥数据不完整"),
            ("Unknown ", "未知的"), ("Missing ", "缺少"), ("Secure random generation failed", "安全随机数生成失败"),
            ("RSA verification failed", "RSA 验签失败"), ("script context expired", "脚本上下文已失效"),
            ("openUrl UI is unavailable", "当前无法打开网页界面"), ("openUrl ", "打开网页参数错误："),
            ("Request header", "请求头格式错误："), ("Task script is empty", "定时任务脚本为空")
        ]
        var trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        while let wrapper = ["Error: ", "JavaScript: "].first(where: { trimmed.hasPrefix($0) }) {
            trimmed = String(trimmed.dropFirst(wrapper.count))
        }
        guard !trimmed.isEmpty else { return "未知错误" }
        for (prefix, chinese) in prefixes where trimmed.hasPrefix(prefix) {
            let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? chinese : chinese + "（" + rest + "）"
        }
        return trimmed
    }

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
    public weak var variableContext: AnalyzeRule?
    public var baseUrl: String
    public var bindings: [String: Any]
    public var libraryInitializer: ((JSContext) throws -> Void)?
    public var sourceBindingInstaller: ((JSContext) throws -> Void)?
    public var logger: (String) -> Void
    public var platformServices: JsPlatformServices
    public var timeZone: TimeZone
    public var httpClient: any HttpClient
    public var cookieStore: CookieStore
    public var cacheManager: CacheManager
    public var networkSource: AnalyzeUrlExecutor.Source
    public var rateLimiter: ConcurrentRateLimiter
    public var downloadStore: any HostDownloadStore
    public var networkConcurrency: Int = 32
    public var headlessWebView: (any HeadlessWebViewProtocol)?
    public var webViewInteraction: (any WebViewUserInteraction)?
    public var webViewUserAgent: (@Sendable () async throws -> String)?
    public static let sharedCookieStore = CookieStore()

    public init(baseUrl: String = "", bindings: [String: Any] = [:],
                timeZone: TimeZone = .current, logger: @escaping (String) -> Void = { _ in },
                httpClient: any HttpClient = URLSessionHttpClient(), cookieStore: CookieStore = JsEngine.sharedCookieStore,
                cacheManager: CacheManager = .shared, networkSource: AnalyzeUrlExecutor.Source = .init(),
                rateLimiter: ConcurrentRateLimiter = .shared, downloadStore: any HostDownloadStore = DiskHostDownloadStore.shared,
                headlessWebView: (any HeadlessWebViewProtocol)? = nil, webViewInteraction: (any WebViewUserInteraction)? = nil,
                platformServices: JsPlatformServices = .shared) {
        self.platformServices = platformServices
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
        let services = WebViewServices.shared.snapshot()
        self.headlessWebView = headlessWebView ?? services.0
        self.webViewInteraction = webViewInteraction ?? services.1
        self.webViewUserAgent = services.2
    }

    public func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        var values = try context.scriptBindings
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
        if let sourceBindingInstaller { try sourceBindingInstaller(session.context) }
        else { context.sourceAPI?.install(in: session.context, engine: self) }
        freezeEntities(in: session.context)
        return try run(rule, in: session)
    }

    public func evaluateScript(_ script: String, bindings: [String: Any] = [:], javaMapBindings: Set<String> = [], context parser: AnalyzeRule? = nil) throws -> Any? {
        return try autoreleasepool {
            let session = try makeSession(bindings: bindings, javaMapBindings: javaMapBindings, parser: parser)
            return Self.nativeValue(try run(script, in: session))
        }
    }

    static func nativeValue(_ value: Any?) -> Any? {
        guard let value = value as? JSValue else { return value }
        if value.isNull || value.isUndefined { return nil }
        if value.isNumber { return value.toDouble() }
        return JsObject.snapshot(JavaHost.nativeValue(value.toObject()))
    }

    private func run(_ script: String, in session: JsSession) throws -> JSValue? {
        session.context.exception = nil
        defer { session.context.exception = nil }
        let value = session.context.evaluateScript(script)
        try Task.checkCancellation()
        if let exception = session.context.exception { throw JsEngineError.exception(exception.toString()) }
        guard let value, !value.isNull, !value.isUndefined else { return nil }
        return value
    }

    private func makeSession(bindings: [String: Any], javaMapBindings: Set<String> = [], parser: AnalyzeRule? = nil, url: Bool = false) throws -> JsSession {
        let parser = parser ?? variableContext
        guard let context = JSContext() else { throw JsEngineError.unavailable }
        defer { context.exception = nil }
        let networkEngine = networkCopy()
        networkEngine.baseUrl = bindings["baseUrl"] as? String ?? parser?.scriptBaseUrl ?? baseUrl
        let host = JavaHost(parser: parser, timeZone: timeZone, logger: logger, network: JavaHostNetwork(engine: networkEngine),
                            extraParams: url ? bindings["extraParams"] as? [String: String] ?? [:] : [:], platformServices: platformServices)
        host.install(in: context)
        CryptoJSLibrary.install(in: context)
        var values: [String: Any] = ["result": NSNull(), "src": NSNull(), "baseUrl": baseUrl,
            "source": NSNull(), "book": NSNull(), "chapter": NSNull(), "chapters": NSNull(),
            "title": NSNull(), "nextChapterUrl": NSNull(), "rssArticle": NSNull(), "fromBookInfo": false, "isFromBookInfo": false]
        if url {
            values = ["baseUrl": baseUrl, "page": NSNull(), "key": NSNull(), "speakText": NSNull(),
                      "speakSpeed": NSNull(), "book": NSNull(), "source": NSNull(), "result": NSNull(), "infoMap": NSNull()]
        }
        if let parser { values.merge(try parser.scriptBindings) { _, new in new } }
        values.merge(self.bindings) { _, new in new }
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
        if let sourceBindingInstaller { try sourceBindingInstaller(context) }
        else { parser?.sourceAPI?.install(in: context, engine: self) }
        try libraryInitializer?(context)
        freezeEntities(in: context)
        if let exception = context.exception { throw JsEngineError.exception(exception.toString()) }
        return JsSession(context: context, host: host)
    }

    func freezeEntities(in context: JSContext) {
        context.evaluateScript("""
        (function() {
            ['book','chapter'].forEach(function(name) {
                const value=globalThis[name];
                if(value && typeof value==='object' && !Object.isFrozen(value)) {
                    value.getVariable=key=>__legadoEntityVariable(name,key,null,false);
                    value.putVariable=(key,stored)=>__legadoEntityVariable(name,key,stored,true);
                }
            });
            function freeze(value) {
                if (value == null || typeof value !== 'object' || Object.isFrozen(value)) return;
                Object.keys(value).forEach(function(key) { freeze(value[key]); });
                Object.freeze(value);
            }
            [book, source, typeof chapter === 'undefined' ? null : chapter,
             typeof chapters === 'undefined' ? null : chapters,
             typeof rssArticle === 'undefined' ? null : rssArticle].forEach(freeze);
        })();
        """)
    }

    func networkCopy() -> JsEngine {
        let copy = JsEngine(baseUrl: baseUrl, bindings: bindings, timeZone: timeZone, logger: logger,
                            httpClient: httpClient, cookieStore: cookieStore, cacheManager: cacheManager,
                            networkSource: networkSource, rateLimiter: rateLimiter, downloadStore: downloadStore)
        copy.platformServices = platformServices
        copy.variableContext = variableContext
        copy.libraryInitializer = libraryInitializer
        copy.sourceBindingInstaller = sourceBindingInstaller
        copy.networkConcurrency = networkConcurrency
        copy.headlessWebView = headlessWebView
        copy.webViewInteraction = webViewInteraction
        copy.webViewUserAgent = webViewUserAgent
        return copy
    }

    func evaluateURLScript(_ script: String, bindings: [String: Any], result: Any? = nil) throws -> Any? {
        return try autoreleasepool {
            var values = bindings
            values["result"] = result ?? NSNull()
            if let extra = bindings["extraParams"] as? [String: String] {
                for (key, value) in extra { values[key] = key == "page" ? Int32(value).map { $0 as Any } ?? value : value }
            }
            return Self.nativeValue(try run(script, in: makeSession(bindings: values, javaMapBindings: values["infoMap"] is [String: Any] ? ["infoMap"] : [], url: true)))
        }
    }

    /// 规格 §10.2：URL 模板的 result 为 null，分页等值由调用方显式绑定。
    public func interpolateURL(_ rule: String, bindings: [String: Any]) throws -> String {
        return try autoreleasepool {
            var values = bindings.filter { ["page", "key", "speakText", "speakSpeed", "book", "source", "infoMap", "extraParams"].contains($0.key) }
            if let extra = bindings["extraParams"] as? [String: String] {
                for (key, value) in extra { values[key] = key == "page" ? Int32(value).map { $0 as Any } ?? value : value }
            }
            values["infoMap"] = bindings["infoMap"] ?? NSNull()
            let session = try makeSession(bindings: values, javaMapBindings: values["infoMap"] is [String: Any] ? ["infoMap"] : [], url: true)
            let analyzer = RuleAnalyzer(rule, code: true)
            return try analyzer.innerRule(start: "{{", end: "}}") { script in
                let value = try self.run(script, in: session)
                if let number = integralScriptNumber(value) { return String(format: "%.0f", number) }
                return value.map { ruleText($0) } ?? ""
            }
        }
    }
}
