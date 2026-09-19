import SwiftUI

struct LegadoTitleBar<Actions: View, Overflow: View>: ToolbarContent {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var overflow: () -> Overflow
    @Environment(\.themeColors) private var colors

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 18)).lineLimit(1)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).lineLimit(1) }
            }
            .foregroundStyle(colors.onPrimary)
            .accessibilityAddTraits(.isHeader)
            .overlay(alignment: .bottom) {
                if colors.isEInk { Rectangle().fill(colors.divider).frame(height: 0.5).offset(y: 3) }
            }
        }
        if #available(iOS 26, *) {
            trailingItems.sharedBackgroundVisibility(colors.isEInk ? .hidden : .automatic)
        } else { trailingItems }
    }

    private var trailingItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            actions()
            Menu(content: overflow) { Image(systemName: "ellipsis").accessibilityLabel("更多") }
        }
    }
}

struct RefreshProgressBar: View {
    var progress: Double? = nil
    @Environment(\.themeColors) private var colors

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: progress != nil || !colors.allowsAnimation)) { context in
                let value = progress.map(ComponentMetrics.progress)
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                ZStack(alignment: .leading) {
                    colors.accent.opacity(0.15)
                    Rectangle().fill(colors.accent)
                        .frame(width: geometry.size.width * (value ?? 0.35))
                        .offset(x: value == nil && colors.allowsAnimation ? geometry.size.width * (phase * 1.35 - 0.35) : 0)
                }
            }
        }
        .frame(height: 2).clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("加载中")
        .accessibilityValue(progress.map { "\(Int(ComponentMetrics.progress($0) * 100))%" } ?? "")
    }
}

struct CapsuleSearchField: View {
    @Binding var text: String
    var prompt = "搜索"
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(colors.textSecondary)
            TextField(prompt, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).onSubmit { focused = false; onSubmit() }.submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(colors.textSecondary) }
                    .accessibilityLabel("清空")
            }
        }
        .font(.system(size: 14)).padding(.horizontal, 12).frame(height: 30)
        .background(colors.textPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 35))
        .overlay { RoundedRectangle(cornerRadius: 35).stroke(colors.divider, lineWidth: 0.5) }
    }
}

struct SelectActionBar<Actions: View>: View {
    let selectedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void
    @ViewBuilder var actions: () -> Actions
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onSelectAll) {
                Label("全选", systemImage: selectedCount > 0 && selectedCount == totalCount ? "checkmark.square.fill" : "square")
            }.disabled(totalCount <= 0)
            Text("已选 \(max(0, selectedCount))").font(.system(size: 14))
            Spacer(minLength: 0)
            actions()
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        .background(colors.bottomBackground)
        .overlay(alignment: .top) { Rectangle().fill(colors.divider).frame(height: 0.5) }
    }
}
