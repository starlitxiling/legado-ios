import XCTest
@testable import LegadoCore

final class RuleReplaceTests: XCTestCase {
    // 规格 L218-231、L368：组引用贪婪扩展只到合法组号，替换 $0 与模板 $0 不同。
    func testNumberedGroupsAndEscapes() {
        let replacer = RuleReplace()
        XCTAssertEqual(replacer.apply("ab", replacement: RuleReplacement("##(a)(b)##$0/$12/$2")), "ab/a2/b")
        XCTAssertEqual(replacer.apply("ab", replacement: RuleReplacement(#"##(a)(b)##\$1\\$2"#)), #"$1\b"#)
        XCTAssertEqual(replacer.apply("ab", replacement: RuleReplacement("##(a)(b)##$")), "ab")
        XCTAssertEqual(replacer.apply("ab", replacement: RuleReplacement("##(a)(b)##$###")), "$")
    }

    // 规格 L227-228：首匹配先提取子串，再重新匹配；前后文不会保留。
    func testFirstMatchRechecksExtractedSubstring() {
        let replacer = RuleReplace()
        XCTAssertEqual(replacer.apply("ab", replacement: RuleReplacement("##(?<=a)b##X###")), "b")
        XCTAssertEqual(replacer.apply("ab", replacement: RuleReplacement("##b##X####ignored")), "X")
        XCTAssertEqual(replacer.apply("ab", replacement: RuleReplacement("####X")), "ab")
    }

    // 规格 L225、L368：替换语法走 Java Matcher 组引用，未参与匹配的组为空。
    func testNamedGroups() {
        let replacer = RuleReplace()
        XCTAssertEqual(replacer.apply("b ab", replacement: RuleReplacement("##(?<letter>a)?b##${letter}")), " a")
        XCTAssertEqual(replacer.apply("ab", replacement: RuleReplacement("##(?<letter>a)b##${missing}")), "ab")
    }

    // 规格 L230：超过缓存容量仍计算，不丢弃后续替换。
    func testCacheCapacityDoesNotLimitEvaluation() {
        let replacer = RuleReplace()
        for index in 0..<20 {
            XCTAssertEqual(replacer.apply("v\(index)", replacement: RuleReplacement("##v\(index)##X")), "X")
        }
    }
}
