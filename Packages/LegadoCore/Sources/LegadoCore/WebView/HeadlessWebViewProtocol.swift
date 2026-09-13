import Foundation

public enum HeadlessWebViewError: Error, Equatable, CustomStringConvertible {
    case unavailable, notForeground, timedOut, mainThread, invalidRequest, interactionBusy

    public var description: String {
        switch self {
        case .unavailable: return "webView 服务不可用"
        case .notForeground: return "webView 仅可在前台运行"
        case .timedOut: return "webView 加载超时"
        case .mainThread: return "webView 同步规则必须在后台线程执行"
        case .invalidRequest: return "webView 请求参数无效"
        case .interactionBusy: return "webView 已有等待中的用户交互"
        }
    }
}

public struct HeadlessWebViewRequest: Sendable {
    public var url: String?
    public var html: String?
    public var headers: [String: String]
    public var cookies: String
    public var javaScript: String?
    /// 与 Kotlin 一致，以毫秒计。
    public var delayTime: Int64
    public var sourceRegex: String?
    public var overrideUrlRegex: String?
    /// 总预算以秒计，包括排队时间。
    public var timeout: TimeInterval
    public var cacheFirst: Bool
    public var result: String?
    public var cookieStore: CookieStore?
    public var tag: String?
    public var cookieSession: (any WebViewCookieSession)?

    public init(url: String? = nil, html: String? = nil, headers: [String: String] = [:], cookies: String = "",
                javaScript: String? = nil, delayTime: Int64 = 0, sourceRegex: String? = nil,
                overrideUrlRegex: String? = nil, timeout: TimeInterval = 60, cacheFirst: Bool = false,
                result: String? = nil, cookieStore: CookieStore? = nil, tag: String? = nil,
                cookieSession: (any WebViewCookieSession)? = nil) {
        self.url = url; self.html = html; self.headers = headers; self.cookies = cookies
        self.javaScript = javaScript; self.delayTime = delayTime; self.sourceRegex = sourceRegex
        self.overrideUrlRegex = overrideUrlRegex; self.timeout = timeout; self.cacheFirst = cacheFirst
        self.result = result; self.cookieStore = cookieStore; self.tag = tag
        self.cookieSession = cookieSession
    }

    public func saveCookies(url: String, cookie: String) async throws {
        if let cookieSession {
            let merged = try await cookieSession.saveWebViewCookies(url: url, cookie: cookie)
            await cookieStore?.setCookie(url: url, cookie: merged)
        } else {
            await cookieStore?.replaceCookie(url: url, cookie: cookie)
        }
    }

    func persistCookies(responseURL: String) async throws {
        guard let cookieStore else { return }
        for key in Set([responseURL, tag ?? url ?? responseURL]) {
            try await saveCookies(url: key, cookie: cookieStore.getCookie(url: key))
        }
    }
}

public protocol WebViewCookieSession: Sendable {
    func saveWebViewCookies(url: String, cookie: String) async throws -> String
}

/// 实现必须响应 Task 取消，并在返回前释放 WebView 和相关回调。
public protocol HeadlessWebViewProtocol: Sendable {
    func load(_ request: HeadlessWebViewRequest) async throws -> StrResponse
}

public protocol WebViewUserInteraction: Sendable {
    func getVerificationCode(_ request: HeadlessWebViewRequest) async throws -> String
    func startBrowser(_ request: HeadlessWebViewRequest, title: String) async throws
    func startBrowserAwait(_ request: HeadlessWebViewRequest, title: String) async throws -> StrResponse
}

/// App 在构造规则引擎之前安装一次；每个引擎保存独立快照，测试可直接注入。
public final class WebViewServices: @unchecked Sendable {
    public static let shared = WebViewServices()
    private let lock = NSLock()
    private var loader: (any HeadlessWebViewProtocol)?
    private var interaction: (any WebViewUserInteraction)?
    private var userAgent: (@Sendable () async throws -> String)?
    public func install(loader: any HeadlessWebViewProtocol, interaction: any WebViewUserInteraction,
                        userAgent: (@Sendable () async throws -> String)? = nil) {
        lock.lock(); defer { lock.unlock() }
        self.loader = loader; self.interaction = interaction
        self.userAgent = userAgent
    }
    func snapshot() -> ((any HeadlessWebViewProtocol)?, (any WebViewUserInteraction)?, (@Sendable () async throws -> String)?) {
        lock.lock(); defer { lock.unlock() }
        return (loader, interaction, userAgent)
    }
}

public actor HeadlessWebViewScheduler: HeadlessWebViewProtocol {
    private let loader: any HeadlessWebViewProtocol
    private let maximum: Int
    private let isForeground: @Sendable () async -> Bool
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var active = 0
    private var queue: [(UUID, CheckedContinuation<Void, Error>)] = []

    public init(loader: any HeadlessWebViewProtocol, maximumConcurrentLoads: Int = 2,
                isForeground: @escaping @Sendable () async -> Bool,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
                    try await Task.sleep(for: .seconds($0))
                }) {
        self.loader = loader; maximum = max(1, maximumConcurrentLoads)
        self.isForeground = isForeground; self.sleep = sleep
    }

    public func load(_ request: HeadlessWebViewRequest) async throws -> StrResponse {
        guard request.timeout.isFinite, request.timeout > 0, request.delayTime >= 0 else {
            throw HeadlessWebViewError.invalidRequest
        }
        try Task.checkCancellation()
        guard await isForeground() else { throw HeadlessWebViewError.notForeground }
        return try await withThrowingTaskGroup(of: StrResponse.self) { group in
            group.addTask { try await self.perform(request) }
            group.addTask { [sleep] in
                try await sleep(request.timeout)
                try Task.checkCancellation()
                throw HeadlessWebViewError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func perform(_ request: HeadlessWebViewRequest) async throws -> StrResponse {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                if active < maximum { active += 1; continuation.resume() }
                else { queue.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancelQueued(id) } }
        defer { release() }
        try Task.checkCancellation()
        guard await isForeground() else { throw HeadlessWebViewError.notForeground }
        return try await loader.load(request)
    }

    private func cancelQueued(_ id: UUID) {
        guard let index = queue.firstIndex(where: { $0.0 == id }) else { return }
        queue.remove(at: index).1.resume(throwing: CancellationError())
    }

    private func release() {
        if queue.isEmpty { active -= 1 }
        else { queue.removeFirst().1.resume() }
    }
}
