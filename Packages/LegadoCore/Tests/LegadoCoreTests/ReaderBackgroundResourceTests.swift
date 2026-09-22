import XCTest
@testable import LegadoCore

final class ReaderBackgroundResourceTests: XCTestCase {
    func testEveryAndroidBackgroundIsBundled() throws {
        XCTAssertEqual(ReaderBackgroundResources.names.count, 14)
        XCTAssertEqual(Set(ReaderBackgroundResources.names).count, 14)
        for name in ReaderBackgroundResources.names {
            let url = try XCTUnwrap(ReaderBackgroundResources.url(named: name))
            XCTAssertTrue(try Data(contentsOf: url).starts(with: [255, 216]), name)
        }
        XCTAssertNil(ReaderBackgroundResources.url(named: "../护眼漫绿.jpg"))
        XCTAssertNil(ReaderBackgroundResources.url(named: "missing.jpg"))
    }
}
