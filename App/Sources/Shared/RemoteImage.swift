import SwiftUI
import UIKit
import LegadoCore

@MainActor struct RemoteImage: View {
    let url: String?
    let origin: String?
    var book: Book? = nil
    var isCover = true
    var isReadRecord = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppContainer.self) private var container
    @State private var model = RemoteImageViewModel()
    @State private var preferences = AppPreferences.shared
    @State private var network = CoverNetworkStatus.shared

    private struct Identity: Hashable {
        let url: String?
        let origin: String?
        let book: Data?
        let isCover: Bool
        let allowNetwork: Bool
        let useDefault: Bool
    }

    var body: some View {
        Group {
            if isCover, !isReadRecord, preferences.boolean("useDefaultCover"), let book {
                ConfiguredCoverView(title: book.name ?? "", author: book.author ?? "", preferences: preferences)
            } else if case let .loaded(data) = model.state, let image = CoverBitmapCache.image(data, maximumMegabytes: preferences.integer("bitmapCacheSize")) {
                Image(uiImage: image).resizable().interpolation(preferences.boolean("antiAlias") ? .high : .none).scaledToFit()
            } else if isReadRecord, model.state != .loading {
                SettingsImage(path: preferences.string(colorScheme == .dark ? "readRecordCoverDark" : "readRecordCover"))
            } else if isCover, let book, model.state != .loading {
                ConfiguredCoverView(title: book.name ?? "", author: book.author ?? "", preferences: preferences)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.08))
                    if model.state == .loading { ProgressView() }
                    else {
                        Image(systemName: isCover ? "book.closed" : "photo")
                            .font(.title).foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(model.state == .failed ? "图片加载失败" : "图片占位")
            }
        }
        .task(id: Identity(url: url, origin: origin, book: identityData, isCover: isCover,
                           allowNetwork: allowNetwork, useDefault: preferences.boolean("useDefaultCover"))) {
            guard isReadRecord || !isCover || !preferences.boolean("useDefaultCover") else { return }
            await model.load(url: url?.isEmpty == false ? url : book?.name) {
                let client = CoverNetworkClient(underlying: container.httpClient, allowed: allowNetwork)
                var address = url ?? ""
                if address.isEmpty, isCover, !isReadRecord, let book {
                    let data = try await container.database.backupConfiguration(named: "coverRule.json")
                    let rule = try data.map { try JSONDecoder().decode(CoverSearchRule.self, from: $0) } ?? .androidDefault
                    address = try await rule.search(book: book, client: client) ?? ""
                }
                if address.hasPrefix("/") { return try Data(contentsOf: URL(fileURLWithPath: address)) }
                if let local = URL(string: address), local.isFileURL { return try Data(contentsOf: local) }
                return try await ImageRepositoryLoader.load(url: address, origin: origin, book: book, isCover: isCover,
                    sources: container.bookSources, cookies: container.cookies, client: client)
            }
        }
    }

    private var allowNetwork: Bool { !isCover || !preferences.boolean("loadCoverOnlyWifi") || network.isWifi }

    private var identityData: Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try? book.map { try encoder.encode($0) }
    }
}
