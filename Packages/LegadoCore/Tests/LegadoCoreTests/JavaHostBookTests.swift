import XCTest
@testable import LegadoCore

final class JavaHostBookTests: XCTestCase {
    func testSourceIdentityRefreshAndOpenURL() throws {
        var events: [String] = [], opened: [String] = []
        let services = JsPlatformServices(refresh: { events.append($0) }, openURL: { url, mime, source in opened = [url,mime ?? "",source] })
        let engine = JsEngine(platformServices: services)
        let bindings: [String: Any] = ["source": ["bookSourceUrl": "https://source.test", "bookSourceName": "Fixture"]]
        XCTAssertEqual(try engine.evaluateScript("[java.getSource()===source,java.getTag()].join('|')", bindings: bindings) as? String, "true|Fixture")
        _ = try engine.evaluateScript("java.refreshBookInfo();java.refreshBookToc();java.refreshContent();java.openUrl('https://book.test','text/html')", bindings: bindings)
        XCTAssertEqual(events, ["refreshBookInfo","refreshBookToc","refreshContent"])
        XCTAssertEqual(opened, ["https://book.test","text/html","Fixture"])
        XCTAssertThrowsError(try engine.evaluateScript("java.openUrl('https://book.test')"))
        XCTAssertThrowsError(try engine.evaluateScript("java.openUrl('x'.repeat(65536))", bindings: bindings))
    }

    func testLockReentrancySingleFlightAndFailureCleanup() throws {
        let engine = JsEngine(), key = UUID().uuidString
        let bindings: [String: Any] = ["source": ["bookSourceUrl":key]]
        let script = """
        var n=0;
        java.lock('a',function(){ 'use strict'; if(this!==globalThis)throw Error('this'); n++; java.lock('a',()=>n++); });
        java.singleFlight('b',()=>{n++;java.singleFlight('b',()=>n+=100)});
        try { java.lock('c',()=>{throw Error('failure')}); } catch(e) {}
        java.lock('c',()=>n++);
        n
        """
        XCTAssertEqual(try engine.evaluateScript(script, bindings: bindings) as? Double, 4)
        XCTAssertEqual(try engine.evaluateScript("[java.tick('n'),java.tick('n')].join(',')", bindings: bindings) as? String, "0,1")
        XCTAssertEqual(try engine.evaluateScript("java.tick('n')", bindings: bindings) as? Double, 2)
        XCTAssertThrowsError(try engine.evaluateScript("java.tick('n')"))
        for script in ["java.lock('',()=>{})", "java.lock('a',()=>{},-1)", "java.singleFlight('a',()=>{},300001)", "java.lock('a',3)"] {
            XCTAssertThrowsError(try engine.evaluateScript(script, bindings: bindings))
        }
    }

    func testEveryExportedHostMethodReachesAnImplementation() throws {
        let engine = JsEngine(httpClient: ReplayHttpClient(), downloadStore: MemoryHostDownloadStore())
        let result = try engine.evaluateScript("""
        const missing=[];
        Object.keys(java).forEach(name=>{
            try { java[name](); }
            catch(e) { if(e.message === '\\u672a\\u5b9e\\u73b0\\uff1ajava.'+name) missing.push(name); }
        });
        missing.join(',')
        """) as? String
        XCTAssertEqual(result, "")
    }

    func testConcurrentLockSerializesAndTimeoutDoesNotLeakEntry() throws {
        let lock = SourceLock(), entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let done = expectation(description: "holder finished")
        DispatchQueue.global().async {
            defer { done.fulfill() }
            do { try lock.perform(key: "a", singleFlight: false, timeout: 1000) { entered.signal(); release.wait() } }
            catch { XCTFail(String(describing:error)) }
        }
        XCTAssertEqual(entered.wait(timeout: .now()+2), .success)
        XCTAssertThrowsError(try lock.perform(key: "a", singleFlight: false, timeout: 0) { XCTFail("must not enter") })
        release.signal(); wait(for: [done], timeout: 2)
        var called = false
        try lock.perform(key: "a", singleFlight: false, timeout: 0) { called = true }
        XCTAssertTrue(called)
    }
}
