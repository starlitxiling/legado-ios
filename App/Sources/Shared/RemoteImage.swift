import SwiftUI
import UIKit
import LegadoCore

struct RemoteImage: View {
    let url: String?
    let origin: String?
    var book: Book? = nil
    var isCover = true
    @Environment(AppContainer.self) private var container
    @State private var model = RemoteImageViewModel()

    private struct Identity: Hashable {
        let url: String?
        let origin: String?
        let book: Data?
        let isCover: Bool
    }

    var body: some View {
        Group {
            if case let .loaded(data) = model.state, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
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
        .task(id: Identity(url: url, origin: origin, book: identityData, isCover: isCover)) {
            await model.load(url: url) {
                try await ImageRepositoryLoader.load(url: url ?? "", origin: origin, book: book, isCover: isCover,
                    sources: container.bookSources, cookies: container.cookies, client: container.httpClient)
            }
        }
    }

    private var identityData: Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try? book.map { try encoder.encode($0) }
    }
}
