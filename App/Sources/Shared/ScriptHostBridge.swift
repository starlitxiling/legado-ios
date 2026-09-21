import SwiftUI
import UIKit
import Observation
import LegadoCore

@Observable
@MainActor
final class ScriptToastCenter {
    static let shared = ScriptToastCenter()
    struct Message: Identifiable {
        let id = UUID()
        let text: String
        let long: Bool
    }
    private(set) var message: Message?

    func show(_ text: String, long: Bool) { message = Message(text: text, long: long) }
    func dismiss(_ id: UUID) {
        if message?.id == id { message = nil }
    }
}

@MainActor
enum ScriptHostBridge {
    static func install(database: AppDatabase) {
        JsPlatformServices.shared.install(deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "",
            toast: { text, long in Task { @MainActor in ScriptToastCenter.shared.show(text, long: long) } },
            readConfiguration: {
                let defaults = UserDefaults.standard
                let file = defaults.bool(forKey: "shareLayout") ? "shareReadConfig.json" : "readConfig.json"
                let retained = try await database.backupConfiguration(named: file)
                return try ScriptHostConfiguration.reading(defaults: defaults, retained: retained)
            })
        JsPlatformServices.shared.installBookActions(refresh: { event in
            Task { @MainActor in NotificationCenter.default.post(name: .init("Legado.script.refresh"), object: event) }
        }, openURL: { address, mime, source in
            guard let url = URL(string: address), url.scheme != nil else { throw JsEngineError.exception("openUrl invalid URL") }
            Task { @MainActor in
                guard !UserDefaults.standard.bool(forKey: "blockSourceNavigation") else { return }
                ScriptOpenCenter.shared.request = .init(url: url, source: source, mime: mime)
            }
        })
        updateAppearance(systemNight: UITraitCollection.current.userInterfaceStyle == .dark)
    }

    static func updateAppearance(systemNight: Bool) {
        let preferences = AppPreferences.shared
        preferences.reload()
        let mode = preferences.string("themeMode")
        let night = mode == "2" || (mode == "0" && systemNight)
        let suffix = night ? "Night" : ""
        let theme = preferences.currentTheme(name: preferences.string("durThemeName" + suffix), night: night)
        do {
            let text = String(decoding: try JSONEncoder().encode(theme), as: UTF8.self)
            JsPlatformServices.shared.updateAppearance(mode: mode, configuration: text)
        } catch { NSLog("Script theme configuration failed: %@", error.localizedDescription) }
    }
}

struct ScriptHostModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private var toast: ScriptToastCenter { .shared }
    private var opener: ScriptOpenCenter { .shared }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = toast.message {
                    Text(message.text)
                        .font(.callout)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 70)
                        .accessibilityIdentifier("scriptToast")
                        .allowsHitTesting(false)
                        .task(id: message.id) {
                            do { try await Task.sleep(for: .milliseconds(message.long ? 3500 : 2000)) }
                            catch { return }
                            toast.dismiss(message.id)
                        }
                }
            }
            .confirmationDialog("打开书源提供的链接", isPresented: Binding(get: { opener.request != nil }, set: { if !$0 { opener.request = nil } }), presenting: opener.request) { request in
                Button("打开") {
                    opener.request = nil
                    if request.url.scheme == "legado" || request.url.scheme == "yuedu" {
                        NotificationCenter.default.post(name: .init("Legado.script.import"), object: request.url)
                    } else {
                        UIApplication.shared.open(request.url) { success in
                            if !success { Task { @MainActor in toast.show("无法打开此链接。", long: true) } }
                        }
                    }
                }
                Button("取消", role: .cancel) { opener.request = nil }
            } message: { request in Text(request.source + "\n" + request.url.absoluteString) }
            .onAppear { ScriptHostBridge.updateAppearance(systemNight: colorScheme == .dark) }
            .onChange(of: colorScheme) { _, scheme in ScriptHostBridge.updateAppearance(systemNight: scheme == .dark) }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                ScriptHostBridge.updateAppearance(systemNight: colorScheme == .dark)
            }
    }
}

@Observable
@MainActor
final class ScriptOpenCenter {
    static let shared = ScriptOpenCenter()
    struct Request { let url: URL; let source: String; let mime: String? }
    var request: Request?
}
