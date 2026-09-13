import XCTest
@testable import LegadoCore

final class JsEngineTests: XCTestCase {
    // cb664b84d AnalyzeRule.kt:368；模板格式化见 :801。
    func testReviewNumberFormatting() throws {
        let parser = AnalyzeRule(content: "", engines: [.js: JsEngine()])
        XCTAssertEqual(try parser.getString("@js:var [h,...t]=[1,2,3];t.length"), "2.0")
        XCTAssertEqual(try parser.getString("{{2}}"), "2")
        XCTAssertEqual(try parser.getStringList("@js:['a','b']##a##x"), ["x", "b"])
    }

    // cb664b84d AnalyzeRule.kt:349：链式 result 保留可调用对象。
    func testReviewFunctionPipeline() throws {
        let parser = AnalyzeRule(content: "", engines: [.js: JsEngine()])
        XCTAssertEqual(try parser.getString("<js>(function(){return 'ok'})</js><js>result()</js>"), "ok")
        XCTAssertEqual(try parser.getString("<js>({f:()=> 'nested'})</js><js>result.f()</js>"), "nested")
        XCTAssertEqual(try parser.getString("<js>globalThis.marker='same';result</js><js>marker</js>"), "same")
        XCTAssertEqual(try parser.getString("@js:typeof marker"), "undefined")
    }

    // cb664b84d AnalyzeRule.kt:302-319：布尔参数与替代内容重载。
    func testReviewGetStringOverloads() throws {
        let parser = AnalyzeRule(content: "<p>original</p>", engines: [.js: JsEngine(), .default: AnalyzeByJSoup()])
        XCTAssertEqual(try parser.getString("@js:java.getString(\"@js:'&amp;'\",false)==='&amp;'"), "true")
        XCTAssertEqual(try parser.getString("@js:java.getString('tag.p@text','<p>other</p>')"), "other")
        XCTAssertEqual(try parser.getString("@js:java.getString('tag.p@text','<p>other</p>',false)"), "other")
        XCTAssertEqual(try parser.getString("@js:java.getString('@js:src','other')"), "<p>original</p>")
        XCTAssertThrowsError(try parser.getString("@js:java.getString('x','y',true)"))
        XCTAssertThrowsError(try parser.getString("@js:java.getString('x','y',false,42)"))
    }

    // cb664b84d AnalyzeRule.kt:104-119：链式宿主、基址与非空约束。
    func testReviewSetContent() throws {
        let parser = AnalyzeRule(content: "", engines: [.js: JsEngine(), .default: AnalyzeByJSoup()])
        XCTAssertEqual(try parser.getString("@js:java.setContent('<p>A</p>').getString('tag.p@text')"), "A")
        XCTAssertEqual(try parser.getString("@js:java.setContent('x','https://new/').getString('@js:baseUrl')"), "https://new/")
        XCTAssertThrowsError(try parser.getString("@js:java.setContent(null)"))
    }

    // cb664b84d AnalyzeUrl.kt:395-411：URL 专属绑定与 extraParams 顺序。
    func testReviewURLBindings() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.interpolateURL("https://x/{{page===null?'first':page}}", bindings: [:]), "https://x/first")
        XCTAssertEqual(try engine.interpolateURL("{{[key,speakText,speakSpeed,infoMap].every(x=>x===null)}}", bindings: [:]), "true")
        XCTAssertEqual(try engine.interpolateURL("{{typeof src}}/{{page+1}}/{{custom}}", bindings: ["extraParams": ["page":"2", "custom":"ok"]]), "undefined/3/ok")
    }

    // cb664b84d JsExtensions.kt:681-687、761：字符集和 flags 重载。
    func testReviewEncodingOverloads() throws {
        let parser = AnalyzeRule(content: "", engines: [.js: JsEngine()])
        for charset in ["GBK", "GB2312", "GB18030"] {
            XCTAssertEqual(try parser.getString("@js:java.encodeURI('中','\(charset)')"), "%D6%D0")
        }
        XCTAssertEqual(try parser.getString("@js:java.base64Decode('YQ==',0)"), "a")
        XCTAssertEqual(try parser.getString("@js:java.base64Decode('YQ',2)"), "a")
    }

    // cb664b84d AnalyzeRule.kt:856：宿主参数转换为字符串并返回。
    func testReviewPutCoercion() throws {
        let store = RuleVariableStore()
        let parser = AnalyzeRule(content: "", engines: [.js: JsEngine()], ruleData: store)
        XCTAssertEqual(try parser.getString("@js:java.put('x',123)+1"), "1231")
        XCTAssertEqual(store.value(for: "x"), "123")
        XCTAssertEqual(try parser.getString("@js:java.put('x',null)"), "null")
        XCTAssertEqual(store.value(for: "x"), "null")
    }

    // rule-engine.md:129、138、240：脚本保留原值，模板 null 不插入。
    func testRulesAndTemplates() throws {
        let parser = AnalyzeRule(content: "abc", engines: [.js: JsEngine()])
        XCTAssertEqual(try parser.getString("@js:result.toUpperCase()"), "ABC")
        XCTAssertEqual(try parser.getString("<js>result+'x'</js><js>result+'y'</js>"), "abcxy")
        XCTAssertEqual(try parser.getString("a{{null}}b{{1+2}}"), "ab3")
        XCTAssertEqual(try parser.getElements("@js:['a', null, 'b']") as? [String], ["a", "b"])
    }

    // rule-engine.md:265-280：result 与 src 分开绑定，page 尝试转整数。
    func testBindingsAndHosts() throws {
        let engine = JsEngine(baseUrl: "https://example.invalid", timeZone: TimeZone(secondsFromGMT: 0)!, httpClient: ReplayHttpClient(), cacheManager: CacheManager(directory: nil))
        let store = RuleVariableStore(name: "书名")
        let parser = AnalyzeRule(content: "original", engines: [.js: engine], book: store)
        parser.setLocal("page", value: "2")
        XCTAssertEqual(try parser.getString("<js>'changed'</js><js>[result,src,page+1,book.name].join('|')</js>"), "changed|original|3|书名")
        XCTAssertEqual(try parser.getString("@js:java.put('x','v');java.get('x')"), "v")
        XCTAssertEqual(try parser.getString("@js:java.md5Encode('abc')"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(try parser.getString("@js:java.base64Decode('5Lit5paH')"), "中文")
        XCTAssertEqual(try parser.getString("@js:java.encodeURI('a +~*')"), "a+%2B%7E*")
        XCTAssertEqual(try parser.getString("@js:java.timeFormat(0)"), "1970/01/01 00:00")
        XCTAssertEqual(try parser.getString("@js:java.log('ok')"), "ok")
        XCTAssertNotNil(try parser.getString("@js:java.ajax('https://example.invalid')"))
    }

    // 已知差异：docs/spec/js-host-compat.md；这些断言记录边界，不表示已对齐 Rhino。
    func testIsolationExceptionsAndCompatibility() throws {
        let engine = JsEngine()
        XCTAssertThrowsError(try engine.evaluateScript("let x=1; let x=2; x"))
        XCTAssertThrowsError(try engine.evaluateScript("{ let x=1; } x"))
        XCTAssertThrowsError(try engine.evaluateScript("{ const x=1; } x"))
        XCTAssertEqual(try engine.evaluateScript("var x=1; var x=2; x") as? Double, 2)
        XCTAssertEqual(try engine.evaluateScript("let x=3; x") as? Double, 3)
        XCTAssertNil(try engine.evaluateScript("undefined"))
        XCTAssertNil(try engine.evaluateScript("null"))
        XCTAssertEqual(try engine.evaluateScript("typeof CryptoJS") as? String, "undefined")
        XCTAssertThrowsError(try engine.evaluateScript("throw new Error('boom')"))
        XCTAssertEqual(try engine.evaluateScript("1+1") as? Double, 2)
        do { _ = try engine.evaluateScript("let duplicate=1; let duplicate=2; duplicate") }
        catch { print("JSC-EXPERIMENT duplicate let: \(error)") }
        print("JSC-EXPERIMENT duplicate var: \(try engine.evaluateScript("var duplicate=1; var duplicate=2; duplicate")!)")
        let parser = AnalyzeRule(content: "", engines: [.js: engine])
        XCTAssertEqual(try parser.getString("@js:typeof java.md5Encode('abc')"), "string")
        XCTAssertEqual(try parser.getString("@js:java.md5Encode('abc').length"), "32.0")
        XCTAssertThrowsError(try parser.getString("@js:java.md5Encode('abc').length()"))
    }

    func testHostBoundariesAndNestedEvaluation() throws {
        let engine = JsEngine(httpClient: ReplayHttpClient(), cacheManager: CacheManager(directory: nil))
        let parser = AnalyzeRule(content: "<p>A</p>", engines: [.js: engine, .default: AnalyzeByJSoup()])
        XCTAssertEqual(try parser.getString("@js:java.getString('tag.p@text')"), "A")
        XCTAssertEqual(try parser.getString("@js:java.getElements('tag.p')[0].text()"), "A")
        XCTAssertEqual(try parser.getString("@js:java.getElement('tag.p')[0].text()"), "A")
        XCTAssertEqual(try parser.getString("@js:java.getString('@js:1+2')"), "3.0")
        XCTAssertEqual(try parser.getString("@js:java.setContent('<b>B</b>');java.getString('tag.b@text')"), "B")
        XCTAssertEqual(try parser.getString("@js:java.toNumChapter('前言 第一百二十三章 标题')"), "第123章")
        XCTAssertEqual(try parser.getString("@js:java.toNumChapter('第两千二章')"), "第2200章")
        XCTAssertEqual(try parser.getString("@js:java.toNumChapter('第无效章')"), "第-1章")
        XCTAssertEqual(try parser.getString("@js:java.base64Decode('YQ')"), "a")
        XCTAssertThrowsError(try parser.getString("@js:java.base64Decode('!')"))
        // 已知差异：docs/spec/js-host-compat.md 的离线宿主桩。
        XCTAssertThrowsError(try parser.getString("@js:cookie.get('x')"))
        XCTAssertNoThrow(try parser.getString("@js:cache.put('x','y')"))
        XCTAssertEqual(try parser.getString("@js:try { java.post('x'); } catch(e) { e.message; }"), "JavaScript: post 参数数量无效")
        XCTAssertEqual(try parser.getString("@js:java.aesBase64DecodeToString('cnJ+iB7c/QEApxhoeQm1ZQ==','0123456789abcdef','AES/ECB/NoPadding','')"), "0123456789abcdef")
        XCTAssertThrowsError(try parser.getString("@js:java.aesBase64DecodeToString('AA==','short','AES/CBC/PKCS5Padding','')"))
    }

    func testOfflineFixtures() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cases = try ConformanceRunner.load(directories: ["golden", "synthetic"].map {
            root.appendingPathComponent("Tests/Conformance/fixtures/\($0)")
        })
        let ids = ["synthetic-template-001", "synthetic-template-002", "synthetic-template-004",
                   "synthetic-replace-007", "synthetic-replace-008", "synthetic-url-017", "synthetic-url-018"]
        let report = ConformanceRunner.run(cases.filter { $0.kind == "js" || ids.contains($0.id) })
        for result in report.results {
            print("JS-FIXTURE \(result.id): \(result.status.rawValue) \(result.detail)")
            XCTAssertEqual(result.status, .passed, "\(result.id): \(result.detail)")
        }
    }
}
