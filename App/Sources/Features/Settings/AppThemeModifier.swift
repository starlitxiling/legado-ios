import SwiftUI
import UIKit

@MainActor
struct AppThemeModifier: ViewModifier {
    let preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingWelcome = true
    private var night: Bool {
        preferences.string("themeMode") == "2" || (preferences.string("themeMode") == "0" && colorScheme == .dark)
    }
    private var suffix: String { night ? "Night" : "" }
    private var eink: Bool { preferences.string("themeMode") == "3" }

    func body(content: Content) -> some View {
        content
            .tint(eink ? .black : Theme.color(preferences.integer("colorAccent" + suffix)))
            .toolbarBackground(eink ? .white : Theme.color(preferences.integer("colorPrimary" + suffix)), for: .navigationBar)
            .toolbarBackground(eink ? .white : Theme.color(preferences.integer("colorBottomBackground" + suffix)), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar, .navigationBar)
            .background {
                Theme.color(preferences.integer("colorBackground" + suffix)).ignoresSafeArea()
                if !eink {
                    SettingsImage(path: preferences.string("backgroundImage" + suffix))
                        .blur(radius: Double(max(0, min(100, preferences.integer("backgroundImage" + suffix + "Blurring")))))
                        .ignoresSafeArea()
                }
            }
            .scrollContentBackground(.hidden)
            .font(preferences.integer("fontScale") == 0 ? nil : .system(size: 17 * Double(max(8, min(16, preferences.integer("fontScale")))) / 10))
            .overlay {
                if showingWelcome, preferences.boolean("customWelcome") {
                    ZStack {
                        Theme.color(preferences.integer("colorBackground" + suffix)).ignoresSafeArea()
                        SettingsImage(path: preferences.string(night ? "welcomeImagePathDark" : "welcomeImagePath")).ignoresSafeArea()
                        VStack(spacing: 20) {
                            if preferences.boolean(night ? "welcomeShowIconDark" : "welcomeShowIcon") { Image(systemName: "book.closed").font(.system(size: 64)) }
                            if preferences.boolean(night ? "welcomeShowTextDark" : "welcomeShowText") { Text("阅读，让生活更美好").font(.title2) }
                        }
                    }
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(max(0, min(800, preferences.integer("welcomeShowTime")))))
                showingWelcome = false
            }
    }
}

struct SettingsImage: View {
    let path: String
    var body: some View {
        if path.hasPrefix("https://") || path.hasPrefix("http://") {
            AsyncImage(url: URL(string: path)) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
        } else if let image = UIImage(contentsOfFile: URL(string: path)?.isFileURL == true ? URL(string: path)!.path : path) {
            Image(uiImage: image).resizable().scaledToFill()
        }
    }
}
