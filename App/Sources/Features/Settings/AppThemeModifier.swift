import SwiftUI
import UIKit

@MainActor
struct AppThemeModifier: ViewModifier {
    let preferences: AppPreferences
    @Environment(\.themeColors) private var colors
    @State private var showingWelcome = true
    private var night: Bool { colors.isNight }
    private var suffix: String { night ? "Night" : "" }
    private var eink: Bool { colors.isEInk }

    func body(content: Content) -> some View {
        content
            .background {
                colors.background.ignoresSafeArea()
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
                        colors.background.ignoresSafeArea()
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
