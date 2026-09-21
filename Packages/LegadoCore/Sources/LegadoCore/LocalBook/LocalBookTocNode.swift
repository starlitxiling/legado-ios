import Foundation

public struct LocalBookTocNode: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let parentId: Int?
    public let depth: Int
    public let title: String
    public let href: String?
    public let pageIndex: Int?

    public init(id: Int, parentId: Int?, depth: Int, title: String, href: String? = nil, pageIndex: Int? = nil) {
        self.id = id; self.parentId = parentId; self.depth = depth
        self.title = title; self.href = href; self.pageIndex = pageIndex
    }
}
