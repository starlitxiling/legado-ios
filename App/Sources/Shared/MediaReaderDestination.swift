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
        case .video: ContentUnavailableView("暂不支持视频播放", systemImage: "video", description: Text("已识别为视频书源。"))
        case .file: ContentUnavailableView("暂不支持文件下载源", systemImage: "arrow.down.doc", description: Text("已识别为仅提供文件下载的书源。"))
        case .text:
            if let row = try? DiscoveryStorage.row(book, defaults: BookRow()) {
                ReaderView(book: row, database: container.database, client: container.httpClient)
            }
        }
    }
}
