import XCTest
@testable import SettingsBackupCheck

final class LauncherIconTests: XCTestCase {
    @MainActor func testUnavailableResourcesDoNotWritePreference() async {
        let client = FakeIconClient(); client.supported = false
        var saved: [String] = []
        let model = LauncherIconModel(client: client, save: { saved.append($0) })
        await model.select("launcher1")
        XCTAssertTrue(saved.isEmpty); XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNotNil(model.message)
    }
    @MainActor func testSuccessDefaultAndFailureOnlyPersistAppliedIcons() async {
        let client = FakeIconClient()
        var saved: [String] = []
        let model = LauncherIconModel(client: client, save: { saved.append($0) })
        await model.select("launcher1")
        XCTAssertEqual(saved, ["launcher1"])
        client.fail = true
        await model.select("launcher2")
        XCTAssertEqual(saved, ["launcher1"])
        client.fail = false
        await model.select("ic_launcher")
        XCTAssertEqual(saved, ["launcher1", "ic_launcher"])
        XCTAssertNil(client.requests.last!)
        await model.select("unknown")
        XCTAssertEqual(saved.count, 2)
    }
}

@MainActor private final class FakeIconClient: LauncherIconClient {
    var supported = true
    var alternateNames = ["launcher1", "launcher2"]
    var currentName: String?
    var requests: [String?] = []
    var fail = false
    func change(to name: String?) async throws {
        requests.append(name)
        if fail { throw NSError(domain: "IconFixture", code: 1) }
        currentName = name
    }
}
