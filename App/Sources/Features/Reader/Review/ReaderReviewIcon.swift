import SwiftUI
import WebKit
import UniformTypeIdentifiers
import LegadoCore

struct ReaderReviewIcon: View {
    let settings: ReaderSettings
    var count = 0
    private var svg: String { settings.configuration.reviewIconSvg }
    private var color: Color {
        settings.configuration.reviewIconColor == 0 ? Color(cgColor: ReaderTypography.bodyColor(settings)) :
            ARGBColor(UInt32(truncatingIfNeeded: settings.configuration.reviewIconColor)).color
    }
    var body: some View {
        let height = 24 * Double(min(200, max(50, settings.configuration.reviewIconScale))) / 100
        Group {
            if let document = try? ReaderReviewIconStyle.document(svg, count: count), let ratio = try? ReaderReviewIconStyle.aspectRatio(svg) {
                ReaderSVGImage(svg: document).frame(width: height * ratio, height: height)
                    .colorMultiply(color)
            } else { Image(systemName: "text.bubble").resizable().scaledToFit().foregroundStyle(color).frame(width: height, height: height) }
        }.accessibilityLabel("段评图标").accessibilityIdentifier("reader.review.icon").allowsHitTesting(false)
    }
}

private struct ReaderSVGImage: UIViewRepresentable {
    let svg: String
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false; view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.svg != svg else { return }
        context.coordinator.svg = svg
        let data = Data(svg.utf8).base64EncodedString()
        view.loadHTMLString("""
        <meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>html,body{margin:0;width:100%;height:100%;background:transparent}div{width:100%;height:100%;background:white;mask:url('data:image/svg+xml;base64,\(data)') center/contain no-repeat}</style><div></div>
        """, baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var svg = "" }
}

struct ReaderStyleShareFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .zip) { $0.data }.suggestedFileName("readConfig.zip")
    }
}
