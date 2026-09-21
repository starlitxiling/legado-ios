import XCTest
import LegadoCore
@testable import ReaderCheck

final class ReaderTocTests: XCTestCase {
    func testHierarchySearchAndReversalPreserveChapterIdentity() {
        var chapters = (0..<3).map { index in
            var row = BookChapterRow(); row.index = index; row.url = "part\(index).xhtml"; row.title = "Chapter \(index)"; return row
        }
        chapters[0].isVolume = true
        chapters[1].title = "Opening"; chapters[2].title = "Ending"
        let nodes = [LocalBookTocNode(id: 10, parentId: nil, depth: 0, title: "Volume"),
                     LocalBookTocNode(id: 11, parentId: 10, depth: 1, title: "Opening", href: "part1.xhtml"),
                     LocalBookTocNode(id: 12, parentId: 10, depth: 1, title: "Ending", href: "part2.xhtml")]
        let entries = ReaderTocPresentation.entries(chapters: chapters, nodes: nodes)
        XCTAssertEqual(entries.first?.chapterIndex, nil)
        XCTAssertEqual(entries[1].chapterIndex, 1)
        XCTAssertEqual(ReaderTocPresentation.visible(entries, collapsed: ["node:10"], query: "", reversed: false).count, 2)
        let search = ReaderTocPresentation.visible(entries, collapsed: ["node:10"], query: "ending", reversed: false)
        XCTAssertEqual(search.map(\.id), ["node:10", "node:12"])
        XCTAssertEqual(ReaderTocPresentation.visible(entries, collapsed: [], query: "", reversed: true).map(\.id), entries.reversed().map(\.id))
        XCTAssertEqual(ReaderTocPresentation.ancestors(of: "node:12", in: entries), ["node:10"])
    }

    func testPDFOutlineTargetsPhysicalPageAndBookmarkExport() throws {
        var chapter = BookChapterRow(); chapter.index = 2; chapter.start = 20; chapter.end = 30
        XCTAssertTrue(ReaderTocPresentation.entries(chapters: [chapter], nodes: [], includeUnlisted: false).isEmpty)
        let entries = ReaderTocPresentation.entries(chapters: [chapter], nodes: [.init(id: 0, parentId: nil, depth: 0, title: "Section", pageIndex: 24)], includeUnlisted: false)
        XCTAssertEqual(entries.first?.chapterIndex, 2)
        XCTAssertEqual(entries.first?.pageIndex, 24)
        var bookmark = BookmarkRow(); bookmark.chapterName = "First"; bookmark.bookText = "Original"; bookmark.content = "Note"
        let markdown = ReaderTocPresentation.bookmarkMarkdown(name: "Book", author: "Author", bookmarks: [bookmark])
        XCTAssertTrue(markdown.hasPrefix("## Book Author\n\n#### First"))
        XCTAssertTrue(markdown.contains("Original")); XCTAssertTrue(markdown.contains("Note"))
    }
}
