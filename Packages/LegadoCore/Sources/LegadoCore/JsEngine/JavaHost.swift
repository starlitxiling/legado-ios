import Foundation
import JavaScriptCore
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
    private weak var parser: AnalyzeRule?
    private let crypto = JavaHostCrypto()
    private let platformServices: JsPlatformServices
    private let extraParams: [String: String]
    private let timeZone: TimeZone
    private let logger: (String) -> Void
    private let network: JavaHostNetwork

    public init(parser: AnalyzeRule?, timeZone: TimeZone, logger: @escaping (String) -> Void) {
        self.parser = parser
        self.platformServices = .shared
        self.extraParams = [:]
        self.timeZone = timeZone
        self.logger = logger
        self.network = JavaHostNetwork(engine: JsEngine(timeZone: timeZone, logger: logger))
    }

    init(parser: AnalyzeRule?, timeZone: TimeZone, logger: @escaping (String) -> Void, network: JavaHostNetwork, extraParams: [String: String] = [:], platformServices: JsPlatformServices = .shared) {
        self.parser = parser
        self.platformServices = platformServices
        self.extraParams = extraParams
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
            globalThis.com = {jayway: {jsonpath: {JsonPath: {
                read: function(content, path) { return invoke('jsonPathRead', [content, path]); }
            }}}};
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
            function nativeArguments(args) {
                return Array.prototype.map.call(args, function(value) {
                    if (ArrayBuffer.isView(value)) return Array.from(new Uint8Array(value.buffer,value.byteOffset,value.byteLength));
                    if (value instanceof ArrayBuffer) return Array.from(new Uint8Array(value));
                    return value;
                });
            }
            function response(value) {
                if (value && value.__legadoBytes) return new Uint8Array(value.__legadoBytes);
                if (value && value.__legadoKeyBytes) return {
                    getEncoded: () => new Uint8Array(value.__legadoKeyBytes),
                    getAlgorithm: () => value.algorithm, getFormat: () => value.format
                };
                if (value && value.__legadoCrypto !== undefined) {
                    const object = {};
                    value.methods.forEach(function(name) {
                        object[name] = function() {
                            const result = response(invoke('crypto.'+name,[value.__legadoCrypto].concat(nativeArguments(arguments))));
                            return name.startsWith('set') ? object : result;
                        };
                    });
                    return object;
                }
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
            const methods = ['get','put','getString','getStringList','getElement','getElements','getElementsRaw','cacheContent','reGetBook','refreshTocUrl','setContent',
                'timeFormat','timeFormatUTC','log','toast','longToast','logType','randomUUID','androidId',
                'getReadBookConfig','getReadBookConfigMap','getThemeMode','getThemeConfig','getThemeConfigMap',
                'base64DecodeToByteArray','hexDecodeToByteArray','hexEncodeToString','strToBytes','bytesToStr','decodeURI','htmlFormat','toURL','base64Decode','base64Encode','hexDecodeToString','toNumChapter',
                'encodeURI','ajax','post','head','connect','ajaxAll','ajaxTestAll','getCookie','webView','readFile','downloadFile','cacheFile',
                'webViewGetSource','webViewGetOverrideUrl','getVerificationCode','startBrowser','startBrowserAwait','getWebViewUA'].concat(\(JavaHostCrypto.methods.map { "'" + $0 + "'" }.joined(separator: ",")));
            methods.forEach(function(name) {
                java[name] = function() {
                    const args = nativeArguments(arguments);
                    const headerIndex = name === 'post' ? 2 : (name === 'get' || name === 'head' ? 1 : -1);
                    if (headerIndex >= 0 && args[headerIndex] instanceof Map) args[headerIndex] = Object.fromEntries(args[headerIndex]);
                    if (name === 'put') {
                        if (args.length !== 2) throw new Error('未实现：java.put 重载');
                        args[0] = String(args[0]); args[1] = String(args[1]);
                    }
                    if (name === 'toast' || name === 'longToast') {
                        args[0] = String(args[0]);
                        args[1] = String(typeof source === 'object' && source != null
                            ? (source.bookSourceName == null ? source.sourceName == null ? null : source.sourceName : source.bookSourceName) : null);
                    }
                    if (name === 'logType') {
                        const value = args[0], type = typeof value;
                        args[0] = value === null ? 'null' : type === 'undefined' ? 'org.htmlunit.corejs.javascript.Undefined'
                            : type === 'string' ? 'java.lang.String' : type === 'boolean' ? 'java.lang.Boolean'
                            : type === 'number' ? 'java.lang.Double' : Array.isArray(value) ? 'org.htmlunit.corejs.javascript.NativeArray'
                            : type === 'function' ? 'org.htmlunit.corejs.javascript.InterpretedFunction'
                            : 'org.htmlunit.corejs.javascript.NativeObject';
                    }
                    const value = response(invoke(name, args));
                    if (name === 'toURL' && value.searchParams != null) value.searchParams = javaMap(value.searchParams, false);
                    if (name === 'getReadBookConfigMap' || name === 'getThemeConfigMap') return javaMap(value, false);
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
        if let data = value as? Data { return ["__legadoBytes": Array(data).map(Int.init)] }
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
        if JavaHostCrypto.methods.contains(method) || method.hasPrefix("crypto.") {
            return try crypto.call(method, arguments: arguments)
        }
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
        case "jsonPathRead": return try AnalyzeByJSonPath(value(0) ?? NSNull()).getObject(string(1))
        case "get":
            if let value = extraParams[string(0)] { return value }
            return try analyzer().get(string(0))
        case "put":
            try analyzer().put(string(0), value: string(1))
            return string(1)
        case "setContent":
            guard (1...2).contains(arguments.count), arguments.count == 1 || value(1) is String || value(1) is NSNull else {
                throw JsEngineError.unimplemented("java.setContent 重载")
            }
            guard let content = value(0), !(content is NSNull) else { throw JsEngineError.exception("内容不可空（Content cannot be null）") }
            let parser = try analyzer()
            try parser.setContent(JsObject.snapshot(Self.nativeValue(content)), baseUrl: value(1) as? String)
            return nil
        case "getString":
            guard (1...3).contains(arguments.count), value(0) is String || value(0) is NSNull else {
                throw JsEngineError.unimplemented("java.getString 重载")
            }
            let rule = value(0) is NSNull ? nil : string(0)
            if arguments.count == 2, let unescape = boolean(1) { return try analyzer().getString(rule, unescape: unescape) }
            guard arguments.count < 3 || boolean(2) != nil else { throw JsEngineError.unimplemented("java.getString isUrl 重载") }
            return try analyzer().getString(rule, content: JsObject.snapshot(Self.nativeValue(value(1))), isURL: boolean(2) ?? false)
        case "getStringList":
            guard (1...3).contains(arguments.count), value(0) is String || value(0) is NSNull,
                  arguments.count < 3 || boolean(2) != nil else { throw JsEngineError.unimplemented("java.getStringList 重载") }
            return try analyzer().getStringList(value(0) is NSNull ? nil : string(0),
                content: JsObject.snapshot(Self.nativeValue(value(1))), isURL: boolean(2) ?? false)
        case "getElement": return try analyzer().getElement(string(0))
        case "getElements": return try analyzer().getElements(string(0))
        case "cacheContent":
            guard arguments.count == 2, let batch = try analyzer().batchContent else {
                throw JsEngineError.exception("java.cacheContent requires a chapter and content inside a batch rule")
            }
            return try batch.saveContent(identifier: Self.nativeValue(value(0)), content: string(1))
        case "getElementsRaw": return try analyzer().getElementsRaw(string(0))
        case "reGetBook", "refreshTocUrl":
            guard arguments.isEmpty else { throw JsEngineError.exception("java.\(method) takes no arguments") }
            let parser = try analyzer()
            if method == "reGetBook" { try parser.reGetBook() } else { try parser.refreshTocUrl() }
            if let context = JSContext.current(), let book = try parser.scriptBindings["book"] {
                context.setObject(book, forKeyedSubscript: "book" as NSString)
                network.engine.freezeEntities(in: context)
            }
            return nil
        case "log": logger(string(0)); return value(0)
        case "logType": logger(string(0)); return nil
        case "toast", "longToast":
            platformServices.showToast(string(1) + ": " + string(0), long: method == "longToast", logger: logger)
            return nil
        case "randomUUID": return UUID().uuidString.lowercased()
        case "androidId": return platformServices.identifier()
        case "getThemeMode": return platformServices.appearance().mode
        case "getReadBookConfig", "getReadBookConfigMap", "getThemeConfig", "getThemeConfigMap":
            let text = try method.hasPrefix("getReadBookConfig") ? platformServices.readingConfiguration() : platformServices.appearance().configuration
            if method.hasSuffix("Map") {
                guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                    throw JsEngineError.exception("\(method) requires a JSON object")
                }
                return object
            }
            return text
        case "strToBytes": return try JavaHostEncoding.encode(string(0), charset: value(1).map { ruleText($0) } ?? "UTF-8")
        case "bytesToStr": return try JavaHostEncoding.decode(JavaHostEncoding.bytes(value(0)), charset: value(1).map { ruleText($0) } ?? "UTF-8")
        case "base64DecodeToByteArray":
            guard let input = value(0), !(input is NSNull), !string(0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try JavaHostEncoding.base64(string(0), flags: (value(1) as? NSNumber)?.intValue ?? 0)
        case "hexDecodeToByteArray": return string(0).isEmpty ? nil : try JavaHostEncoding.hex(string(0))
        case "hexEncodeToString": return Data(string(0).utf8).map { String(format: "%02x", $0) }.joined()
        case "decodeURI": return try JavaHostEncoding.decodeURI(string(0), charset: value(1).map { ruleText($0) } ?? "UTF-8")
        case "htmlFormat": return HtmlFormatter.formatKeepImg(string(0), redirectUrl: (value(1) as? String).flatMap(URL.init(string:)))
        case "toURL": return try JavaHostEncoding.url(string(0), base: value(1) as? String)
        case "timeFormat", "timeFormatUTC":
            if method == "timeFormatUTC", arguments.count < 3 {
                throw JsEngineError.exception("timeFormatUTC requires time, format and offset milliseconds")
            }
            return try JavaHostTime.format(value(0), pattern: value(1) as? String ?? "yyyy/MM/dd HH:mm", timeZone: timeZone,
                offset: method == "timeFormatUTC" ? value(2) : nil)
        case "base64Encode":
            let flags = (value(1) as? NSNumber)?.intValue ?? 2
            var encoded = Data(string(0).utf8).base64EncodedString()
            if flags & 8 != 0 { encoded = encoded.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") }
            if flags & 1 != 0 { encoded = encoded.replacingOccurrences(of: "=", with: "") }
            if flags & 2 == 0, !encoded.isEmpty {
                let characters = Array(encoded)
                let separator = flags & 4 != 0 ? "\r\n" : "\n"
                encoded = stride(from: 0, to: characters.count, by: 76).map {
                    String(characters[$0..<min($0 + 76, characters.count)])
                }.joined(separator: separator) + separator
            }
            return encoded
        case "hexDecodeToString": return string(0).isEmpty ? nil : try JavaHostEncoding.decode(JavaHostEncoding.hex(string(0)))
        case "base64Decode":
            if value(0) == nil || value(0) is NSNull { return nil }
            let flags = (value(1) as? NSNumber)?.int32Value
            let encoding = flags == nil ? try JavaHostEncoding.charset(value(1).map { ruleText($0) } ?? "UTF-8") : .utf8
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
            guard let encoding = try? JavaHostEncoding.charset(value(1).map { ruleText($0) } ?? "UTF-8"),
                  let data = string(0).data(using: encoding, allowLossyConversion: true) else { return "" }
            return data.map { byte -> String in
                if byte == 32 { return "+" }
                if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45, 95, 46, 42].contains(byte) {
                    return String(UnicodeScalar(byte))
                }
                return String(format: "%%%02X", byte)
            }.joined()
        case "toNumChapter": return value(0) is NSNull ? nil : chapterNumber(string(0))
        default: throw JsEngineError.unimplemented("java.\(method)")
        }
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
