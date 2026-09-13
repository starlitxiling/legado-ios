import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class BookInfoEditModel {
    var name: String
    var author: String
    var cover: String
    var intro: String
    var tag: String
    var variable: String
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private let bookURL: String
    private let repository: BookshelfRepository

    init(book: BookRow, repository: BookshelfRepository) {
        bookURL = book.bookUrl; self.repository = repository
        name = book.name; author = book.author
        cover = book.customCoverUrl ?? ""; intro = book.customIntro ?? ""
        tag = book.customTag ?? ""; variable = book.variable ?? ""
    }

    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            if !variable.isEmpty {
                guard let object = try JSONSerialization.jsonObject(with: Data(variable.utf8)) as? [String: String] else {
                    errorMessage = "自定义字段必须是字符串键值组成的 JSON 对象。"; return false
                }
                _ = object
            }
            try await repository.saveMetadata(bookURL: bookURL, name: name, author: author,
                cover: cover.isEmpty ? nil : cover, intro: intro.isEmpty ? nil : intro,
                tag: tag.isEmpty ? nil : tag, variable: variable.isEmpty ? nil : variable)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
}
