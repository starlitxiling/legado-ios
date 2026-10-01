import SwiftUI
import LegadoCore

struct EInkSettingsView: View {
    let preferences: AppPreferences
    private var controls: PreferenceControls { .init(preferences: preferences) }
    private var settings: EInkSettings { EInkSettings(values: preferences.snapshot) }

    var body: some View {
        Form {
            Section {
                Text("仅在「墨水屏」主题下生效。翻页与界面切换不使用动画，界面去掉半透明与阴影。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("刷新") {
                Stepper(settings.refreshInterval == 0 ? "全刷：关闭" : "全刷：每 \(settings.refreshInterval) 页",
                        value: controls.integer(EInkSettings.refreshIntervalKey), in: 0...50)
                    .accessibilityIdentifier("eink.refreshInterval")
                Text("翻页到设定页数时整屏黑白闪一次，模拟墨水屏清除残影。阅读菜单「更多 → 刷新屏幕」可随时手动全刷。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("纸张与文字") {
                Picker("纸张底色", selection: controls.string(EInkSettings.paperKey)) {
                    ForEach(EInkSettings.Paper.allCases) { Text($0.title).tag($0.rawValue) }
                }.accessibilityIdentifier("eink.paper")
                Picker("字体加深", selection: controls.integer(EInkSettings.textWeightKey)) {
                    Text("标准").tag(0); Text("加深").tag(1); Text("更深").tag(2)
                }.pickerStyle(.segmented).accessibilityIdentifier("eink.textWeight")
                controls.toggle("锐利文字（关闭抗锯齿）", EInkSettings.sharpTextKey)
                controls.toggle("阅读时隐藏状态栏", EInkSettings.hideStatusBarKey)
            }
            Section("图片") {
                Picker("图片处理", selection: controls.string(EInkSettings.imageModeKey)) {
                    ForEach(EInkSettings.ImageMode.allCases) { Text($0.title).tag($0.rawValue) }
                }.accessibilityIdentifier("eink.imageMode")
                if settings.imageMode == .threshold {
                    Stepper("黑白阈值：\(settings.threshold)", value: controls.integer(EInkSettings.thresholdKey), in: 5...250, step: 5)
                }
                Text("作用于封面、正文插图与漫画。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .legadoNavigationTitle("墨水屏设置")
    }
}
