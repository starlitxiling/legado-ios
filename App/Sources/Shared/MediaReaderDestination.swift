import SwiftUI
import LegadoCore

struct MediaReaderDestination: View {
    let book: Book
    let container: AppContainer

    var body: some View {
        switch book.mediaKind {
        case .audio: AudioPlayView(book: book, database: container.database, client: container.httpClient)
        case .image:
            if AppPreferences.shared.boolean("showMangaUi") {
                MangaReaderView(book: book, database: container.database, client: container.httpClient)
            } else if let row = try? DiscoveryStorage.row(book, defaults: BookRow()) {
                ReaderView(book: row, database: container.database, client: container.httpClient)
            }
        case .video: VideoPlayView(book: book, database: container.database, client: container.httpClient)
        case .file: WebFileDownloadView(book: book, container: container)
        case .text:
            if let row = try? DiscoveryStorage.row(book, defaults: BookRow()) {
                ReaderView(book: row, database: container.database, client: container.httpClient)
            }
        }
    }
}
