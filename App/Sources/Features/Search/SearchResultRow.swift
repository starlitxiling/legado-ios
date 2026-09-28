import SwiftUI
import LegadoCore

struct SearchResultRow: View {
    let book: SearchBook
    var sourceCount = 1
    var isOnShelf = false
    var hasRead = false
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RemoteImage(url: book.coverUrl, origin: book.origin, book: book.toBook())
                .frame(width: 80, height: 110).clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .topLeading) {
                    if isOnShelf || hasRead {
                        Circle().fill(isOnShelf ? Color.green : Color.orange).frame(width: 8, height: 8).padding(3)
                            .accessibilityLabel(isOnShelf ? "已在书架" : "读过")
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(book.name ?? "未命名书籍").font(.body).lineLimit(1).foregroundStyle(colors.textPrimary)
                    Text(String(sourceCount)).font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(colors.accent.opacity(0.12), in: Capsule()).foregroundStyle(colors.accent)
                        .accessibilityLabel("\(sourceCount) 个来源")
                }
                Text(book.author ?? "未知作者").font(.caption).lineLimit(1)
                if let kind = book.kind, !kind.isEmpty { LabelsBar(labels: kind.components(separatedBy: CharacterSet(charactersIn: ",，\n")).filter { !$0.isEmpty }) }
                if let chapter = book.latestChapterTitle, !chapter.isEmpty { Text("最新：" + chapter).font(.caption).lineLimit(1) }
                if let intro = book.intro, !intro.isEmpty { Text(intro).font(.caption).lineLimit(3) }
            }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(colors.textSecondary)
        }.padding(8).contentShape(Rectangle())
    }
}
