import SwiftUI
import UIKit
import LegadoCore

@MainActor struct RemoteImage: View {
    let url: String?
    let origin: String?
    var book: Book? = nil
    var isCover = true
    var isReadRecord = false
    var placeholderTitle: String? = nil
    @Environment(\.themeColors) private var themeColors
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppContainer.self) private var container
    @Environment(\.displayScale) private var displayScale
    @State private var size = CGSize.zero
    @State private var bitmap: UIImage?
    @State private var model = RemoteImageViewModel()
    @State private var preferences = AppPreferences.shared
    @State private var network = CoverNetworkStatus.shared

    private struct Identity: Equatable {
        let url: String?
        let origin: String?
        let book: Book?
        let isCover: Bool
        let allowNetwork: Bool
        let useDefault: Bool
        let pixels: Int
        let cacheMegabytes: Int
    }

    var body: some View {
        Group {
            if isCover, !isReadRecord, preferences.boolean("useDefaultCover"), let book {
                ConfiguredCoverView(title: book.name ?? "", author: book.author ?? "", preferences: preferences)
            } else if let bitmap {
                Image(uiImage: bitmap).resizable().interpolation(preferences.boolean("antiAlias") ? .high : .none).scaledToFit()
                    .accessibilityLabel(isCover ? "书籍封面" : "正文图片")
            } else if isReadRecord, model.state != .loading {
                SettingsImage(path: preferences.string(colorScheme == .dark ? "readRecordCoverDark" : "readRecordCover"))
            } else if isCover, let book, model.state != .loading {
                ConfiguredCoverView(title: book.name ?? "", author: book.author ?? "", preferences: preferences)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(themeColors.accent.opacity(0.08))
                    if model.state == .loading { ProgressView() }
                    else {
                        if let placeholderTitle {
                            Text(String(placeholderTitle.prefix(1))).font(.system(size: 28)).foregroundStyle(themeColors.textSecondary)
                        } else {
                            Image(systemName: isCover ? "book.closed" : "photo")
                                .font(.title).foregroundStyle(themeColors.textSecondary)
                        }
                    }
                }
                .accessibilityLabel(model.state == .failed ? "图片加载失败" : "图片占位")
            }
        }
        .background(GeometryReader { geometry in
            Color.clear.onAppear { size = geometry.size }.onChange(of: geometry.size) { _, value in size = value }
        })
        .task(id: Identity(url: url, origin: origin, book: book, isCover: isCover,
                           allowNetwork: allowNetwork, useDefault: preferences.boolean("useDefaultCover"),
                           pixels: maximumPixels, cacheMegabytes: preferences.integer("bitmapCacheSize"))) {
            bitmap = nil
            var cacheKey = url ?? ""
            guard isReadRecord || !isCover || !preferences.boolean("useDefaultCover") else { return }
            await model.load(url: url?.isEmpty == false ? url : book?.name) {
                let client = CoverNetworkClient(underlying: container.httpClient, allowed: allowNetwork)
                var address = url ?? ""
                if address.isEmpty, isCover, !isReadRecord, let book {
                    let data = try await container.database.backupConfiguration(named: "coverRule.json")
                    let rule = try data.map { try JSONDecoder().decode(CoverSearchRule.self, from: $0) } ?? .androidDefault
                    address = try await rule.search(book: book, client: client) ?? ""
                }
                cacheKey = address + "|" + (origin ?? "") + "|" + (book?.bookUrl ?? "")
                let local = address.hasPrefix("/") ? URL(fileURLWithPath: address) : URL(string: address)
                if let local, local.isFileURL {
                    return try await Task.detached(priority: .utility) { try Data(contentsOf: local) }.value
                }
                return try await ImageRepositoryLoader.load(url: address, origin: origin, book: book, isCover: isCover,
                    sources: container.bookSources, cookies: container.cookies, client: client,
                    readerCacheDirectory: URL.applicationSupportDirectory.appendingPathComponent("Legado/ReaderCache", isDirectory: true))
            }
            guard !Task.isCancelled, case let .loaded(data) = model.state else { return }
            let decoded = await CoverBitmapCache.shared.image(data, key: cacheKey, maximumPixels: maximumPixels,
                maximumMegabytes: preferences.integer("bitmapCacheSize"))
            guard !Task.isCancelled else { return }
            bitmap = decoded.map { UIImage(cgImage: $0) }
        }
    }

    private var allowNetwork: Bool { !isCover || !preferences.boolean("loadCoverOnlyWifi") || network.isWifi }

    private var maximumPixels: Int {
        let dimension = max(size.width, size.height) * displayScale
        return dimension > 0 ? min(4096, Int(ceil(dimension / 32)) * 32) : (isCover ? 360 : 2048)
    }
}
