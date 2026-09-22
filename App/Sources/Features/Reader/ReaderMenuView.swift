import SwiftUI
import LegadoCore

struct ReaderMenuView: View {
    let model: ReaderViewModel
    let configuration: ReaderBehaviorConfiguration
    @Bindable var device: ReaderDeviceController
    let automatic: Bool
    let close: () -> Void
    let leave: () -> Void
    let action: (ReaderTapAction) -> Void
    let show: (String) -> Void
    let autoRead: () -> Void
    let night: () -> Void
    @State private var partition = ReaderMenuPartition.load(selection: false)
    @AppStorage("readerMenuConfig") private var menuConfig = ""
    @Environment(\.themeColors) private var colors
    private var menuColor: Color {
        guard configuration.boolean("readBarStyleFollowPage") else { return colors.menu }
        let config = model.settings.configuration
        return (ARGBColor(hex: model.settings.theme == .night ? config.bgStrNight : config.bgStr) ?? ARGBColor(0xFFEEEEEE)).color
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("返回", systemImage: "chevron.left", action: leave).labelStyle(.iconOnly)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.book?.name ?? "阅读器").font(.system(size: 16)).lineLimit(1)
                    if configuration.boolean("showReadTitleAddition") {
                        Text(model.chapterTitle).font(.system(size: configuration.boolean("showReadTitleChapterNameOnly") ? 14 : 12)).lineLimit(1)
                        if model.readerSource != nil {
                            Text(model.currentChapterURL).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                .opacity(configuration.boolean("showReadTitleChapterNameOnly") ? 0 : 1)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("书源") { show("source") }.font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                if model.readerSource?.customButton == true { Button("定制按钮", systemImage: "bolt") { show("custom") }.labelStyle(.iconOnly) }
                Menu {
                    Button("换源") { show("source") }
                    Button("刷新") { Task { await model.refreshContent() } }
                    Button("离线缓存") { show("cache") }
                    Divider()
                    ForEach(partition.primary, id: \.self) { key in item(key) }
                    if !partition.more.isEmpty {
                        Menu("更多操作") { ForEach(partition.more, id: \.self) { key in item(key) } }
                    }
                    Button("书签列表") { show("bookmarks") }
                    Button("批注") { show("highlights") }
                    if model.readerBook.flatMap(LocalBook.fileURL)?.pathExtension.lowercased() == "txt" { Button("设置编码") { show("charset") } }
                    if model.supportsReviews { Button("段评") { show("reviews") } }
                    Button("收起", action: close)
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 36) }.accessibilityLabel("更多")
            }.padding(.horizontal, 14).padding(.vertical, 10).background(menuColor)
            HStack {
                if !device.brightnessOnRight { brightness }
                Button(action: close) { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("收起")
                if device.brightnessOnRight { brightness }
                VStack(spacing: 12) {
                    if model.supportsReviews {
                        Button { show("reviews") } label: { ReaderReviewIcon(settings: model.settings) }
                            .accessibilityLabel("段评").padding(6).background(menuColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                    }
                    floating("全文搜索", icon: "magnifyingglass") { action(.search) }
                    floating(automatic ? "停止自动阅读" : "自动阅读", icon: automatic ? "pause.rectangle" : "play.rectangle", action: autoRead)
                        .contextMenu { Button("自动阅读速度") { show("autoSpeed") } }
                    floating("替换管理", icon: "arrow.2.squarepath") { show("replace") }
                    floating("深色模式", icon: "moon", action: night)
                }.padding(.trailing, 10)
            }.frame(maxHeight: .infinity)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button("上一章") { action(.previousChapter) }.disabled(model.chapterPosition == 0)
                    Slider(value: progress, in: 0...Double(max(1, progressCount - 1)), step: 1)
                        .disabled(progressCount <= 1).accessibilityLabel("阅读进度")
                    Button("下一章") { action(.nextChapter) }.disabled(model.chapterPosition + 1 >= model.availableChapterCount)
                }.font(.system(size: 14))
                HStack {
                    bottom("目录", icon: "list.bullet") { action(.toc) }
                    bottom("朗读", icon: "speaker.wave.2") { show("aloud") }
                    bottom("界面", icon: "textformat.size") { show("interface") }
                    bottom("设置", icon: "gearshape") { show("settings") }
                    if configuration.boolean("showBookMemo") { bottom("备忘录", icon: "note.text") { show("memo") } }
                }
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10).background(menuColor)
        }
        .foregroundStyle(configuration.boolean("readBarStyleFollowPage") ? Color(cgColor: ReaderTypography.bodyColor(model.settings)) : colors.textPrimary)
        .buttonStyle(.plain)
        .onAppear { partition = .load(selection: false) }
        .onChange(of: menuConfig) { _, _ in partition = .load(selection: false) }
    }
    private var progressCount: Int {
        max(1, configuration.string("progressBarBehavior") == "chapter" ? model.availableChapterCount : model.pagination?.pages.count ?? 1)
    }
    private var progress: Binding<Double> {
        Binding(get: { Double(configuration.string("progressBarBehavior") == "chapter" ? model.chapterPosition : model.pageIndex) }, set: { value in
            Task {
                if configuration.string("progressBarBehavior") == "chapter", model.chapters.indices.contains(Int(value)) {
                    await model.goToChapter(model.chapters[Int(value)].index)
                } else { await model.selectPage(Int(value)) }
            }
        })
    }
    @ViewBuilder private var brightness: some View {
        if configuration.boolean("showBrightnessView") {
            VStack(spacing: 6) {
                Button("自动亮度", systemImage: device.automaticBrightness ? "sun.max.fill" : "sun.max") { device.toggleAutomaticBrightness() }
                    .labelStyle(.iconOnly).frame(width: 24, height: 24)
                Slider(value: Binding(get: { device.brightness }, set: { device.setBrightness($0) }), in: 0...1)
                    .frame(width: 180).rotationEffect(.degrees(-90)).frame(width: 28, height: 180).accessibilityLabel("亮度")
                Button("亮度条换边", systemImage: "arrow.left.arrow.right") { device.swapBrightnessSide() }
                    .labelStyle(.iconOnly).frame(width: 24, height: 24)
            }.padding(8).background(menuColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 5)).padding(.leading, 10)
        }
    }
    private func floating(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: icon, action: action).labelStyle(.iconOnly).frame(width: 36, height: 36)
            .background(menuColor.opacity(0.9), in: Circle())
    }
    private func bottom(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 22)); Text(title).font(.system(size: 12)) }
                .frame(maxWidth: .infinity)
        }.accessibilityLabel(title)
    }
    @ViewBuilder private func item(_ key: String) -> some View {
        let title = ReaderMenuPartition.readerActions.first { $0.0 == key }?.1 ?? key
        switch key {
        case "reimportSource": if model.readerSource != nil { Button(title) { show(key) } }
        case "bookmark": Button(title) { action(.bookmark) }
        case "sameTitleRemoved": Button(title) { Task { await model.toggleRemoveSameTitle() } }
        case "reverseContent": Button(title) { Task { await model.reverseContent() } }
        case "updateToc": if model.readerBook.flatMap(LocalBook.fileURL)?.pathExtension.lowercased() == "txt" { Button(title) { show(key) } }
        case "delRubyTag", "delHTag":
            if model.readerBook.flatMap(LocalBook.fileURL)?.pathExtension.lowercased() == "epub" {
                let flag: Int64 = key == "delRubyTag" ? 4 : 2
                Toggle(title, isOn: Binding(get: { (model.readerBook?.readConfig?.delTag ?? 0) & flag != 0 }, set: { enabled in
                    Task {
                        await model.updateReadConfig { config in config.delTag = enabled ? config.delTag | flag : config.delTag & ~flag }
                        await model.refreshContent()
                    }
                }))
            }
        case "reSegment": Toggle(title, isOn: Binding(get: { model.readerBook?.readConfig?.reSegment ?? false }, set: { value in Task { await model.updateReadConfig { $0.reSegment = value } } }))
        case "imageStyle":
            Menu(title) {
                Button("跟随书源") { Task { await model.updateReadConfig { $0.imageStyle = nil } } }
                ForEach(Array(zip(["DEFAULT", "FULL", "TEXT", "SINGLE"], ["默认", "满宽", "文字大小", "独占一页"])), id: \.0) { value, name in
                    Button(name) { Task { await model.updateReadConfig { $0.imageStyle = value; if value == "SINGLE" { $0.pageAnim = 0 } } } }
                }
            }
        case "pageAnim":
            Menu(title) {
                Button("跟随全局") { Task { await model.updateReadConfig { $0.pageAnim = nil } } }
                ForEach(Array(["覆盖", "滑动", "仿真", "滚动", "无动画"].enumerated()), id: \.offset) { index, name in
                    Button(name) { Task { await model.updateReadConfig { $0.pageAnim = index } } }
                }
            }
        case "getProgress": Button(title) { action(.sync) }
        default: Button(title) { show(key) }
        }
    }
}
