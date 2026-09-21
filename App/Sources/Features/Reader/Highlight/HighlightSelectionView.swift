import SwiftUI
import UIKit
import LegadoCore

struct HighlightSelectionView: View {
    let text: NSAttributedString
    let pageOffset: Int
    var initialSelection: NSRange? = nil
    let model: ReaderViewModel
    let container: AppContainer
    let save: (NSRange, String) -> Void
    let readAloud: (NSRange) -> Void
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var note = ""
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var noteAction = ""
    @State private var showsNote = false
    @State private var route: SelectionRoute?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableReaderText(text: text, initialSelection: initialSelection, action: perform, selectionChanged: { selection = $0 })
                .legadoNavigationTitle("选择正文")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .bottomBar) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                let partition = ReaderMenuPartition.load(selection: true)
                                ForEach(partition.primary.filter { $0 != "processText" }, id: \.self) { key in selectionButton(key) }
                                Menu("更多") {
                                    ForEach(partition.more.filter { $0 != "processText" }, id: \.self) { key in selectionButton(key) }
                                    Button("批注") { perform(selection, "note") }
                                }
                            }.disabled(selection.length == 0)
                        }
                    }
                }
                .onAppear { selection = initialSelection ?? NSRange(location: 0, length: 0) }
                .alert(noteAction == "bookmark" ? "添加书签" : "添加批注", isPresented: $showsNote) {
                    TextField("摘要或批注", text: $note)
                    Button("保存") {
                        if noteAction == "bookmark" { Task { await model.addBookmark(selection: selectedRange, note: note) } }
                        else { save(selectedRange, note) }
                        dismiss()
                    }
                    Button("取消", role: .cancel) {}
                }
                .sheet(item: $route) { destination in
                    switch destination.key {
                    case "replace":
                        NavigationStack {
                            ReplaceRuleEditView(rule: replacement(destination.text), repository: container.replaceRules) { await model.reflow() }
                        }
                    case "dict": ReaderDictionaryView(word: destination.text, database: container.database, client: container.httpClient)
                    case "search": ReaderSearchView(model: model, initialQuery: destination.text, opened: { dismiss() })
                    case "browser": ReaderSelectionBrowser(text: destination.text)
                    case "share": ReaderTextShare(text: destination.text)
                    default: EmptyView()
                    }
                }
        }
    }
    private func selectionButton(_ key: String) -> some View {
        Button(ReaderMenuPartition.textActions.first { $0.0 == key }?.1 ?? key) { perform(selection, key) }
            .accessibilityIdentifier("reader.selection." + key)
    }
    private func replacement(_ text: String) -> ReplaceRuleRow {
        var rule = ReplaceRuleRow()
        rule.name = String(text.prefix(40)); rule.pattern = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        rule.isRegex = false; rule.scope = [model.book?.name, model.book?.origin].compactMap { $0 }.joined(separator: ";")
        return rule
    }
    private func perform(_ range: NSRange, _ key: String) {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return }
        let chapterRange = NSRange(location: pageOffset + range.location, length: range.length)
        let selected = text.attributedSubstring(from: range).string
        switch key {
        case "highlight": save(chapterRange, ""); dismiss()
        case "note", "bookmark": selectedRange = chapterRange; noteAction = key; showsNote = true
        case "aloud": readAloud(chapterRange); dismiss()
        case "copy": UIPasteboard.general.string = selected; dismiss()
        default: route = SelectionRoute(key: key, text: selected)
        }
    }
}

private struct SelectionRoute: Identifiable {
    let key: String
    let text: String
    var id: String { key }
}

private struct SelectableReaderText: UIViewRepresentable {
    let text: NSAttributedString
    let initialSelection: NSRange?
    let action: (NSRange, String) -> Void
    let selectionChanged: (NSRange) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action, selectionChanged: selectionChanged) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true
        view.font = .preferredFont(forTextStyle: .body); view.textColor = .label
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "reader.selectableText"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        // TextKit cannot consume CoreText paragraph attributes; retain the exact string offsets.
        if view.text != text.string { view.text = text.string }
        if !context.coordinator.selectedInitially, let initialSelection {
            context.coordinator.selectedInitially = true
            view.selectedRange = initialSelection
            view.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var selectedInitially = false
        let action: (NSRange, String) -> Void
        let selectionChanged: (NSRange) -> Void
        init(action: @escaping (NSRange, String) -> Void, selectionChanged: @escaping (NSRange) -> Void) {
            self.action = action; self.selectionChanged = selectionChanged
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            DispatchQueue.main.async { [selectionChanged] in selectionChanged(range) }
        }
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return nil }
            let partition = ReaderMenuPartition.load(selection: true)
            func element(_ key: String) -> UIMenuElement {
                let title = ReaderMenuPartition.textActions.first { $0.0 == key }?.1 ?? key
                if key == "processText" { return UIMenu(title: title, children: suggestedActions) }
                if key == "highlight" {
                    return UIMenu(title: title, options: .displayInline, children: [
                        UIAction(title: title) { [action] _ in action(range, key) },
                        UIAction(title: "批注") { [action] _ in action(range, "note") }
                    ])
                }
                return UIAction(title: title) { [action] _ in action(range, key) }
            }
            var items = partition.primary.map(element)
            if !partition.more.isEmpty { items.append(UIMenu(title: "更多", children: partition.more.map(element))) }
            return UIMenu(children: items)
        }
    }
}

private struct ReaderTextShare: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
