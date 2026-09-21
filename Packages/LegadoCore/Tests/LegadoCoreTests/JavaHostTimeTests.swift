import XCTest
@testable import LegadoCore

final class JavaHostTimeTests: XCTestCase {
    func testDefaultAndCustomLocalFormats() throws {
        let engine = JsEngine(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
        XCTAssertEqual(try engine.evaluateScript("java.timeFormat(0)") as? String, "1970/01/01 08:00")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormat(123,'yyyy-MM-dd HH:mm:ss.SSS')") as? String, "1970-01-01 08:00:00.123")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormatUTC(new Date(0),'yyyyMMdd',0)") as? String, "19700101")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormat(0,'')") as? String, "")
    }

    func testUTCOffsetUsesMillisecondsIncludingFractionalSeconds() throws {
        let engine = JsEngine(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
        XCTAssertEqual(try engine.evaluateScript("java.timeFormatUTC(0,'yyyy/MM/dd HH:mm',0)") as? String, "1970/01/01 00:00")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormatUTC(0,'yyyy/MM/dd HH:mm',19800000)") as? String, "1970/01/01 05:30")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormatUTC(0,'yyyy/MM/dd HH:mm',-18000000)") as? String, "1969/12/31 19:00")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormatUTC(0,'ss.SSS',8)") as? String, "00.008")
    }

    func testJavaPatternDifferencesAndLiterals() throws {
        let engine = JsEngine(timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(try engine.evaluateScript("java.timeFormat(123,'S SS SSS SSSS u uu')") as? String, "123 123 123 0123 4 04")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormat(123,'SSSuu')") as? String, "12304")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormat(-1,'yyyy-MM-dd HH:mm:ss.SSS')") as? String, "1969-12-31 23:59:59.999")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormatUTC(0,\"'at' HH:mm 'o''clock' X XX XXX Z ZZZZ\",19800000)") as? String,
            "at 05:30 o'clock +05 +0530 +05:30 +0530 +0530")
        XCTAssertEqual(try engine.evaluateScript("java.timeFormatUTC(0,'X XX XXX',0)") as? String, "Z Z Z")
    }

    func testInvalidTimeAndPatternsFailExplicitly() throws {
        let engine = JsEngine()
        for script in ["java.timeFormat(NaN)", "java.timeFormat(Infinity)", "java.timeFormat('bad')",
                       "java.timeFormat(0,'Q')", "java.timeFormat(0,\"yyyy 'open\")",
                       "java.timeFormatUTC(0,'XXXX',0)", "java.timeFormatUTC(0,'HH',2147483648)"] {
            XCTAssertThrowsError(try engine.evaluateScript(script), script)
        }
    }
}
