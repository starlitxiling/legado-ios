import SwiftUI
import UIKit

struct SourceCodeInput: UIViewRepresentable {
    @Binding var text: String
    let field: String
    let rows: Int
    var onFocus: () -> Void = {}
    static let assists: [(String, String)] = [
        ("@css:", "@css:"),
        ("<js>", "<js></js>"),
        ("{{}}", "{{}}"),
        ("##", "##"),
        ("&&", "&&"),
        ("%%", "%%"),
        ("||", "||"),
        ("//", "//"),
        ("\\", "\\"),
        ("$.", "$."),
        ("@", "@"),
        (":", ":"),
        ("class", "class"),
        ("text", "text"),
        ("href", "href"),
        ("textNodes", "textNodes"),
        ("ownText", "ownText"),
        ("all", "all"),
        ("html", "html"),
        ("[", "["),
        ("]", "]"),
        ("<", "<"),
        (">", ">"),
        ("#", "#"),
        ("!", "!"),
        (".", "."),
        ("+", "+"),
        ("-", "-"),
        ("*", "*"),
        ("/", "/"),
        ("=", "="),
        ("useWebView", ",{\"webView\": true}")
    ]

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.backgroundColor = .secondarySystemGroupedBackground
        view.textColor = .label
        view.autocorrectionType = .no; view.autocapitalizationType = .none
        view.smartQuotesType = .no; view.smartDashesType = .no
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        view.layer.cornerRadius = 5
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        view.accessibilityIdentifier = "source.field." + field
        view.accessibilityLabel = BookSourceEditModel.label(field)
        if context.coordinator.rows != rows {
            context.coordinator.rows = rows
            let accessory = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 36 * max(1, rows)), inputViewStyle: .keyboard)
            let scroll = UIScrollView(frame: accessory.bounds); scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let count = max(1, min(5, rows)), columns = Int(ceil(Double(Self.assists.count) / Double(count)))
            for (index, pair) in Self.assists.enumerated() {
                let button = UIButton(type: .system)
                button.setTitle(pair.0, for: .normal); button.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
                button.frame = CGRect(x: (index / count) * 88, y: (index % count) * 36, width: 86, height: 34)
                button.addAction(UIAction { [weak view] _ in view?.insertText(pair.1) }, for: .touchUpInside)
                scroll.addSubview(button)
            }
            scroll.contentSize = CGSize(width: columns * 88, height: count * 36)
            accessory.addSubview(scroll); view.inputAccessoryView = accessory; view.reloadInputViews()
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SourceCodeInput
        var rows = 0
        init(_ parent: SourceCodeInput) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocus() }
    }
}
