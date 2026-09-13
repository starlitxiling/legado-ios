import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct SourceJSONFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("legado-sources.json")
    }
}

struct SourceJSONShareView: View {
    let text: String
    @State private var qr: CGImage?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            ShareLink(item: SourceJSONFile(data: Data(text.utf8)), preview: SharePreview("书源 JSON")) {
                Label("分享 JSON 文件", systemImage: "square.and.arrow.up")
            }
            if let qr {
                Image(decorative: qr, scale: 1).interpolation(.none).resizable().scaledToFit()
                    .padding(20).background(.white).frame(maxWidth: 360, maxHeight: 360)
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }
        .padding().navigationTitle("导出与分享")
        .task {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(text.utf8); filter.correctionLevel = "L"
            guard let output = filter.outputImage,
                  let image = CIContext().createCGImage(output, from: output.extent) else {
                error = "内容过长，无法生成二维码，请使用 JSON 文件分享。"; return
            }
            qr = image
        }
    }
}
