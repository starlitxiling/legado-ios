import SwiftUI
import UIKit
import CoreImage

@MainActor struct ThemeSettingsView: View {
    let preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.themeColors) private var themeColors
    @State private var themeName = ""
    @State private var message: String?
    private var controls: PreferenceControls { .init(preferences: preferences) }

    var body: some View {
        Form {
            Section {
                NavigationLink("切换图标") { LauncherIconSettingsView(preferences: preferences) }
                NavigationLink("启动界面样式") { WelcomeSettingsView(preferences: preferences) }
                Menu {
                    Button("跟随系统") { preferences.set("fontScale", .int(0)) }
                    ForEach(8...16, id: \.self) { scale in
                        Button("\(scale * 10)%") { preferences.set("fontScale", .int(Int32(scale))) }
                    }
                } label: {
                    HStack {
                        Text("字体大小").foregroundStyle(themeColors.textPrimary)
                        Spacer()
                        Text(preferences.integer("fontScale") == 0 ? "跟随系统" : "\(preferences.integer("fontScale") * 10)%")
                            .foregroundStyle(themeColors.accent)
                    }.contentShape(Rectangle())
                }
                NavigationLink("封面设置") { CoverSettingsView(preferences: preferences) }
                NavigationLink("主题列表") {
                    List(preferences.themes, id: \.themeName) { theme in
                        Button(theme.themeName) {
                            do { try themeStore.apply(theme, systemIsNight: colorScheme == .dark); message = "已应用 \(theme.themeName)" }
                            catch { message = "主题颜色无效" }
                        }
                    }.legadoNavigationTitle("主题列表")
                }
                Toggle("跟随壁纸配色", isOn: Binding(get: { preferences.defaults.bool(forKey: "Legado.followBackgroundColors") }, set: { enabled in
                    preferences.defaults.set(enabled, forKey: "Legado.followBackgroundColors")
                    if enabled { applyBackgroundColors() }
                }))
                Text("iOS 无法读取系统壁纸，此项使用下方导入的背景图片。图片更换时重新提取主色与强调色。").font(.footnote).foregroundStyle(.secondary)
                TextField("保存名称", text: $themeName)
                if let message { Text(message) }
            }
            colors(night: false)
            colors(night: true)
        }.legadoNavigationTitle("主题设置")
            .onChange(of: preferences.string("backgroundImage")) { _, _ in applyBackgroundColors() }
            .onChange(of: preferences.string("backgroundImageNight")) { _, _ in applyBackgroundColors() }
    }

    private func applyBackgroundColors() {
        guard preferences.defaults.bool(forKey: "Legado.followBackgroundColors") else { return }
        var applied = false
        for suffix in ["", "Night"] {
            let path = preferences.string("backgroundImage" + suffix)
            guard !path.isEmpty else { continue }
            let url = path.hasPrefix("file:") ? URL(string: path) : URL(fileURLWithPath: path)
            guard let url, url.isFileURL, let image = CIImage(contentsOf: url),
                  let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)]),
                  let output = filter.outputImage else { message = "请导入有效的本地背景图片后提取配色"; continue }
            var pixel = [UInt8](repeating: 0, count: 4)
            CIContext().render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            let value = Int32(bitPattern: 0xff000000 | UInt32(pixel[0]) << 16 | UInt32(pixel[1]) << 8 | UInt32(pixel[2]))
            preferences.set("colorPrimary" + suffix, .int(value)); preferences.set("colorAccent" + suffix, .int(value))
            applied = true
        }
        if applied { message = "已应用背景图片配色" }
        else { message = "请先导入本地背景图片" }
    }

    private func modeName(_ mode: ThemeMode) -> String {
        switch mode {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        case .eInk: "墨水屏"
        }
    }

    private func saveTheme(night: Bool) {
        do { try themeStore.save(name: themeName, night: night); message = "主题已保存" }
        catch { message = error.localizedDescription }
    }

    private func colors(night: Bool) -> some View {
        let suffix = night ? "Night" : ""
        return Section(night ? "夜间" : "白天") {
            color("主色调", "colorPrimary" + suffix)
            color("强调色", "colorAccent" + suffix)
            color("背景色", "colorBackground" + suffix)
            color("底部操作栏颜色", "colorBottomBackground" + suffix)
            controls.text("背景图片 URL 或本地路径", "backgroundImage" + suffix)
            CoverResourcePicker(title: "导入背景图片", key: "backgroundImage" + suffix, directory: "bg", preferences: preferences)
            controls.number("背景模糊", "backgroundImage" + suffix + "Blurring", range: 0...100)
            Button("保存主题配置") { saveTheme(night: night) }
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
        }.legadoNavigationTitle("欢迎页")
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
        }.legadoNavigationTitle("封面设置")
    }
}
