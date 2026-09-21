import Foundation

public final class JsPlatformServices: @unchecked Sendable {
    public static let shared = JsPlatformServices()
    private let lock = NSLock()
    private var deviceID: String
    private var mode: String
    private var theme: String
    private var refresh: ((String) -> Void)?
    private var open: ((String, String?, String) throws -> Void)?
    private var toast: ((String, Bool) -> Void)?
    private var readConfiguration: (() async throws -> String)?

    public init(deviceID: String = "", themeMode: String = "0", themeConfiguration: String = "{}",
                toast: ((String, Bool) -> Void)? = nil,
                readConfiguration: (() async throws -> String)? = nil,
                refresh: ((String) -> Void)? = nil, openURL: ((String, String?, String) throws -> Void)? = nil) {
        self.deviceID = deviceID; mode = themeMode; theme = themeConfiguration
        self.toast = toast; self.readConfiguration = readConfiguration
        self.refresh = refresh; self.open = openURL
    }

    public func install(deviceID: String, toast: @escaping (String, Bool) -> Void,
                        readConfiguration: @escaping () async throws -> String) {
        lock.lock(); defer { lock.unlock() }
        self.deviceID = deviceID; self.toast = toast; self.readConfiguration = readConfiguration
    }

    public func installBookActions(refresh: @escaping (String) -> Void,
                                   openURL: @escaping (String, String?, String) throws -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.refresh = refresh; open = openURL
    }

    func sendRefresh(_ event: String) {
        lock.lock(); let callback = refresh; lock.unlock()
        callback?(event)
    }

    func openURL(_ url: String, mimeType: String?, sourceName: String) throws {
        lock.lock(); let callback = open; lock.unlock()
        guard let callback else { throw JsEngineError.exception("openUrl UI is unavailable") }
        try callback(url, mimeType, sourceName)
    }

    public func updateAppearance(mode: String, configuration: String) {
        lock.lock(); defer { lock.unlock() }
        self.mode = mode; theme = configuration
    }

    func identifier() -> String {
        lock.lock(); defer { lock.unlock() }
        return deviceID
    }

    func appearance() -> (mode: String, configuration: String) {
        lock.lock(); defer { lock.unlock() }
        return (mode, theme)
    }

    func showToast(_ message: String, long: Bool, logger: (String) -> Void) {
        lock.lock()
        let callback = toast
        lock.unlock()
        if let callback { callback(message, long) }
        else { logger(message) }
    }

    func readingConfiguration() throws -> String {
        lock.lock()
        let callback = readConfiguration
        lock.unlock()
        if let callback { return try HostAsyncBridge.wait { try await callback() } }
        return String(decoding: try JSONEncoder().encode(ReadBookConfig()), as: UTF8.self)
    }
}
