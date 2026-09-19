import Foundation
import XCTest
@testable import ArchiveProbe

final class ArchiveProbeTests: XCTestCase {
    private let expected = Data(String(repeating: "Synthetic archive probe chapter.\n", count: 100).utf8)

    func testLZMA7zExtraction() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "lzma", withExtension: "7z", subdirectory: "Fixtures"))
        XCTAssertEqual(try ArchiveProbe.read7z(at: url), ["chapter.txt": expected])
    }

    func testLZMA2Solid7zExtraction() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "lzma2-solid", withExtension: "7z", subdirectory: "Fixtures"))
        XCTAssertEqual(try ArchiveProbe.read7z(at: url), ["chapter.txt": expected, "second.txt": Data("Second synthetic chapter.\n".utf8)])
    }

    func testRAR5Extraction() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rar5", withExtension: "rar", subdirectory: "Fixtures"))
        let signature = try Data(contentsOf: url).prefix(8)
        XCTAssertEqual(signature, Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00]))
        XCTAssertEqual(try ArchiveProbe.readRAR(at: url), ["chapter.txt": expected])
    }
}
