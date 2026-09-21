import XCTest
@testable import LegadoCore

final class JavaHostFontTests: XCTestCase {
    func testGlyphQueriesAndReplacement() throws {
        let engine = JsEngine()
        let a = font(code: 65).base64EncodedString(), b = font(code: 66).base64EncodedString()
        XCTAssertEqual(try engine.evaluateScript("""
        var a=java.queryBase64TTF('\(a)'), b=java.queryTTF(java.base64DecodeToByteArray('\(b)'));
        [a.getGlyfIdByUnicode(65),a.getGlyfByUnicode(65),a.getUnicodeByGlyf('10,20'),
         a.getGlyfById(0),a.isBlankUnicode(32),java.replaceFont('A X',a,b),java.replaceFont('A X',a,b,true)].join(';')
        """) as? String, "1;10,20;65;;true;B X;B ")
        XCTAssertEqual(try engine.evaluateScript("java.replaceFont('A',null,null)") as? String, "A")
        XCTAssertNil(try engine.evaluateScript("java.queryTTF(null)"))
        XCTAssertThrowsError(try engine.evaluateScript("java.queryTTF('YQ==')"))
    }

    func testURLCacheAndBypass() async throws {
        let client = ReplayHttpClient(), url = URL(string: "https://font.test/" + UUID().uuidString)!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: font(code: 67), finalURL: url))
        let engine = JsEngine(httpClient: client)
        let script = "java.queryTTF('\(url.absoluteString)').getGlyfIdByUnicode(67)"
        XCTAssertEqual(try engine.evaluateScript(script) as? Double, 1)
        XCTAssertEqual(try engine.evaluateScript(script) as? Double, 1)
        XCTAssertThrowsError(try engine.evaluateScript("java.queryTTF('\(url.absoluteString)',false)"))
    }

    func testCompoundAndMappingFormats() throws {
        for format in [0, 4, 6] {
            let query = try QueryTTF(font(code: 65, format: format))
            XCTAssertEqual(query.getGlyfByUnicode(65), "10,20")
            XCTAssertEqual(query.getGlyfById(2), "[{flags:3,glyphIndex:1,arg1:-2,arg2:4,xScale:0.0,scale01:0.0,scale10:0.0,yScale:0.0}]")
            XCTAssertEqual(query.getGlyfIdByUnicode(90), 0)
            XCTAssertNil(query.getGlyfByUnicode(90))
        }
    }

    func testTruncatedTablesFailWithoutCrashing() throws {
        let bytes = font(code: 65)
        for length in stride(from: 0, to: bytes.count, by: 7) { XCTAssertThrowsError(try QueryTTF(bytes.prefix(length))) }
    }

    private func font(code: Int, format: Int = 6) -> Data {
        func words(_ values: [Int]) -> Data { Data(values.flatMap { [UInt8(truncatingIfNeeded: $0 >> 8), UInt8(truncatingIfNeeded: $0)] }) }
        func longs(_ values: [Int]) -> Data { Data(values.flatMap { [UInt8(truncatingIfNeeded: $0 >> 24), UInt8(truncatingIfNeeded: $0 >> 16), UInt8(truncatingIfNeeded: $0 >> 8), UInt8(truncatingIfNeeded: $0)] }) }
        let simple = words([1,0,0,10,20,0,0]) + Data([0x37,10,20,0])
        let compound = words([-1,0,0,10,20,3,1,-2,4])
        var head = Data(repeating: 0, count: 54); head[51] = 1
        let mapping: Data
        switch format {
        case 0:
            var ids = Data(repeating: 0, count: 256); ids[code] = 1
            mapping = words([0,262,0]) + ids
        case 4: mapping = words([4,32,0,4,4,1,0,code,65535,0,code,65535,1-code,1,0,0])
        default: mapping = words([6,12,0,code,1,1])
        }
        let tables: [(String, Data)] = [("head",head),("name",words([0,0,6])),("maxp",longs([0x10000])+words([3,1,1])+Data(repeating:0,count:22)),
            ("loca",longs([0,0,simple.count,simple.count+compound.count])),("glyf",simple+compound),("cmap",words([0,1,3,1])+longs([12])+mapping)]
        var result = longs([0x10000])+words([tables.count,0,0,0]), body = Data()
        var offset = 12 + 16*tables.count
        for (name, data) in tables { result += Data(name.utf8)+longs([0,offset,data.count]); body += data; offset += data.count }
        return result + body
    }
}
