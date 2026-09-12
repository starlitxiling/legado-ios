import Foundation
import XCTest
@testable import LegadoCore

final class UrlOptionsTests: XCTestCase {
    func testDefaultsAndSplitting() throws {
        let result = UrlOptions.parse("https://example.invalid/a,b  ,  {\"method\":\"head\"}")
        XCTAssertEqual(result.url, "https://example.invalid/a,b")
        XCTAssertEqual(result.options.method, "HEAD")
        XCTAssertEqual(result.status, .strict)
        let defaults = UrlOptions.parse("/path")
        XCTAssertEqual(defaults.status, .absent)
        XCTAssertEqual(defaults.options.method, "GET")
        XCTAssertNil(defaults.options.charset)
        XCTAssertEqual(defaults.options.effectiveCharset, "UTF-8")
        XCTAssertNil(defaults.options.timeout)
        XCTAssertNil(defaults.options.followRedirects)
        XCTAssertEqual(defaults.options.retry, 0)
    }

    func testLenientAndMalformedJSON() throws {
        let parsed = UrlOptions.parse("u,{method:'head', /* note */ charset:UTF-8}")
        XCTAssertEqual(parsed.status, .lenient)
        XCTAssertEqual(parsed.options.method, "HEAD")
        XCTAssertEqual(parsed.options.charset, "UTF-8")
        for text in ["u,{method:", "u,{method:'post',}", "u,{} garbage"] {
            XCTAssertEqual(UrlOptions.parse(text).status, .invalid, text)
            XCTAssertEqual(UrlOptions.parse(text).options.method, "GET", text)
        }
        XCTAssertEqual(try UrlOptions.fromJSON("{method=>head}").method, "HEAD")
    }

    func testTimeoutBoundaries() throws {
        for (value, expected) in [("1", 60_000), ("40000", 80_000), ("2147483647", 2_147_483_647)] {
            XCTAssertEqual(try UrlOptions.fromJSON("{timeout:\(value)}").callTimeout, Int64(expected))
        }
        for value in ["0", "-1", "2147483648", "1.5", "true", "'1.0'", "[]", "null"] {
            XCTAssertNil(try UrlOptions.fromJSON("{timeout:\(value)}").timeout, value)
        }
        XCTAssertEqual(try UrlOptions.fromJSON("{timeout:' 40000 '}").timeout, 40_000)
        XCTAssertEqual(try UrlOptions.fromJSON("{timeout:1e3}").timeout, 1_000)
    }

    func testBooleanAndWebViewTruth() throws {
        for value in ["true", "1", "' TRUE '", "'1'"] {
            XCTAssertEqual(try UrlOptions.fromJSON("{followRedirects:\(value)}").followRedirects, true)
        }
        for value in ["false", "0", "' False '", "'0'"] {
            XCTAssertEqual(try UrlOptions.fromJSON("{followRedirects:\(value)}").followRedirects, false)
        }
        for value in ["2", "'yes'", "null", "{}"] {
            XCTAssertNil(try UrlOptions.fromJSON("{followRedirects:\(value)}").followRedirects)
        }
        for value in ["null", "''", "false", "'false'"] {
            XCTAssertFalse(try UrlOptions.fromJSON("{webView:\(value)}").useWebView)
        }
        for value in ["0", "'0'", "'False'", "' '", "[]", "{}"] {
            XCTAssertTrue(try UrlOptions.fromJSON("{webView:\(value)}").useWebView)
        }
    }

    func testHeadersAndBody() throws {
        let options = try UrlOptions.fromJSON("{headers:{n:2,b:true,z:null},body:{k:'v',a:[],z:null}}")
        XCTAssertEqual(options.headers, ["n": "2", "b": "true", "z": "null"])
        XCTAssertEqual(options.body, "{\n  \"k\": \"v\",\n  \"a\": []\n}")
        XCTAssertEqual(try UrlOptions.fromJSON("{body:[]}").body, "[]")
        XCTAssertEqual(try UrlOptions.fromJSON("{body:'a=b&x=y'}").body, "a=b&x=y")
        XCTAssertEqual(try UrlOptions.fromJSON("{body:false}").body, "false")
        XCTAssertEqual(try UrlOptions.fromJSON("{headers:'bad'}").headers, [:])
    }

    func testAllFieldsAndAliasOrder() throws {
        let options = try UrlOptions.fromJSON("{method:patch,charset:'',origin:7,type:true,webJs:'x',js:'y',bodyJs:'z',retry:3,serverID:9223372036854775807,webViewDelayTime:-8,dnsIp:'a',resolveIp:' b '}")
        XCTAssertEqual(options.method, "GET")
        XCTAssertEqual(options.origin, "7")
        XCTAssertEqual(options.type, "true")
        XCTAssertEqual(options.webJs, "x")
        XCTAssertEqual(options.js, "y")
        XCTAssertEqual(options.bodyJs, "z")
        XCTAssertEqual(options.retry, 3)
        XCTAssertEqual(options.serverID, Int64.max)
        XCTAssertEqual(options.webViewDelayTime, 0)
        XCTAssertEqual(options.dnsIp, " b ")
        XCTAssertEqual(try UrlOptions.fromJSON("{resolveIp:'a',dnsIp:'b'}").dnsIp, "b")
        var setters = UrlOptions()
        setters.setTimeout("5000")
        setters.setFollowRedirects("false")
        setters.setDnsIp(" 1.1.1.1 ")
        XCTAssertEqual(setters.timeout, 5000)
        XCTAssertEqual(setters.followRedirects, false)
        XCTAssertEqual(setters.dnsIp, "1.1.1.1")
    }

    func testDNSLiteralValidationAndProxy() throws {
        XCTAssertEqual(try UrlOptions.parseDnsIpAddresses("1.1.1.1, [2001:db8::1]").first, "1.1.1.1")
        for value in ["", "dns.example", "999.1.1.1", "[::1", "::1%en0", "1.1.1.1,dns.example"] {
            XCTAssertThrowsError(try UrlOptions.parseDnsIpAddresses(value), value)
        }
        XCTAssertThrowsError(try UrlOptions.validateDnsIpProxyCompatibility(proxy: "http://p", dnsIp: "1.1.1.1"))
        XCTAssertNoThrow(try UrlOptions.validateDnsIpProxyCompatibility(proxy: " ", dnsIp: "1.1.1.1"))
    }

    func testRepeatedAliasAndTypedFieldFailure() throws {
        XCTAssertEqual(try UrlOptions.fromJSON("{dnsIp:a,resolveIp:b,dnsIp:c}").dnsIp, "c")
        XCTAssertEqual(try UrlOptions.fromJSON("{retry:'3',serverID:'42',webViewDelayTime:'5'}").retry, 3)
        for field in ["retry", "serverID", "webViewDelayTime"] {
            XCTAssertEqual(UrlOptions.parse("u,{method:POST,\(field):'bad'}").status, .invalid, field)
        }
        XCTAssertEqual(try UrlOptions.fromJSON("{method:{x:1},body:{a:1,a:2}}").body, "{\n  \"a\": 2\n}")
    }

    func testLenientSeparatorsAndEscapedStrings() throws {
        for json in ["{method=>head}", "{method:head;body:[]}", "{body:[1,,3,]}", "{# comment\nmethod:head}"] {
            XCTAssertEqual(UrlOptions.parse("u," + json).status, .lenient, json)
        }
        let result = UrlOptions.parse("u,{method=>head; # comment\n body:[1,,3,];charset:'UTF-8'}")
        XCTAssertEqual(result.status, .lenient)
        XCTAssertEqual(result.options.method, "HEAD")
        XCTAssertEqual(result.options.body, "[\n  1,\n  null,\n  3,\n  null\n]")
        XCTAssertEqual(try UrlOptions.fromJSON(#"{"body":"\uD83D\uDE00\n\"\\"}"#).body, "😀\n\"\\")
        XCTAssertEqual(UrlOptions.parse("u,{\"body\":\"\\'\"}").status, .lenient)
        XCTAssertEqual(UrlOptions.parse("u,{\"body\":\"a\\q\"}").status, .invalid)
    }

    func testHeaderNumberRepresentations() throws {
        XCTAssertEqual(try UrlOptions.fromJSON("{headers:{a:2.0,b:1e3}}").headers, ["a": "2.0", "b": "1000.0"])
        XCTAssertEqual(try UrlOptions.fromJSON("{headers:'{a:2.0,b:1e3}'}").headers, ["a": "2", "b": "1000"])
    }

    func testJVMDoubleExponentBoundaries() throws {
        for (input, expected) in [
            ("1e7", "1.0E7"), ("2.0", "2.0"), ("1e-5", "1.0E-5"), ("1e21", "1.0E21"),
            ("9999999.0", "9999999.0"), ("0.001", "0.001"), ("0.0009999", "9.999E-4"),
            ("-1e7", "-1.0E7"), ("-0.0", "-0.0"), ("10000000", "10000000"),
            ("9223372036854775807", "9223372036854775807")
        ] {
            let options = try UrlOptions.fromJSON("{headers:{n:\(input)},body:\(input)}")
            XCTAssertEqual(options.headers["n"], expected, input)
            XCTAssertEqual(options.body, expected, input)
        }
    }

    func testGsonLongSaturationPreservesOptions() throws {
        let cases: [(String, Int64)] = [
            ("9223372036854775806", Int64.max - 1), ("9223372036854775807", Int64.max),
            ("9223372036854775808", Int64.max), ("9223372036854775809", Int64.max),
            ("-9223372036854775807", Int64.min + 1), ("-9223372036854775808", Int64.min),
            ("-9223372036854775809", Int64.min), ("-9223372036854775810", Int64.min)
        ]
        for (input, expected) in cases {
            for value in [input, "\"\(input)\""] {
                let parsed = UrlOptions.parse("u,{\"method\":\"POST\",\"serverID\":\(value),\"webViewDelayTime\":\(value)}")
                XCTAssertEqual(parsed.status, .strict, value)
                XCTAssertEqual(parsed.options.method, "POST", value)
                XCTAssertEqual(parsed.options.serverID, expected, value)
                XCTAssertEqual(parsed.options.webViewDelayTime, max(0, expected), value)
            }
        }
        for value in ["9223372036854777856", "-9223372036854777856", "1e30", "1.5"] {
            for field in ["serverID", "webViewDelayTime"] {
                XCTAssertEqual(UrlOptions.parse("u,{\"\(field)\":\(value)}").status, .invalid, "\(field)=\(value)")
            }
        }
    }

    func testCombiningScalarAtStartOfString() throws {
        for value in ["\u{0301}x", #"\u0301x"#] {
            let parsed = UrlOptions.parse("u,{\"body\":\"\(value)\"}")
            XCTAssertEqual(parsed.status, .strict, value)
            XCTAssertEqual(parsed.options.body?.unicodeScalars.map(\.value), [0x301, 0x78], value)
        }
    }
}
