import Foundation
import JavaScriptCore
import CommonCrypto
import SwiftSoup
import CoreFoundation

@objc private protocol JavaElementExport: JSExport {
    func text() -> String
    func html() -> String
    func outerHtml() -> String
    func attr(_ name: String) -> String
}

/// 只桥接离线读取；列表保持原生 JS 数组，不模拟 java.util.List。
private final class JavaElement: NSObject, JavaElementExport {
    let element: Element
    init(_ element: Element) { self.element = element }
    private func read(_ operation: () throws -> String) -> String {
        do { return try operation() }
        catch {
            if let context = JSContext.current() {
                context.exception = JSValue(newErrorFromMessage: String(describing: error), in: context)
            }
            return ""
        }
    }
    func text() -> String { read { try element.text() } }
    func html() -> String { read { try element.html() } }
    func outerHtml() -> String { read { try element.outerHtml() } }
    func attr(_ name: String) -> String { read { try element.attr(name) } }
}

/// 规则与平台宿主；网络服务通过独立依赖对象注入。
public final class JavaHost {
    private let parser: AnalyzeRule?
    private let timeZone: TimeZone
    private let logger: (String) -> Void
    private let network: JavaHostNetwork

    public init(parser: AnalyzeRule?, timeZone: TimeZone, logger: @escaping (String) -> Void) {
        self.parser = parser
        self.timeZone = timeZone
        self.logger = logger
        self.network = JavaHostNetwork(engine: JsEngine(timeZone: timeZone, logger: logger))
    }

    init(parser: AnalyzeRule?, timeZone: TimeZone, logger: @escaping (String) -> Void, network: JavaHostNetwork) {
        self.parser = parser
        self.timeZone = timeZone
        self.logger = logger
        self.network = network
    }

    func install(in context: JSContext) {
        let invoke: @convention(block) (String, [Any]) -> Any? = { [self, weak context] method, arguments in
            do { return bridge(try call(method, arguments)) }
            catch {
                if let context { context.exception = JSValue(newErrorFromMessage: String(describing: error), in: context) }
                return nil
            }
        }
        context.setObject(invoke, forKeyedSubscript: "__legadoHost" as NSString)
        context.evaluateScript("""
        (function(invoke) {
            globalThis.java = {};
            function javaMap(values, ignoreCase) {
                const owns = key => Object.prototype.hasOwnProperty.call(values, key);
                function find(key) {
                    key = String(key);
                    if (owns(key)) return key;
                    return ignoreCase ? Object.keys(values).find(name => name.toLowerCase() === key.toLowerCase()) : undefined;
                }
                return new Proxy(values, {get: function(target, key) {
                    if (key === 'get') return name => { const found = find(name); return found === undefined ? null : values[found]; };
                    if (key === 'containsKey') return name => find(name) !== undefined;
                    if (key === 'keySet') return () => Object.keys(values);
                    if (key === 'size') return () => Object.keys(values).length;
                    return Reflect.get(target, key);
                }, has: (target, key) => ['get','containsKey','keySet','size'].includes(key) || Reflect.has(target, key)});
            }
            function callable(value) {
                return new Proxy(() => value, {get: function(target, key) {
                    if (key === Symbol.toPrimitive) return () => value !== null && typeof value === 'object' ? String(value) : value;
                    if (key === 'toString') return () => String(value);
                    if (key === 'valueOf' || key === 'toJSON') return () => value;
                    if (value !== null && value !== undefined && key in Object(value)) {
                        const member = value[key];
                        return typeof member === 'function' ? member.bind(value) : member;
                    }
                    return Reflect.get(target, key);
                }});
            }
            function response(value) {
                if (Array.isArray(value)) return value.map(response);
                if (!value || !value.__strResponse) return value;
                const headers = javaMap(value.headers, true);
                const result = {
                    body: callable(value.body), url: callable(value.url), code: callable(value.code),
                    headers: callable(headers), header: name => headers.get(name), raw: callable(value.raw),
                    callTime: value.callTime, isSuccessful: callable(value.isSuccessful)
                };
                if (value.__connectionResponse) {
                    const cookies = javaMap(value.cookies, false);
                    result.cookies = callable(cookies);
                    result.cookie = name => cookies.get(name);
                    result.statusCode = callable(value.code);
                }
                return result;
            }
            const methods = ['get','put','getString','getStringList','getElement','getElements','setContent',
                'timeFormat','log','toast','md5Encode','base64Decode','toNumChapter','aesBase64DecodeToString',
                'encodeURI','ajax','post','head','connect','ajaxAll','ajaxTestAll','getCookie','webView','readFile','downloadFile','cacheFile',
                'webViewGetSource','webViewGetOverrideUrl','getVerificationCode','startBrowser','startBrowserAwait','getWebViewUA'];
            methods.forEach(function(name) {
                java[name] = function() {
                    const args = Array.prototype.slice.call(arguments);
                    const headerIndex = name === 'post' ? 2 : (name === 'get' || name === 'head' ? 1 : -1);
                    if (headerIndex >= 0 && args[headerIndex] instanceof Map) args[headerIndex] = Object.fromEntries(args[headerIndex]);
                    if (name === 'put') {
                        if (args.length !== 2) throw new Error('未实现：java.put 重载');
                        args[0] = String(args[0]); args[1] = String(args[1]);
                    }
                    const value = response(invoke(name, args));
                    return name === 'setContent' ? java : value;
                };
            });
            const objects = {cookie:['getCookie','getKey','setCookie','replaceCookie','removeCookie'],
                cache:['put','get','getInt','getLong','getDouble','getFloat','delete']};
            Object.keys(objects).forEach(function(name) {
                globalThis[name] = {};
                objects[name].forEach(function(method) {
                    globalThis[name][method] = function() {
                        const args = Array.prototype.slice.call(arguments);
                        if (name === 'cache' && method === 'put' && args.length >= 2) args[1] = String(args[1]);
                        return invoke(name+'.'+method,args);
                    };
                });
            });
        })(__legadoHost);
        delete globalThis.__legadoHost;
        """)
    }

    func bridge(_ value: Any?) -> Any {
        if let element = value as? Element { return JavaElement(element) }
        if let list = value as? [Any] { return list.map { bridge($0) } }
        if let object = value as? [String: Any] { return object.mapValues { bridge($0) } }
        return value ?? NSNull()
    }

    static func nativeValue(_ value: Any?) -> Any? {
        if let element = value as? JavaElement { return element.element }
        if let list = value as? [Any] { return list.map { nativeValue($0) ?? NSNull() } }
        if let object = value as? [String: Any] { return object.mapValues { nativeValue($0) ?? NSNull() } }
        return value
    }

    private func call(_ method: String, _ arguments: [Any]) throws -> Any? {
        if ["webView", "webViewGetSource", "webViewGetOverrideUrl", "getVerificationCode", "startBrowser", "startBrowserAwait", "getWebViewUA"].contains(method) {
            return try network.callWebView(method, arguments)
        }
        if method.hasPrefix("cookie.") || method.hasPrefix("cache.") ||
            ["ajax", "ajaxAll", "ajaxTestAll", "connect", "post", "head", "getCookie", "downloadFile", "cacheFile"].contains(method) ||
            (method == "get" && arguments.count >= 2) {
            return try network.call(method, arguments)
        }
        func value(_ index: Int) -> Any? { index < arguments.count ? arguments[index] : nil }
        func string(_ index: Int) -> String { ruleText(value(index)) }
        func boolean(_ index: Int) -> Bool? {
            guard let number = value(index) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
            return number.boolValue
        }
        func analyzer() throws -> AnalyzeRule {
            guard let parser else { throw JsEngineError.unimplemented("java.\(method) 缺少 AnalyzeRule") }
            return parser
        }
        switch method {
        case "get": return try analyzer().get(string(0))
        case "put":
            try analyzer().put(string(0), value: string(1))
            return string(1)
        case "setContent":
            guard (1...2).contains(arguments.count), arguments.count == 1 || value(1) is String || value(1) is NSNull else {
                throw JsEngineError.unimplemented("java.setContent 重载")
            }
            guard let content = value(0), !(content is NSNull) else { throw JsEngineError.exception("内容不可空（Content cannot be null）") }
            let parser = try analyzer()
            parser.setContent(Self.nativeValue(content))
            if let baseUrl = value(1) as? String { parser.scriptBaseUrl = baseUrl }
            return nil
        case "getString":
            guard (1...3).contains(arguments.count), value(0) is String || value(0) is NSNull else {
                throw JsEngineError.unimplemented("java.getString 重载")
            }
            let rule = value(0) is NSNull ? nil : string(0)
            if arguments.count == 2, let unescape = boolean(1) { return try analyzer().getString(rule, unescape: unescape) }
            if arguments.count == 3 {
                guard let isUrl = boolean(2), !isUrl else { throw JsEngineError.unimplemented("java.getString isUrl 重载") }
            }
            return try analyzer().getString(rule, content: Self.nativeValue(value(1)))
        case "getStringList": return try analyzer().getStringList(string(0))
        case "getElement": return try analyzer().getElement(string(0))
        case "getElements": return try analyzer().getElements(string(0))
        case "log": logger(string(0)); return value(0)
        case "timeFormat":
            guard let time = value(0) as? NSNumber, time.doubleValue.isFinite else { throw JsEngineError.exception("timeFormat 需要毫秒数") }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy/MM/dd HH:mm"
            return formatter.string(from: Date(timeIntervalSince1970: time.doubleValue / 1000))
        case "md5Encode":
            let data = Data(string(0).utf8)
            var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            data.withUnsafeBytes { _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest) }
            return digest.map { String(format: "%02x", $0) }.joined()
        case "base64Decode":
            if value(0) == nil || value(0) is NSNull { return nil }
            let flags = (value(1) as? NSNumber)?.int32Value
            let encoding = flags == nil ? try charset(value(1).map { ruleText($0) } ?? "UTF-8") : .utf8
            var encoded = string(0).filter { !$0.isWhitespace }
            if flags == nil || flags! & 8 != 0 {
                encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            }
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let data = Data(base64Encoded: encoded), let decoded = String(data: data, encoding: encoding) else {
                throw JsEngineError.exception("base64Decode 无效输入")
            }
            return decoded
        case "encodeURI":
            guard let encoding = try? charset(value(1).map { ruleText($0) } ?? "UTF-8"),
                  let data = string(0).data(using: encoding, allowLossyConversion: true) else { return "" }
            return data.map { byte -> String in
                if byte == 32 { return "+" }
                if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 95, 46, 42].contains(byte) {
                    return String(UnicodeScalar(byte))
                }
                return String(format: "%%%02X", byte)
            }.joined()
        case "toNumChapter": return value(0) is NSNull ? nil : chapterNumber(string(0))
        case "aesBase64DecodeToString": return try decrypt(string(0), key: string(1), transformation: string(2), iv: string(3))
        default: throw JsEngineError.unimplemented("java.\(method)")
        }
    }

    private func charset(_ name: String) throws -> String.Encoding {
        switch name.uppercased() {
        case "GBK", "GB2312", "GB18030":
            let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard encoding != kCFStringEncodingInvalidId else { throw JsEngineError.unimplemented("字符集 \(name)") }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
        case "UTF-8", "UTF8": return .utf8
        case "UTF-16LE": return .utf16LittleEndian
        case "UTF-16BE": return .utf16BigEndian
        case "ISO-8859-1": return .isoLatin1
        case "US-ASCII", "ASCII": return .ascii
        default: throw JsEngineError.unimplemented("字符集 \(name)")
        }
    }

    private func decrypt(_ text: String, key: String, transformation: String, iv: String) throws -> String {
        let parts = transformation.uppercased().split(separator: "/")
        guard parts.count == 3, parts[0] == "AES", ["CBC", "ECB"].contains(parts[1]),
              ["PKCS5PADDING", "PKCS7PADDING", "NOPADDING"].contains(parts[2]) else {
            throw JsEngineError.unimplemented("AES transformation \(transformation)")
        }
        let keyData = Data(key.utf8), ivData = Data(iv.utf8)
        guard [16, 24, 32].contains(keyData.count), parts[1] == "ECB" || ivData.count == 16,
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else {
            throw JsEngineError.exception("AES 参数无效")
        }
        let options = (parts[1] == "ECB" ? CCOptions(kCCOptionECBMode) : 0) | (parts[2] == "NOPADDING" ? 0 : CCOptions(kCCOptionPKCS7Padding))
        var output = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var count = 0
        let status = keyData.withUnsafeBytes { keyBytes in
            ivData.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { bytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options,
                            keyBytes.baseAddress, keyData.count, parts[1] == "ECB" ? nil : ivBytes.baseAddress,
                            bytes.baseAddress, data.count, &output, capacity, &count)
                }
            }
        }
        guard status == kCCSuccess else { throw JsEngineError.exception("AES 解密失败：\(status)") }
        return String(decoding: output.prefix(count), as: UTF8.self)
    }

    private func chapterNumber(_ title: String) -> String {
        guard let match = title.range(of: "第(.+?)章", options: .regularExpression) else { return title }
        let number = String(title[match].dropFirst().dropLast()).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? ""
        let text = number.filter { !$0.isWhitespace }
        if let value = Int32(text) { return "第\(value)章" }
        let digits = Array("〇零一二三四五六七八九壹贰叁肆伍陆柒捌玖十拾百佰千仟万亿两")
        let values: [Int32] = [0,0,1,2,3,4,5,6,7,8,9,1,2,3,4,5,6,7,8,9,10,10,100,100,1000,1000,10000,100000000,2]
        let map = Dictionary(uniqueKeysWithValues: zip(digits, values))
        let chars = Array(text)
        var result: Int32 = 0, tmp: Int32 = 0, billion: Int32 = 0
        for (index, char) in chars.enumerated() {
            guard let n = map[char] else { return "第-1章" }
            if n == 100000000 { result = (result &+ tmp) &* n; billion = billion &* n &+ result; result = 0; tmp = 0 }
            else if n == 10000 { result = (result &+ tmp) &* n; tmp = 0 }
            else if n >= 10 { result = result &+ n &* (tmp == 0 ? 1 : tmp); tmp = 0 }
            else if index >= 2, index == chars.count - 1, let previous = map[chars[index - 1]], previous > 10 { tmp = n &* previous / 10 }
            else { tmp = tmp &* 10 &+ n }
        }
        return "第\(result &+ tmp &+ billion)章"
    }
}
