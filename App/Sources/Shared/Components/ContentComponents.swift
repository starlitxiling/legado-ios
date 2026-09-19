import SwiftUI
import LegadoCore

struct DetailSeekBar: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).foregroundStyle(colors.textSecondary).monospacedDigit()
            }.font(.system(size: 14))
            Slider(value: $value, in: range, step: step).accessibilityLabel(title).accessibilityValue(format(value))
        }
    }
}

struct LabelsBar: View {
    let labels: [String]
    var selected: Set<String> = []
    var onSelect: ((String) -> Void)? = nil
    @Environment(\.themeColors) private var colors

    var body: some View {
        LabelFlowLayout {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                if let onSelect {
                    Button { onSelect(label) } label: { badge(label) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(label) ? .isSelected : [])
                } else { badge(label) }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).lineLimit(1)
            .foregroundStyle(selected.contains(text) ? colors.accent : colors.textSecondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(colors.accent.opacity(selected.contains(text) ? 0.15 : 0.06), in: RoundedRectangle(cornerRadius: 3))
            .overlay { RoundedRectangle(cornerRadius: 3).stroke(colors.divider, lineWidth: 0.5) }
    }
}

private struct LabelFlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil)) }
        let width = proposedWidth ?? sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, sizes.count - 1)) * 6
        let frames = ComponentMetrics.flowFrames(sizes: sizes, width: width)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = ComponentMetrics.flowFrames(sizes: subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)) }, width: bounds.width)
        for (index, frame) in frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(frame.size))
        }
    }
}

struct CoverImage: View {
    let url: String?
    let title: String
    var origin: String? = nil
    var book: Book? = nil
    var cornerRadius: CGFloat = 12
    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack {
            colors.card
            Text(String(title.prefix(1))).font(.system(size: 28)).foregroundStyle(colors.textSecondary)
            if let url, !url.isEmpty {
                RemoteImage(url: url, origin: origin, book: book, placeholderTitle: title).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay { RoundedRectangle(cornerRadius: cornerRadius).stroke(colors.divider, lineWidth: 0.5) }
        .accessibilityLabel(title)
    }
}

struct BadgeView: View {
    let count: Int
    @Environment(\.themeColors) private var colors
    var body: some View {
        if let text = ComponentMetrics.badgeText(count) {
            Text(text).font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(colors.isEInk ? colors.textPrimary : colors.onAccent)
                .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                .background(colors.isEInk ? colors.background : colors.accent, in: Capsule())
                .overlay { Capsule().stroke(colors.isEInk ? colors.divider : .clear, lineWidth: 0.5) }
                .accessibilityLabel("未读 \(count)")
        }
    }
}

struct ReadStyleCircle: View {
    let background: Color
    let foreground: Color
    var selected = false
    var action: () -> Void = {}
    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: action) {
            Text("阅").font(.system(size: 18)).foregroundStyle(foreground)
                .frame(width: 48, height: 48).background(background, in: Circle())
                .overlay { Circle().stroke(selected ? colors.accent : colors.divider, lineWidth: selected ? 2 : 0.5) }
        }
        .buttonStyle(.plain).accessibilityLabel("阅读配色")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
