import Foundation

public struct SearchResult: Identifiable {
    public struct Identity: Hashable {
        public let name: String
        public let author: String
        public let rank: Int
    }

    public let id: Identity
    public let book: SearchBook
    public private(set) var sources: [SearchBook]

    public init(book: SearchBook, rank: Int = 3) {
        id = Identity(name: book.name ?? "", author: book.author ?? "", rank: rank)
        self.book = book
        sources = [book]
    }

    public mutating func merge(_ book: SearchBook) {
        guard !sources.contains(where: { $0.origin == book.origin }) else { return }
        sources.append(book)
        sources.sort { ($0.originOrder, $0.origin ?? "") < ($1.originOrder, $1.origin ?? "") }
    }
}

public struct SearchModel {
    public private(set) var results: [SearchResult] = []
    private var query: String?

    public init() {}

    @discardableResult
    public mutating func merge(_ books: [SearchBook], key: String, precision: Bool = false) -> [SearchResult] {
        if query != key { results = []; query = key }
        if precision { results.removeAll { Self.rank($0.book, key: key) == 3 } }
        for book in books {
            let rank = Self.rank(book, key: key)
            if precision && rank == 3 { continue }
            let incoming = SearchResult(book: book, rank: rank)
            if let index = results.firstIndex(where: { $0.id == incoming.id }) { results[index].merge(book) }
            else { results.append(incoming) }
        }
        results = results.enumerated().sorted { left, right in
            let a = Self.rank(left.element.book, key: key), b = Self.rank(right.element.book, key: key)
            if a != b { return a < b }
            if a < 3, left.element.sources.count != right.element.sources.count {
                return left.element.sources.count > right.element.sources.count
            }
            return left.offset < right.offset
        }.map(\.element)
        return results
    }

    private static func rank(_ book: SearchBook, key: String) -> Int {
        if book.name == key || book.author == key { return 0 }
        if book.kind?.contains(key) == true { return 1 }
        if (book.name ?? "").contains(key) || (book.author ?? "").contains(key) { return 2 }
        return 3
    }
}
