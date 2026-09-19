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
        updateAppearance(systemNight: UITraitCollection.current.userInterfaceStyle == .dark)
    }

    static func updateAppearance(systemNight: Bool) {
        let preferences = AppPreferences.shared
        preferences.reload()
        let mode = preferences.string("themeMode")
        let night = mode == "2" || (mode == "0" && systemNight)
        let suffix = night ? "Night" : ""
        var theme = preferences.currentTheme(name: preferences.string("durThemeName" + suffix), night: night)
        theme.transparentNavBar = preferences.defaults.bool(forKey: "transparentNavBar" + suffix)
        do {
            let text = String(decoding: try JSONEncoder().encode(theme), as: UTF8.self)
            JsPlatformServices.shared.updateAppearance(mode: mode, configuration: text)
        } catch { NSLog("Script theme configuration failed: %@", error.localizedDescription) }
    }
}

struct ScriptHostModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private var toast: ScriptToastCenter { .shared }

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
            .onAppear { ScriptHostBridge.updateAppearance(systemNight: colorScheme == .dark) }
            .onChange(of: colorScheme) { _, scheme in ScriptHostBridge.updateAppearance(systemNight: scheme == .dark) }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                ScriptHostBridge.updateAppearance(systemNight: colorScheme == .dark)
            }
    }
}
