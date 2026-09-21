import XCTest
@testable import LegadoCore

final class ExploreControlTests: XCTestCase {
    func testControlsDecodeChoicesDefaultsAndDynamicNames() throws {
        let kinds = try ExploreKinds.parse(#"[{"title":"Sort","type":"select","chars":["New",null,"Hot"],"default":"Hot","viewName":"'Order'"},{"title":"Query","type":"text","action":"infoMap.save()"}]"#)
        XCTAssertEqual(kinds[0].chars, ["New", "Hot"])
        XCTAssertEqual(kinds[0].defaultValue, "Hot")
        XCTAssertEqual(kinds[0].viewName, "'Order'")
        XCTAssertEqual(kinds[1].type, "text")
    }

    func testControlActionsShareInfoMapAndSourceVariables() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        let states = SourceStateRepository(database: db)
        var source = BookSource(); source.bookSourceUrl = "https://fixture.test"
        source.exploreUrl = "@js:JSON.stringify([{title:infoMap.get('Sort'),url:'/books'}])"
        let result = try await ExploreKinds.runControl(source: source,
            script: "source.put('seen', infoMap.get('Sort')); infoMap.save(); java.reUiView(); 'Ready'",
            values: ["Sort": "Hot"], client: client, stateRepository: states)
        XCTAssertEqual(result.text, "Ready")
        XCTAssertEqual(result.values["Sort"], "Hot")
        XCTAssertTrue(result.refresh)
        let stored = try await states.load(source: source.bookSourceUrl!)
        XCTAssertEqual(stored["v_seen"], "Hot")
        let kinds = try await ExploreKinds.load(source: source, client: client, stateRepository: states)
        XCTAssertEqual(kinds.first?.title, "Hot")
    }
}
