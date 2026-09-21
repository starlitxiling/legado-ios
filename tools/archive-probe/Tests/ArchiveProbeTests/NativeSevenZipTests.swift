import XCTest
import PLzmaSDK

final class NativeSevenZipTests: XCTestCase {
    func testNativeLZMAAndSolidLZMA2() throws {
        for name in ["lzma.7z", "lzma2-solid.7z"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
            let decoder = try Decoder(stream: InStream(path: Path(url.path)), fileType: .sevenZ)
            XCTAssertTrue(try decoder.open())
            XCTAssertGreaterThan(try decoder.count(), 0)
            for i in 0..<(try decoder.count()) {
                let item = try decoder.item(at: i)
                let output = try OutStream()
                let streams = try ItemOutStreamArray()
                try streams.add(item: item, stream: output)
                XCTAssertTrue(try decoder.extract(itemsToStreams: streams))
                let data = try output.copyContent()
                XCTAssertEqual(UInt64(data.count), item.size)
                XCTAssertFalse(data.isEmpty)
            }
        }
    }

    func testTruncationsThrowWithoutTrapping() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "lzma2-solid.7z", withExtension: nil, subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        for count in 0..<data.count {
            let opened: Bool
            do {
                let decoder = try Decoder(stream: InStream(dataCopy: Data(data.prefix(count))), fileType: .sevenZ)
                opened = try decoder.open()
            } catch { opened = false }
            XCTAssertFalse(opened, "Truncated at \(count)")
        }
    }
}
