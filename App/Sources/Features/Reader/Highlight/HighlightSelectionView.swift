import SwiftUI
import UIKit

struct HighlightSelectionView: View {
    let text: NSAttributedString
    let pageOffset: Int
    var initialSelection: NSRange? = nil
    let save: (NSRange, String) -> Void
    let readAloud: (NSRange) -> Void
    @State private var note = ""
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var showsNote = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableReaderText(text: text, initialSelection: initialSelection) { range, action in
                let chapterRange = NSRange(location: pageOffset + range.location, length: range.length)
                switch action {
                case .highlight: save(chapterRange, ""); dismiss()
                case .note: selectedRange = chapterRange; showsNote = true
                case .readAloud: readAloud(chapterRange); dismiss()
                }
            }
            .legadoNavigationTitle("选择正文")
            .toolbar { Button("完成") { dismiss() } }
            .alert("添加批注", isPresented: $showsNote) {
                TextField("批注", text: $note)
                Button("保存") { save(selectedRange, note); dismiss() }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

private enum ReaderSelectionAction { case highlight, note, readAloud }

private struct SelectableReaderText: UIViewRepresentable {
    let text: NSAttributedString
    let initialSelection: NSRange?
    let action: (NSRange, ReaderSelectionAction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        if !view.attributedText.isEqual(to: text) { view.attributedText = text }
        if !context.coordinator.selectedInitially, let initialSelection {
            context.coordinator.selectedInitially = true
            view.selectedRange = initialSelection
            view.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var selectedInitially = false
        let action: (NSRange, ReaderSelectionAction) -> Void
        init(action: @escaping (NSRange, ReaderSelectionAction) -> Void) { self.action = action }
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let additions: [UIMenuElement] = [
                UIAction(title: "高亮") { [action] _ in action(range, .highlight) },
                UIAction(title: "批注") { [action] _ in action(range, .note) },
                UIAction(title: "朗读") { [action] _ in action(range, .readAloud) }
            ]
            return UIMenu(children: additions + suggestedActions)
        }
    }
}
