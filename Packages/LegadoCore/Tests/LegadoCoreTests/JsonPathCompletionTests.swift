import XCTest
@testable import LegadoCore

final class JsonPathCompletionTests: XCTestCase {
    func testLargeIntegersKeepDigitsAndCompareWithoutRounding() throws {
        let parser = try AnalyzeByJSonPath("[9223372036854775808,9223372036854775809,-999999999999999999999999999999999999999999999999999]")
        XCTAssertEqual(parser.getStringList("$"), ["9223372036854775808", "9223372036854775809", "-999999999999999999999999999999999999999999999999999"])
        XCTAssertEqual(parser.getStringList("$[?(@ == 9223372036854775809)]"), ["9223372036854775809"])
        XCTAssertEqual(parser.getStringList("$[?(@ > 9223372036854775808)]"), ["9223372036854775809"])
    }

    func testCollectionOperators() throws {
        let parser = try AnalyzeByJSonPath(#"[{"id":"one","tags":["a","b"],"text":"alphabet"},{"id":"two","tags":[],"text":"beta"},{"id":"three","tags":["c"]}]"#)
        for (predicate, expected) in [
            ("@.tags contains 'a'", ["one"]), ("@.text contains 'alpha'", ["one"]),
            ("@.tags subsetof ['a','b']", ["one", "two"]),
            ("@.tags anyof ['b','c']", ["one", "three"]),
            ("@.tags noneof ['a','b']", ["two", "three"])
        ] {
            XCTAssertEqual(parser.getStringList("$[?(" + predicate + ")].id"), expected, predicate)
        }
    }

    func testAggregationKeysAndSize() throws {
        let parser = try AnalyzeByJSonPath(#"{"nums":[1,2,3,4],"object":{"z":1,"a":2},"empty":[]}"#)
        XCTAssertEqual(try parser.getObject("$.nums.avg()") as? Double, 2.5)
        XCTAssertEqual(try XCTUnwrap(parser.getObject("$.nums.stddev()") as? Double), sqrt(1.25), accuracy: 1e-12)
        XCTAssertEqual(try parser.getObject("$.object.size()") as? Int, 2)
        XCTAssertEqual(parser.getStringList("$.object.keys()"), ["z", "a"])
        XCTAssertThrowsError(try parser.getObject("$.empty.avg()"))
        XCTAssertEqual(try parser.getObject("$.nums.avg(5,6)") as? Double, 3.5)
        XCTAssertEqual(parser.getStringList("$.nums.append({\"x\":1}).last().x"), ["1"])
        XCTAssertEqual(parser.getStringList("$[?(@.nums.size() == 4)].nums.first()"), ["1"])
    }

    func testFunctionArgumentsPathsAndChaining() throws {
        let parser = try AnalyzeByJSonPath(#"{"nums":[1,2,3],"words":["a",2,"b"],"suffix":"c"}"#)
        XCTAssertEqual(parser.getString("$.words.concat($.suffix, \"d\")"), "abcd")
        XCTAssertEqual(parser.getStringList("$.nums.append(4,5)"), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(parser.getString("$.nums.index(-1)"), "3")
        XCTAssertEqual(parser.getString("$.nums.append(4).avg()"), "2.5")
        XCTAssertThrowsError(try parser.getObject("$.nums.index(-3)"))
        XCTAssertThrowsError(try parser.getObject("$.nums.index(99)"))
    }
}
