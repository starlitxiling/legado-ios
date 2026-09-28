import XCTest
@testable import SettingsBackupCheck

@MainActor
final class ForegroundAutoTaskTests: XCTestCase {
    func testForegroundRestartAndDisableCancelWithoutDuplicateLoops() async {
        let first = expectation(description: "first run")
        let second = expectation(description: "foreground restart")
        var runs = 0
        let loop = ForegroundAutoTaskLoop()
        let operation = {
            runs += 1
            if runs == 1 { first.fulfill() }
            if runs == 2 { second.fulfill() }
        }
        loop.update(active: false, enabled: true, operation: operation)
        XCTAssertEqual(runs, 0)
        loop.update(active: true, enabled: true, operation: operation)
        await fulfillment(of: [first], timeout: 3)
        loop.update(active: true, enabled: true, operation: operation)
        loop.update(active: false, enabled: true, operation: operation)
        await loop.waitUntilStopped()
        XCTAssertEqual(runs, 1)
        loop.update(active: true, enabled: true, operation: operation)
        await fulfillment(of: [second], timeout: 3)
        loop.update(active: true, enabled: false, operation: operation)
        await loop.waitUntilStopped()
        XCTAssertEqual(runs, 2)
    }

    func testLocalNetworkPurposeIsDeclared() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("App/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let purpose = try XCTUnwrap(plist["NSLocalNetworkUsageDescription"] as? String)
        XCTAssertTrue(purpose.contains("Web")); XCTAssertTrue(purpose.contains("书架"))
    }
}
