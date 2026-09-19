import SwiftUI

struct LoadingView: View {
    var text = "加载中"
    @Environment(\.themeColors) private var colors
    var body: some View {
        VStack(spacing: 16) {
            Group {
                if colors.isEInk { Image(systemName: "hourglass").font(.system(size: 32)) }
                else { ProgressView().controlSize(.large) }
            }.frame(width: 48, height: 48)
            Text(text).font(.system(size: 14)).foregroundStyle(colors.textSecondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyText: View {
    let text: String
    @Environment(\.themeColors) private var colors
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(colors.textSecondary)
            .multilineTextAlignment(.center).padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
