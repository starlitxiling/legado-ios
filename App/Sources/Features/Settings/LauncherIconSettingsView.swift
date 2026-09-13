import SwiftUI
import UIKit

@MainActor private struct SystemLauncherIconClient: LauncherIconClient {
    var supported: Bool { UIApplication.shared.supportsAlternateIcons }
    var currentName: String? { UIApplication.shared.alternateIconName }
    var alternateNames: [String] {
        let key = UIDevice.current.userInterfaceIdiom == .pad ? "CFBundleIcons~ipad" : "CFBundleIcons"
        let icons = (Bundle.main.object(forInfoDictionaryKey: key) ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons")) as? [String: Any]
        return Array((icons?["CFBundleAlternateIcons"] as? [String: Any] ?? [:]).keys)
    }
    func change(to name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
}

@MainActor struct LauncherIconSettingsView: View {
    @State private var model: LauncherIconModel
    init(preferences: AppPreferences) {
        _model = State(initialValue: LauncherIconModel(client: SystemLauncherIconClient()) {
            preferences.set("launcherIcon", .string($0))
        })
    }
    var body: some View {
        Form {
            if model.supported {
                ForEach(["ic_launcher"] + model.available, id: \.self) { value in
                    Button {
                        Task { await model.select(value) }
                    } label: {
                        HStack {
                            Text(value == "ic_launcher" ? "默认图标" : "图标 " + value.replacingOccurrences(of: "launcher", with: ""))
                            Spacer()
                            if model.selected == value { Image(systemName: "checkmark") }
                        }
                    }.disabled(model.changing)
                }
            } else {
                Text("当前安装包未包含备用图标，暂不能切换。")
            }
            if let message = model.message { Text(message) }
        }.navigationTitle("应用图标")
    }
}
