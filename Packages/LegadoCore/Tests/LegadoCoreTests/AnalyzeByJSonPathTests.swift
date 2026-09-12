import Foundation
import XCTest
@testable import LegadoCore

final class AnalyzeByJSonPathTests: XCTestCase {
    private let document = #"{"items":[{"x":1,"name":"Alpha","tags":["a"]},{"x":2,"name":"Beta","tags":[]},{"name":"None"}],"nums":[1,2,3,4],"nil":null,"flag":true,"empty":[],"child":{"x":9}}"#

    // 规格 §4、§11；AnalyzeByJSonPath.kt:18-23、49-56、91-99、128-144。
    private func read(_ path: String) throws -> Any {
        try AnalyzeByJSonPath(document).getObject(path)
    }

    // PropertyPathToken；Kotlin AnalyzeByJSonPath.kt:128-129。
    func testPropertyUnionBranchesAndLeafProjection() throws {
        let parser = try AnalyzeByJSonPath(#"{"a":{"x":1},"b":{"x":2}}"#)
        XCTAssertEqual(try parser.getObject("$['a','b'].x") as? [Int], [1, 2])
        XCTAssertEqual(try parser.getObject("$['missing','a'].x") as? [Int], [1])
        let partial = try AnalyzeByJSonPath(#"{"a":1}"#)
        XCTAssertEqual(try partial.getObject("$['a','b']") as? [String: Int], ["a": 1])
        XCTAssertEqual(try partial.getObject("$['b','c']") as? [String: Int], [:])
        XCTAssertThrowsError(try partial.getObject("$.b"))
    }

    func testRootPropertiesAndDefiniteness() throws {
        XCTAssertTrue(try read("$") is [String: Any])
        XCTAssertEqual(try read("$.child.x") as? Int, 9)
        XCTAssertEqual(try read("$['child'][\"x\"]") as? Int, 9)
        XCTAssertEqual(try read("child.x") as? Int, 9)
        XCTAssertEqual(try read("$.items[*].x") as? [Int], [1, 2])
        XCTAssertTrue(try read("$.nil") is NSNull)
        XCTAssertThrowsError(try read("$.missing"))
        XCTAssertThrowsError(try read("$.flag.x"))
    }

    func testWildcardsRecursiveAndUnions() throws {
        XCTAssertEqual(try read("$..x") as? [Int], [1, 2, 9])
        XCTAssertEqual(try read("$.empty[*]") as? [Int], [])
        XCTAssertEqual(try read("$.nums[0,2,-1]") as? [Int], [1, 3, 4])
        XCTAssertEqual(try read("$.nums[99,0]") as? [Int], [1])
        XCTAssertEqual((try read("$.child.*") as? [Int]), [9])
        XCTAssertFalse((try read("$..*") as? [Any] ?? []).isEmpty)
        XCTAssertTrue(try read("$['nil','flag']") is [String: Any])
        XCTAssertEqual(try read("$..[?(@.x)].x") as? [Int], [1, 2, 9])
    }

    func testIndicesAndSlices() throws {
        XCTAssertEqual(try read("$.nums[-1]") as? Int, 4)
        XCTAssertThrowsError(try read("$.nums[4]"))
        XCTAssertThrowsError(try read("$.nums[-5]"))
        XCTAssertEqual(try read("$.nums[1:3]") as? [Int], [2, 3])
        XCTAssertEqual(try read("$.nums[-2:]") as? [Int], [3, 4])
        XCTAssertEqual(try read("$.nums[:99]") as? [Int], [1, 2, 3, 4])
        XCTAssertEqual(try read("$.nums[3:1]") as? [Int], [])
        XCTAssertEqual(try read("$.nums[::2]") as? [Int], [1, 3])
        XCTAssertEqual(try read("$.nums[::-1]") as? [Int], [4, 3, 2, 1])
        XCTAssertThrowsError(try read("$.nums[::0]"))
    }

    // JsonSmartJsonProvider、ScanPathToken；Kotlin AnalyzeByJSonPath.kt:18-23、85-89。
    func testDocumentMemberOrder() throws {
        let parser = try AnalyzeByJSonPath(#"{"z":{"x":1},"a":{"x":2}}"#)
        XCTAssertEqual(try parser.getObject("$..x") as? [Int], [1, 2])
        XCTAssertEqual(try parser.getObject("$.*.x") as? [Int], [1, 2])
        XCTAssertEqual(try parser.getObject("$['a','z'].x") as? [Int], [2, 1])
        let escaped = try AnalyzeByJSonPath(#"{"\u007a":{"x":1},"a":{"x":2},"z":{"x":3}}"#)
        XCTAssertEqual(try escaped.getObject("$..x") as? [Int], [3, 2])
        let nested = try AnalyzeByJSonPath(#"[{"z":{"x":1},"a":[{"x":2},{"x":3}]}]"#)
        XCTAssertEqual(try nested.getObject("$..x") as? [Int], [1, 2, 3])
        for text in ["{", "[1,]", "{\"a\":1,}", "01", "1.", "[true false]", "{}[]"] {
            XCTAssertThrowsError(try AnalyzeByJSonPath(text), text)
        }
    }

    func testFilters() throws {
        let cases: [(String, [String])] = [
            ("@.x == 1", ["Alpha"]), ("@.x != 1", ["Beta", "None"]),
            ("@.x < 2", ["Alpha"]), ("@.x <= 1", ["Alpha"]),
            ("@.x > 1", ["Beta"]), ("@.x >= 2", ["Beta"]),
            ("@.name =~ /alpha/i", ["Alpha"]), ("@.x in [1,3]", ["Alpha"]),
            ("@.x nin [1,3]", ["Beta", "None"]), ("@.tags size 1", ["Alpha"]),
            ("@.tags empty true", ["Beta"]), ("@.tags empty false", ["Alpha"]),
            ("(@.x == 1 || @.x == 2) && @.tags size 0", ["Beta"]),
            ("@.x == 99", []), ("@.x == '1'", []), ("@.x", ["Alpha", "Beta"]),
            ("@.x < $.child.x", ["Alpha", "Beta"])
        ]
        for (filter, expected) in cases {
            XCTAssertEqual(try read("$.items[?(\(filter))].name") as? [String], expected, filter)
        }
        XCTAssertThrowsError(try read("$.items[?(@.x === 1)]"))
        XCTAssertThrowsError(try read("$.items[?(@.x ==)]"))
    }

    func testFunctions() throws {
        for (name, expected) in [("length", 4.0), ("min", 1), ("max", 4), ("sum", 10), ("first", 1), ("last", 4)] {
            XCTAssertEqual((try read("$.nums.\(name)()") as? NSNumber)?.doubleValue, expected)
        }
        XCTAssertEqual(try read("$.empty.length()") as? Int, 0)
        XCTAssertThrowsError(try read("$.empty.first()"))
        XCTAssertThrowsError(try read("$.flag.sum()"))
        XCTAssertThrowsError(try read("$.nums.unknown()"))
    }

    func testKotlinExitsAndMalformedPaths() throws {
        let parser = try AnalyzeByJSonPath(document)
        XCTAssertEqual(parser.getString("$.nums"), "1\n2\n3\n4")
        XCTAssertEqual(parser.getStringList("$.flag"), ["true"])
        XCTAssertEqual(parser.getStringList("$.nil"), ["null"])
        XCTAssertEqual(parser.getStringList("$.child"), ["{x=9}"])
        XCTAssertEqual(parser.getStringList("$.missing"), [])
        XCTAssertEqual(parser.getString("$.missing"), "")
        XCTAssertNil(parser.getString(""))
        XCTAssertEqual(parser.getList("$.flag")?.count, 0)
        XCTAssertEqual(parser.getList("$.nums")?.count, 4)
        for path in ["", "$.", "$[", "$['bad]", "$.nums[wat]", "$.nums[1]junk"] {
            XCTAssertThrowsError(try parser.getObject(path), path)
        }
        XCTAssertThrowsError(try AnalyzeByJSonPath("bad json"))
    }

    func testSelectorIntegrationAndFixtures() throws {
        let parser = AnalyzeRule(content: document, engines: [.json: AnalyzeByJSonPath()])
        XCTAssertEqual(try parser.getString("@Json:$.flag"), "true")
        XCTAssertEqual(try parser.getStringList("$.empty[*]||$.nums[0,1]"), ["1", "2"])
        XCTAssertThrowsError(try parser.getElement("$.missing"))
        XCTAssertEqual(try AnalyzeRule(content: "[1,2]", engines: [.json: AnalyzeByJSonPath()]).getString("$[0]"), "1")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cases = try ConformanceRunner.load(directories: [root.appendingPathComponent("Tests/Conformance/fixtures/synthetic")])
            .filter { $0.kind == "jsonpath" }
        XCTAssertEqual(cases.count, 5)
        for result in ConformanceRunner.run(cases).results {
            print("jsonpath \(result.id): \(result.status.rawValue) \(result.detail)")
            XCTAssertEqual(result.status, .passed, result.detail)
        }
    }

    // 规格 §3.3、§4；AnalyzeByJSonPath.kt:45、86：平衡模板优先于路径读取。
    func testEmbeddedTemplateAndEscapedStrings() throws {
        let parser = try AnalyzeByJSonPath(document)
        XCTAssertEqual(parser.getString("value={$.child.x}"), "value=9")
        XCTAssertEqual(parser.getStringList("{$.flag}:{$.child.x}"), ["true:9"])
        let escaped = try AnalyzeByJSonPath(#"[{"name":"a\"b","雪":true},{"name":"it's"}]"#)
        XCTAssertEqual(escaped.getStringList(#"$[?(@.name == 'a\"b')]['雪']"#), ["true"])
        XCTAssertEqual(escaped.getStringList(#"$[?(@.name == 'it\'s')].name"#), ["it's"])
    }

    func testFilterBoundariesAndNestedValues() throws {
        let parser = try AnalyzeByJSonPath(#"[{"x":null},{"x":false},{"x":0},{"x":""},{"x":[]},{}]"#)
        XCTAssertEqual(parser.getStringList("$[?(@.x == null)].x"), ["null"])
        XCTAssertEqual(parser.getStringList("$[?(@.x == false)].x"), ["false"])
        XCTAssertEqual(parser.getStringList("$[?(@.x)].x"), ["null", "false", "0", "", "[]"])
        XCTAssertEqual(parser.getStringList("$[?(!@.x)]"), ["{}"])
        XCTAssertEqual(parser.getStringList("$[?(@.x empty true)].x"), ["", "[]"])
        XCTAssertEqual(parser.getStringList("$[?(@.x in [])]"), [])
        XCTAssertEqual(try AnalyzeByJSonPath("[]").getStringList("$[?(@.x == 1)]"), [])
        XCTAssertThrowsError(try AnalyzeByJSonPath("[]").getObject("$[?(@.x ==)]"))
        XCTAssertEqual(try AnalyzeByJSonPath(#"[[1,null],{"b":2,"a":1}]"#).getStringList("$"), ["[1, null]", "{b=2, a=1}"])
    }

    // JsonSmartJsonProvider 返回 LinkedHashMap/ArrayList；Kotlin AnalyzeByJSonPath.kt:48-52、85-89。
    func testJavaCollectionAndDoubleText() throws {
        let parser = try AnalyzeByJSonPath(#"{"value":{"z":[1,"two",null,true,{"x":9}],"a":false}}"#)
        XCTAssertEqual(parser.getString("$.value"), "{z=[1, two, null, true, {x=9}], a=false}")
        XCTAssertEqual(parser.getStringList("$.value.z"), ["1", "two", "null", "true", "{x=9}"])
        XCTAssertEqual(parser.getString("$.value.z"), "1\ntwo\nnull\ntrue\n{x=9}")
        let numbers = try AnalyzeByJSonPath("[1,1.0,-0.0,0.001,0.0001,10000000.0,1.25e20,1e-7]")
        XCTAssertEqual(numbers.getStringList("$"), ["1", "1.0", "-0.0", "0.001", "1.0E-4", "1.0E7", "1.25E20", "1.0E-7"])
        let extremes = try AnalyzeByJSonPath("[4.9e-324,2.2250738585072014e-308,1.7976931348623157e308]")
        XCTAssertEqual(extremes.getStringList("$"), ["4.9E-324", "2.2250738585072014E-308", "1.7976931348623157E308"])
    }

    // ScanPathToken；Kotlin AnalyzeByJSonPath.kt:48、85、128-129。
    func testRecursiveFiltersDoNotVisitScalars() throws {
        XCTAssertEqual(try AnalyzeByJSonPath(#"{"x":1}"#).getObject("$..[?(@ == 1)]") as? [Int], [])
        XCTAssertEqual(try AnalyzeByJSonPath("1").getObject("$..[?(@ == 1)]") as? [Int], [])
        let parser = try AnalyzeByJSonPath(#"[1,[1,[1]],{"x":1},[[{"x":2}]]]"#)
        XCTAssertEqual(try parser.getObject("$..[?(@ == 1)]") as? [Int], [])
        XCTAssertEqual(try parser.getObject("$..[?(@.x)].x") as? [Int], [1, 2])
        XCTAssertEqual(try parser.getObject("$[?(@ == 1)]") as? [Int], [1])
    }
}
