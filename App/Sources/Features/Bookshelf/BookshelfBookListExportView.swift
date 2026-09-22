import SwiftUI
import UniformTypeIdentifiers
import LegadoCore

private struct BookshelfBookListFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }.suggestedFileName("books.json")
    }
}

struct BookshelfBookListExportView: View {
    @Environment(\.dismiss) private var dismiss
    let books: [BookRow]
    @State private var data: Data?
    @State private var userError: UserFacingError?
    private var errorMessage: String? { userError?.displayText }

    var body: some View {
        NavigationStack {
            Form {
                Text("共 \(books.count) 本，仅导出书名、作者和简介。")
                if let data {
                    ShareLink(item: BookshelfBookListFile(data: data), preview: SharePreview("书单")) { Label("分享书单文件", systemImage: "square.and.arrow.up") }
                    Text(String(decoding: data, as: UTF8.self)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .legadoNavigationTitle("导出书单")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
            .task {
                do { data = try BookshelfBookList.encode(books) }
                catch { userError = error.presentation(operation: "导出书单", subject: "书单 JSON") }
            }
        }
    }
}
