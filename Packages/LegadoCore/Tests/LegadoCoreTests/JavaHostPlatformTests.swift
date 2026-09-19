import XCTest
@testable import LegadoCore

final class JavaHostPlatformTests: XCTestCase {
    func testPlatformMethodsAreCallable() throws {
        let engine = JsEngine()
        let result = try engine.evaluateScript("""
        ['toast','longToast','logType','randomUUID','androidId','getReadBookConfig',
         'getReadBookConfigMap','getThemeMode','getThemeConfig','getThemeConfigMap']
            .filter(function(name) { return typeof java[name] !== 'function'; }).join(',')
        """) as? String
        XCTAssertEqual(result, "")
    }

    func testUUIDAndDefaultConfigurationContracts() throws {
        let engine = JsEngine()
        let first = try XCTUnwrap(engine.evaluateScript("java.randomUUID()") as? String)
        let second = try XCTUnwrap(engine.evaluateScript("java.randomUUID()") as? String)
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(first, first.lowercased())
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try engine.evaluateScript("java.getThemeMode()") as? String, "0")
        XCTAssertEqual(try engine.evaluateScript("JSON.parse(java.getReadBookConfig()).textSize") as? Double, 20)
        XCTAssertEqual(try engine.evaluateScript("java.getReadBookConfigMap().get('textSize')") as? Double, 20)
    }

    func testLogTypeUsesKotlinRuntimeNames() throws {
        var logs: [String] = []
        let engine = JsEngine(logger: { logs.append($0) })
        _ = try engine.evaluateScript("[null,true,1,'text',[],{},undefined].forEach(java.logType)")
        XCTAssertEqual(logs, ["null", "java.lang.Boolean", "java.lang.Double", "java.lang.String",
            "org.htmlunit.corejs.javascript.NativeArray", "org.htmlunit.corejs.javascript.NativeObject",
            "org.htmlunit.corejs.javascript.Undefined"])
    }

    func testToastCallbacksDoNotInterruptScriptAndKeepSourceTag() throws {
        var messages: [(String, Bool)] = []
        let services = JsPlatformServices(toast: { messages.append(($0, $1)) })
        let engine = JsEngine(bindings: ["source": ["bookSourceName": "Source"]], platformServices: services)
        XCTAssertEqual(try engine.evaluateScript("java.toast('short');java.longToast('long');'continued'") as? String, "continued")
        XCTAssertEqual(messages.map(\.0), ["Source: short", "Source: long"])
        XCTAssertEqual(messages.map(\.1), [false, true])
    }

    func testInjectedDeviceAndCurrentConfigurationReachURLCopies() throws {
        let services = JsPlatformServices(deviceID: "vendor-id", themeMode: "1",
            themeConfiguration: ##"{"primaryColor":"#112233"}"##,
            readConfiguration: { ##"{"textSize":24}"## })
        let engine = JsEngine(baseUrl: "https://example.invalid", platformServices: services)
        XCTAssertEqual(try engine.evaluateScript("java.androidId()") as? String, "vendor-id")
        XCTAssertEqual(try engine.evaluateScript("java.getReadBookConfigMap().get('textSize')") as? Double, 24)
        services.updateAppearance(mode: "2", configuration: ##"{"primaryColor":"#445566"}"##)
        XCTAssertEqual(try engine.evaluateScript("JSON.parse(java.getThemeConfig()).primaryColor") as? String, "#445566")
        let executor = try AnalyzeUrlExecutor("/{{java.getThemeMode()}}/{{java.getThemeConfigMap().get('primaryColor').slice(1)}}", engine: engine)
        XCTAssertEqual(executor.url, "https://example.invalid/2/445566")
    }

    func testConfigurationErrorsReachScriptCaller() throws {
        let services = JsPlatformServices(readConfiguration: { throw JsEngineError.exception("read configuration unavailable") })
        XCTAssertThrowsError(try JsEngine(platformServices: services).evaluateScript("java.getReadBookConfig()")) {
            XCTAssertTrue($0.localizedDescription.contains("read configuration unavailable"))
        }
    }
}
