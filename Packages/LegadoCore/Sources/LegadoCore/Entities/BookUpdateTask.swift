import Foundation
import CryptoKit

public enum BookUpdateTask {
    public static func build(book: Book, name: String) throws -> AutoTaskRule {
        let action: [String: Any] = ["type": "refreshToc", "bookUrl": book.bookUrl ?? "", "bookName": book.name ?? "",
            "bookAuthor": book.author ?? "", "generatedBy": "bookUpdate", "respectCanUpdate": true,
            "notify": ["enable": true, "minCount": 1], "cache": ["enable": false]]
        var task = AutoTaskRule()
        task.id = identifier(book.bookUrl ?? ""); task.name = name
        task.script = "(" + String(decoding: try JSONSerialization.data(withJSONObject: action, options: .sortedKeys), as: UTF8.self) + ")"
        return task
    }

    public static func find(book: Book, tasks: [AutoTaskRule]) -> AutoTaskRule? {
        if let task = tasks.first(where: { $0.id == identifier(book.bookUrl ?? "") }) { return task }
        let matching = tasks.filter { task in
            guard task.id.hasPrefix("book_update:") else { return false }
            var script = task.script.trimmingCharacters(in: .whitespacesAndNewlines)
            if script.lowercased().hasPrefix("@js:") { script = String(script.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines) }
            if script.lowercased().hasPrefix("<js>"), script.lowercased().hasSuffix("</js>") {
                script = String(script.dropFirst(4).dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard script.hasPrefix("("), script.hasSuffix(")"),
                  let action = try? JSONSerialization.jsonObject(with: Data(script.dropFirst().dropLast().utf8)) as? [String: Any] else { return false }
            return action["generatedBy"] as? String == "bookUpdate" && action["bookName"] as? String == book.name
                && (action["bookAuthor"] as? String ?? "") == (book.author ?? "")
        }
        return matching.count == 1 ? matching[0] : nil
    }

    private static func identifier(_ url: String) -> String {
        let hash = Insecure.MD5.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return "book_update:" + hash.dropFirst(8).prefix(16)
    }
}
