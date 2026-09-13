import SwiftUI
import UIKit

@MainActor struct ThemeSettingsView: View {
    let preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme
    @State private var themeName = ""
    @State private var message: String?
    private var controls: PreferenceControls { .init(preferences: preferences) }

    var body: some View {
        Form {
            Section("主题") {
                NavigationLink("应用图标") { LauncherIconSettingsView(preferences: preferences) }
                Picker("模式", selection: controls.string("themeMode")) {
                    Text("跟随系统").tag("0"); Text("浅色").tag("1"); Text("深色").tag("2"); Text("墨水屏").tag("3")
                }
                Picker("字体缩放", selection: controls.integer("fontScale")) {
                    Text("跟随系统").tag(0)
                    ForEach(8...16, id: \.self) { Text("\($0 * 10)%").tag($0) }
                }
                NavigationLink("主题列表") {
                    List(preferences.themes, id: \.themeName) { theme in
                        Button(theme.themeName) {
                            do { try preferences.applyTheme(theme, systemIsNight: colorScheme == .dark); message = "已应用 \(theme.themeName)" }
                            catch { message = "主题颜色无效" }
                        }
                    }.navigationTitle("主题列表")
                }
                controls.text("主题名称", "durThemeName")
                TextField("保存名称", text: $themeName)
                Button("保存日间主题") { preferences.saveTheme(name: themeName, night: false) }
                Button("保存夜间主题") { preferences.saveTheme(name: themeName, night: true) }
                if let message { Text(message) }
            }
            colors(night: false)
            colors(night: true)
            Section {
                NavigationLink("欢迎页") { WelcomeSettingsView(preferences: preferences) }
                NavigationLink("封面设置") { CoverSettingsView(preferences: preferences) }
            }
        }.navigationTitle("主题设置")
    }

    private func colors(night: Bool) -> some View {
        let suffix = night ? "Night" : ""
        return Section(night ? "夜间配色" : "日间配色") {
            color("主色", "colorPrimary" + suffix)
            color("强调色", "colorAccent" + suffix)
            color("背景色", "colorBackground" + suffix)
            color("底栏背景", "colorBottomBackground" + suffix)
            controls.text("背景图片 URL 或本地路径", "backgroundImage" + suffix)
            CoverResourcePicker(title: "导入背景图片", key: "backgroundImage" + suffix, directory: "bg", preferences: preferences)
            controls.number("背景模糊", "backgroundImage" + suffix + "Blurring", range: 0...100)
        }
    }

    private func color(_ title: String, _ key: String) -> some View {
        ColorPicker(title, selection: Binding(get: { Theme.color(preferences.integer(key)) }, set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            func byte(_ component: CGFloat) -> UInt32 { UInt32(max(0, min(1, component)) * 255) }
            let value = byte(alpha) << 24 | byte(red) << 16 | byte(green) << 8 | byte(blue)
            preferences.set(key, .int(Int32(bitPattern: value)))
        }), supportsOpacity: false)
    }
}

@MainActor struct WelcomeSettingsView: View {
    let preferences: AppPreferences
    private var controls: PreferenceControls { .init(preferences: preferences) }
    var body: some View {
        Form {
            controls.toggle("自定义欢迎页", "customWelcome")
            controls.number("显示时长（毫秒）", "welcomeShowTime", range: 0...800)
            ForEach([false, true], id: \.self) { night in
                let suffix = night ? "Dark" : ""
                Section(night ? "夜间" : "日间") {
                    controls.text("背景图片 URL 或路径", "welcomeImagePath" + suffix)
                    controls.toggle("显示文字", "welcomeShowText" + suffix)
                    controls.toggle("显示图标", "welcomeShowIcon" + suffix)
                }
            }
        }.navigationTitle("欢迎页")
    }
}

@MainActor struct CoverSettingsView: View {
    let preferences: AppPreferences
    @Environment(AppContainer.self) private var container
    private var controls: PreferenceControls { .init(preferences: preferences) }
    var body: some View {
        Form {
            Section("默认封面") {
                controls.toggle("始终使用默认封面", "useDefaultCover")
                controls.toggle("仅 Wi-Fi 加载封面", "loadCoverOnlyWifi")
                controls.text("日间封面路径", "defaultCover")
                controls.text("夜间封面路径", "defaultCoverDark")
                controls.text("阅读记录日间封面路径", "readRecordCover")
                controls.text("阅读记录夜间封面路径", "readRecordCoverDark")
                ForEach(["defaultCover", "defaultCoverDark", "readRecordCover", "readRecordCoverDark"], id: \.self) { key in
                    CoverResourcePicker(title: ["defaultCover": "导入日间封面", "defaultCoverDark": "导入夜间封面", "readRecordCover": "导入阅读记录日间封面", "readRecordCoverDark": "导入阅读记录夜间封面"][key] ?? "导入封面", key: key, directory: "covers", preferences: preferences)
                }
                NavigationLink("封面规则") { CoverRuleSettingsView(database: container.database) }
                NavigationLink("阅读记录") { ReadRecordCoversView() }
                controls.toggle("日间显示书名", "coverShowName")
                controls.toggle("日间显示作者", "coverShowAuthor")
                controls.toggle("夜间显示书名", "coverShowNameN")
                controls.toggle("夜间显示作者", "coverShowAuthorN")
            }
            Section("封面文字") {
                controls.toggle("横排标题", "coverHorizontal")
                controls.toggle("标题字号自适应", "coverTitleAdaptive")
                controls.toggle("保留标题标点", "coverKeepPunctuation")
                controls.text("字体文件路径或 PostScript 名", "coverFont")
                CoverResourcePicker(title: "导入封面字体", key: "coverFont", directory: "fonts", preferences: preferences)
                controls.toggle("自定义字号比例", "coverCustomFontSize")
                controls.number("大封面标题 %", "coverTitleLargeSize", range: 50...200)
                controls.number("小封面标题 %", "coverTitleSmallSize", range: 50...200)
                controls.number("大封面作者 %", "coverAuthorLargeSize", range: 50...200)
                controls.number("小封面作者 %", "coverAuthorSmallSize", range: 50...200)
            }
        }.navigationTitle("封面设置")
    }
}
