import Foundation
import Observation
import LegadoCore

@MainActor
protocol WebServiceTransport: AnyObject {
    func start(port: UInt16, router: HttpRouter, state: @escaping (WebServiceState) -> Void) throws
    func stop()
}

enum WebServiceState { case ready, networkChanged, failed(String) }

@Observable
@MainActor
final class WebServiceController {
    var portText: String
    private(set) var isRunning = false
    private(set) var isStarting = false
    private(set) var addresses: [String] = []
    private(set) var message: String?
    private(set) var accessToken: String
    @ObservationIgnored private let token: WebServiceToken
    @ObservationIgnored private let saveToken: (String) throws -> Void
    @ObservationIgnored private let router: HttpRouter
    @ObservationIgnored private let transport: any WebServiceTransport
    @ObservationIgnored private let addressProvider: () -> [String]
    @ObservationIgnored private let savePort: (Int) -> Void
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(router: HttpRouter, transport: any WebServiceTransport, port: Int = 1122,
         addresses: @escaping () -> [String], savePort: @escaping (Int) -> Void,
         token: WebServiceToken = WebServiceToken(), saveToken: @escaping (String) throws -> Void = { _ in }) {
        self.router = router; self.transport = transport; portText = String(port)
        addressProvider = addresses; self.savePort = savePort
        self.token = token; self.saveToken = saveToken; accessToken = token.value ?? ""
        if accessToken.isEmpty { resetToken() }
    }

    func resetToken() {
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        do { try saveToken(value); token.set(value); accessToken = value }
        catch { message = error.localizedDescription }
    }

    func observe(background: Notification.Name, foreground: Notification.Name) {
        guard observers.isEmpty else { return }
        observers = [
            NotificationCenter.default.addObserver(forName: background, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterBackground() }
            },
            NotificationCenter.default.addObserver(forName: foreground, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterForeground() }
            }
        ]
    }

    func start() {
        guard isForeground, !isStarting, !isRunning else { return }
        guard let port = UInt16(portText), port > 0 else { message = "端口须为 1–65535"; return }
        let current = UUID(); generation = current
        isStarting = true; message = "正在启动…"
        do {
            try transport.start(port: port, router: router) { [weak self] state in
                guard let self, self.generation == current else { return }
                switch state {
                case .ready:
                    self.isStarting = false; self.isRunning = true
                    self.addresses = self.addressProvider().map { "http://\($0):\(port)" }
                    self.message = self.addresses.isEmpty ? "已启动，当前未找到局域网 IPv4 地址" : "仅在 App 前台运行"
                case .networkChanged:
                    guard self.isRunning else { return }
                    self.addresses = self.addressProvider().map { "http://\($0):\(port)" }
                    self.message = self.addresses.isEmpty ? "当前未找到局域网 IPv4 地址" : "仅在 App 前台运行"
                case .failed(let error):
                    self.stop(); self.message = error
                }
            }
            savePort(Int(port))
        } catch { stop(); message = error.localizedDescription }
    }

    func stop() {
        generation = UUID()
        transport.stop(); isRunning = false; isStarting = false; addresses = []; message = "服务已停止"
    }

    func enterBackground() {
        isForeground = false
        let wasActive = isRunning || isStarting
        if wasActive { stop(); message = "进入后台，Web 服务已停止；返回前台后请手动启动。" }
    }

    func enterForeground() { isForeground = true }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

final class WebServiceToken: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    init(_ value: String? = nil) { stored = value }
    var value: String? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ value: String) { lock.lock(); defer { lock.unlock() }; stored = value }
}
