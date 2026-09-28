import SwiftUI
import LegadoCore

struct BookshelfBookView: View {
    let book: BookRow
    let layout: BookshelfLayout
    let preferences: AppPreferences
    let loading: Bool
    @Environment(\.themeColors) private var colors
    @ScaledMetric(relativeTo: .footnote) private var detailIconWidth = 18.0

    private var entity: Book? { try? DiscoveryStorage.book(book) }
    private var metrics: BookshelfBookMetrics {
        .init(total: entity?.simulatedTotalChapterNum() ?? book.totalChapterNum,
              chapter: book.durChapterIndex, position: book.durChapterPos)
    }
    var body: some View {
        Group {
            if layout.columns != nil {
                VStack(spacing: 5) {
                    cover.aspectRatio(3.0 / 4.0, contentMode: .fit)
                    if preferences.integer("showBooknameLayout") == 0 {
                        Text(title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    cover.frame(width: layout.coverWidth, height: layout.coverHeight)
                    VStack(alignment: .leading, spacing: layout == .compact ? 2 : 4) {
                        Text(title).font(.body).foregroundStyle(colors.textPrimary).lineLimit(2)
                        detail(book.author.isEmpty ? "未知作者" : book.author, icon: "person")
                        detail("最近：" + (book.durChapterTitle ?? ""), icon: "clock.arrow.circlepath")
                        detail("最新：" + (book.latestChapterTitle ?? ""), icon: "text.badge.checkmark")
                        if preferences.boolean("showLastUpdateTime"), book.lastCheckTime > 0 {
                            Text(Date(timeIntervalSince1970: Double(book.lastCheckTime) / 1000), format: .dateTime.month().day().hour().minute())
                                .font(.footnote).foregroundStyle(colors.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 6)
            }
        }
        .foregroundStyle(colors.textPrimary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + "，" + book.author)
        .accessibilityValue("未读 \(metrics.unread) 章")
    }

    private var title: String { book.name.isEmpty ? "未命名书籍" : book.name }
    private func detail(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.footnote).frame(width: detailIconWidth)
            Text(text).font(.footnote).lineLimit(1)
        }.foregroundStyle(colors.textSecondary)
    }
    private var cover: some View {
        GeometryReader { geometry in
            RemoteImage(url: book.customCoverUrl ?? book.coverUrl, origin: book.origin, book: entity)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .topTrailing) {
                    if preferences.boolean("showUnread"), metrics.unread > 0 {
                        Text(String(metrics.unread)).font(.caption2).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(colors.error, in: RoundedRectangle(cornerRadius: 3)).padding(2)
                    }
                }
                .overlay {
                    if loading { ProgressView().frame(width: layout.columns == nil ? 26 : 22, height: layout.columns == nil ? 26 : 22) }
                }
                .overlay(alignment: .bottomLeading) {
                    if preferences.bookshelfProgressMode != .hidden, let progress = metrics.progress {
                        ZStack(alignment: .leading) {
                            colors.accent.opacity(0.2)
                            colors.accent.frame(width: geometry.size.width * progress)
                        }.frame(height: preferences.bookshelfProgressMode.thickness)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: layout.columns == nil ? 4 : 12))
        }
    }
}

struct BookshelfFolderView: View {
    let group: BookGroupRow
    let books: [BookRow]
    let count: Int
    let layout: BookshelfLayout
    @Environment(\.themeColors) private var colors
    var body: some View {
        Group {
            if layout.columns != nil {
                VStack(spacing: 5) {
                    cover.aspectRatio(3.0 / 4.0, contentMode: .fit)
                    Text(group.groupName).font(.caption).lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
                }
            } else {
                HStack(spacing: 10) {
                    cover.frame(width: layout.coverWidth, height: layout.coverHeight)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.groupName).font(.body)
                        Text("\(count) 本").font(.footnote).foregroundStyle(colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(colors.textSecondary)
                }.padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 6)
            }
        }.foregroundStyle(colors.textPrimary).contentShape(Rectangle())
    }
    private var cover: some View {
        GeometryReader { geometry in
            ZStack {
                colors.card
                if let cover = group.cover, !cover.isEmpty {
                    RemoteImage(url: cover, origin: nil).frame(width: geometry.size.width, height: geometry.size.height)
                } else if books.isEmpty {
                    Image(systemName: "folder").font(.system(size: 26)).foregroundStyle(colors.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)], spacing: 3) {
                        ForEach(books.prefix(4), id: \.bookUrl) { book in
                            RemoteImage(url: book.customCoverUrl ?? book.coverUrl, origin: book.origin, book: try? DiscoveryStorage.book(book))
                                .frame(height: max(0, (geometry.size.height - 11) / 2)).clipped()
                        }
                    }.padding(4)
                }
            }.clipShape(RoundedRectangle(cornerRadius: layout.columns == nil ? 4 : 12))
        }
    }
}
