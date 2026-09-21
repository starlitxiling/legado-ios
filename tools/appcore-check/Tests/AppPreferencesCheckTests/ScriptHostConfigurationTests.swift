import XCTest
@testable import SettingsBackupCheck

final class ScriptHostConfigurationTests: XCTestCase {
    func testSelectedConfigurationPreservesRestoredFieldsAndUsesCurrentSettings() throws {
        let suite = "script-config-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "readStyleSelect")
        let retained = Data(##"[{"name":"first"},{"name":"second","textSize":21,"titleFont":"retained","bgStr":"#ABCDEF"}]"##.utf8)
        func read() throws -> [String: Any] {
            let text = try ScriptHostConfiguration.reading(defaults: defaults, retained: retained)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }
        XCTAssertEqual(try read()["name"] as? String, "second")
        XCTAssertEqual(try read()["textSize"] as? Int, 21)
        XCTAssertEqual(try read()["titleFont"] as? String, "retained")
        defaults.set(200, forKey: "textSize")
        XCTAssertEqual(try read()["textSize"] as? Int, 50)
        XCTAssertEqual(try read()["bgStr"] as? String, "#ABCDEF")
        XCTAssertEqual(try read()["paddingLeft"] as? Int, 16)
    }

    func testSharedConfigurationAndInvalidData() throws {
        let suite = "script-config-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "shareLayout")
        let value = try ScriptHostConfiguration.reading(defaults: defaults, retained: Data(##"{"textSize":26}"##.utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
        XCTAssertEqual(object["textSize"] as? Int, 26)
        XCTAssertThrowsError(try ScriptHostConfiguration.reading(defaults: defaults, retained: Data("[]".utf8)))
        defaults.set(false, forKey: "shareLayout")
        XCTAssertThrowsError(try ScriptHostConfiguration.reading(defaults: defaults, retained: Data("{}".utf8)))
    }
}
