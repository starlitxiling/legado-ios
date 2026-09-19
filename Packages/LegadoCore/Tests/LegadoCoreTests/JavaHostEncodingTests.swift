import XCTest
@testable import LegadoCore

final class JavaHostEncodingTests: XCTestCase {
    func testByteArrayBridgeAcceptsTypedAndSignedJavaArrays() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("Array.from(java.strToBytes('A\\u00e9')).join(',')") as? String, "65,195,169")
        XCTAssertEqual(try engine.evaluateScript("java.strToBytes('A') instanceof Uint8Array") as? Bool, true)
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr(new Uint8Array([65,195,169]))") as? String, "A\u{00e9}")
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr([65,-61,-87])") as? String, "A\u{00e9}")
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr([])") as? String, "")
        XCTAssertThrowsError(try engine.evaluateScript("java.bytesToStr([256])"))
    }

    func testCharacterEncodingOverloadsAndUTF16BOM() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("Array.from(java.strToBytes('A','UTF-16')).join(',')") as? String, "254,255,0,65")
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr([0,65],'UTF-16')") as? String, "A")
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr([255,254,65,0],'UTF-16')") as? String, "A")
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr(java.strToBytes('\\u4e2d\\u6587','GBK'),'GBK')") as? String, "\u{4e2d}\u{6587}")
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr([255])") as? String, "\u{fffd}")
        XCTAssertEqual(try engine.evaluateScript("java.strToBytes('','UTF-16').length") as? Double, 0)
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr([65,255],'ASCII')") as? String, "A\u{fffd}")
        XCTAssertEqual(try engine.evaluateScript("Array.from(java.strToBytes('\\u00e9','ASCII')).join(',')") as? String, "63")
        XCTAssertThrowsError(try engine.evaluateScript("java.strToBytes('x','unsupported')"))
    }

    func testBase64AndHexVectors() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("Array.from(java.base64DecodeToByteArray('AP+A')).join(',')") as? String, "0,255,128")
        XCTAssertEqual(try engine.evaluateScript("Array.from(java.base64DecodeToByteArray('-_8',8)).join(',')") as? String, "251,255")
        XCTAssertNil(try engine.evaluateScript("java.base64DecodeToByteArray('  ')"))
        XCTAssertNil(try engine.evaluateScript("java.base64DecodeToByteArray(null)"))
        XCTAssertEqual(try engine.evaluateScript("Array.from(java.hexDecodeToByteArray('fF 0')).join(',')") as? String, "15,240")
        XCTAssertEqual(try engine.evaluateScript("java.hexEncodeToString('A\\u00e9')") as? String, "41c3a9")
        XCTAssertEqual(try engine.evaluateScript("Array.from(java.hexDecodeToByteArray('\\uff26\\uff26')).join(',')") as? String, "255")
        XCTAssertNil(try engine.evaluateScript("java.hexDecodeToByteArray('')"))
        XCTAssertEqual(try engine.evaluateScript("java.hexDecodeToByteArray(' ').length") as? Double, 0)
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr(java.base64DecodeToByteArray('Y!Q=='))") as? String, "a")
        XCTAssertThrowsError(try engine.evaluateScript("java.base64DecodeToByteArray('YQ=')"))
        XCTAssertThrowsError(try engine.evaluateScript("java.hexDecodeToByteArray('gg')"))
    }

    func testFormDecodingIsInverseOfHostEncoding() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("java.decodeURI('a+b%2Bc%3D%26')") as? String, "a b+c=&")
        XCTAssertEqual(try engine.evaluateScript("java.decodeURI(java.encodeURI('\\u4e2d\\u6587','GBK'),'GBK')") as? String, "\u{4e2d}\u{6587}")
        XCTAssertThrowsError(try engine.evaluateScript("java.decodeURI('%Q0')"))
    }

    func testHTMLFormattingAndRelativeImageURL() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("java.htmlFormat('<p>A</p><img src=\"cover.png\">','https://example.invalid/book/')") as? String,
            "\u{3000}\u{3000}\u{3000}\u{3000}A\n\u{3000}\u{3000}<img src=\"https://example.invalid/book/cover.png\">")
        XCTAssertEqual(try engine.evaluateScript("java.htmlFormat('plain')") as? String, "plain")
    }

    func testURLObjectUsesJavaQueryMapRules() throws {
        let engine = JsEngine()
        let result = try engine.evaluateScript("""
        var url=java.toURL('../a%20b?x=first&x=last+value&flag&a%20b=c%3Dd','https://example.invalid:8443/books/1');
        [url.host,url.origin,url.pathname,url.searchParams.get('x'),url.searchParams.get('flag'),url.searchParams.get('a%20b')].join('|')
        """) as? String
        XCTAssertEqual(result, "example.invalid|https://example.invalid:8443|/a%20b|last value||c=d")
        XCTAssertEqual(try engine.evaluateScript("java.toURL('https://example.invalid').searchParams === null") as? Bool, true)
        XCTAssertThrowsError(try engine.evaluateScript("java.toURL('relative')"))
    }
}
