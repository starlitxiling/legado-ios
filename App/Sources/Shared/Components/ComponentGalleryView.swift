#if DEBUG
import SwiftUI

struct ComponentGalleryView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.themeColors) private var colors
    @State private var query = ""
    @State private var size: Double = 20
    @State private var selected: Set<String> = ["已选"]
    @State private var selectedAll = false
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CapsuleSearchField(text: $query, prompt: "搜索组件") { message = query }
                    HStack {
                        CoverImage(url: nil, title: "阅读").frame(width: 72)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("未读章节"); BadgeView(count: 120) }
                            LabelsBar(labels: ["已选", "连载", "玄幻", "长标签会在窄屏中自动截断并换行"], selected: selected) { label in
                                if !selected.insert(label).inserted { selected.remove(label) }
                            }
                        }
                    }
                    DetailSeekBar(title: "字号", value: $size, range: 12...48)
                    HStack(spacing: 16) {
                        ReadStyleCircle(background: colors.card, foreground: colors.textPrimary, selected: true)
                        ReadStyleCircle(background: colors.primary, foreground: colors.accent)
                        Button("墨水屏") { theme.mode = .eInk }
                        Button("跟随系统") { theme.mode = .system }
                    }
                    Text("进度").font(.system(size: 14))
                    RefreshProgressBar(progress: 0.6)
                    RefreshProgressBar()
                    HStack {
                        LoadingView().frame(height: 100)
                        EmptyText(text: "暂无内容").frame(height: 100)
                    }
                    if !message.isEmpty { Text(message).accessibilityIdentifier("gallery.message") }
                }.padding(16)
            }
            .legadoNavigationTitle("通用组件")
            .toolbar {
                LegadoTitleBar(title: "通用组件", subtitle: "阅读") {
                    Button { message = "刷新完成" } label: { Image(systemName: "arrow.clockwise").accessibilityLabel("刷新") }
                } overflow: {
                    Button("帮助") { message = "组件帮助" }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SelectActionBar(selectedCount: selectedAll ? 3 : 0, totalCount: 3, onSelectAll: { selectedAll.toggle() }) {
                    Button("导出") { message = "导出已选择项目" }.disabled(!selectedAll)
                }
            }
        }
    }
}
#endif
