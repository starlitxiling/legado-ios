import Foundation
import CryptoKit

final class JavaHostNetwork {
    let engine: JsEngine
    init(engine: JsEngine) { self.engine = engine }

    func call(_ method: String, _ arguments: [Any]) throws -> Any? {
        func value(_ index: Int) -> Any? { arguments.indices.contains(index) ? arguments[index] : nil }
        func string(_ index: Int) -> String { ruleText(value(index)) }
        func integer(_ index: Int) -> Int64? { (value(index) as? NSNumber)?.int64Value }
        func require(_ range: ClosedRange<Int>) throws {
            guard range.contains(arguments.count) else { throw JsEngineError.exception("\(method) 参数数量无效") }
        }
        if method.hasPrefix("cookie.") {
            try require(["cookie.getCookie", "cookie.removeCookie"].contains(method) ? 1...1 : 2...2)
            let store = engine.cookieStore
            let url = string(0), key = string(1), cookie = value(1) is NSNull ? nil : value(1).map(ruleText)
            return try HostAsyncBridge.wait {
                switch method {
                case "cookie.getCookie": return await store.getCookie(url: url)
                case "cookie.getKey": return await store.getKey(url: url, key: key)
                case "cookie.setCookie": await store.setCookie(url: url, cookie: cookie)
                case "cookie.replaceCookie": await store.replaceCookie(url: url, cookie: key)
                case "cookie.removeCookie": await store.removeCookie(url: url)
                default: throw JsEngineError.unimplemented(method)
                }
                return nil
            } as String?
        }
        if method.hasPrefix("cache.") {
            try require(method == "cache.put" ? 2...3 : (method == "cache.get" ? 1...2 : 1...1))
            let cache = engine.cacheManager, key = string(0), text = string(1)
            let time = Int32(truncatingIfNeeded: integer(2) ?? 0), onlyDisk = value(1) as? Bool ?? false
            return try HostAsyncBridge.wait { () async throws -> Any? in
                switch method {
                case "cache.put": try await cache.put(key, value: text, saveTime: time)
                case "cache.get": return try await cache.get(key, onlyDisk: onlyDisk)
                case "cache.getInt": return try await cache.getInt(key)
                case "cache.getLong": return try await cache.getLong(key)
                case "cache.getDouble": return try await cache.getDouble(key)
                case "cache.getFloat": return try await cache.getFloat(key)
                case "cache.delete": try await cache.delete(key)
                default: throw JsEngineError.unimplemented(method)
                }
                return nil
            }
        }
        switch method {
        case "getCookie":
            try require(1...2)
            let url = string(0), key = value(1) is NSNull ? nil : value(1).map(ruleText), store = engine.cookieStore
            return try HostAsyncBridge.wait {
                if let key { return await store.getKey(url: url, key: key) }
                return await store.getCookie(url: url)
            }
        case "ajax", "connect":
            try require(method == "ajax" ? 1...2 : 1...3)
            let input = method == "ajax" ? (value(0) as? [Any]).map { ruleText($0.first) } ?? string(0) : string(0)
            let headers = method == "connect" && value(1) is String ? try? Self.headers(value(1), allowMap: false) : nil
            // Kotlin 在 runCatching 之前创建 AnalyzeUrl，URL 脚本错误不可转成网络错误正文。
            let executor = try AnalyzeUrlExecutor(input, engine: engine, headers: headers,
                                                  callTimeout: integer(method == "ajax" ? 1 : 2))
            do {
                let response = try HostAsyncBridge.wait { try await executor.getStrResponse() }
                return method == "ajax" ? response.body : Self.bridge(response)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                let message = Self.errorText(error)
                engine.logger("\(method)(\(input)) error\n\(message)")
                if method == "ajax" { return message }
                let url = URL(string: executor.url).flatMap { ["http", "https"].contains($0.scheme) ? $0 : nil } ?? URL(string: "http://localhost/")!
                return Self.bridge(.init(raw: HttpResponse(status: 200, finalURL: url), body: message))
            }
        case "ajaxAll", "ajaxTestAll":
            try require(method == "ajaxAll" ? 1...2 : 2...3)
            guard let urls = value(0) as? [String] else { throw JsEngineError.exception("\(method) 需要 URL 数组") }
            let executors = try urls.map { try AnalyzeUrlExecutor($0, engine: engine, callTimeout: method == "ajaxTestAll" ? integer(1) : nil) }
            let skip = value(method == "ajaxAll" ? 1 : 2) as? Bool ?? false
            let concurrency = max(1, engine.networkConcurrency)
            let responses = try HostAsyncBridge.wait {
                try await withThrowingTaskGroup(of: (Int, AnalyzeUrlExecutor.Response).self) { group in
                    var results = [AnalyzeUrlExecutor.Response?](repeating: nil, count: executors.count)
                    var next = 0
                    func add(_ index: Int) {
                        group.addTask { (index, try await executors[index].getStrResponseAwait(isTest: method == "ajaxTestAll", skipRateLimit: skip)) }
                    }
                    while next < min(concurrency, executors.count) { add(next); next += 1 }
                    while let (index, response) = try await group.next() {
                        results[index] = response
                        if next < executors.count { add(next); next += 1 }
                    }
                    return results.map { $0! }
                }
            }
            return responses.map(Self.bridge)
        case "get", "head", "post":
            try require(method == "post" ? 3...4 : 2...3)
            let headers = try Self.headers(value(method == "post" ? 2 : 1))
            let input = string(0), body = method == "post" ? Data(string(1).utf8) : nil
            guard let url = URL(string: input), ["http", "https"].contains(url.scheme), url.host != nil else {
                throw JsEngineError.exception("无效 URL：\(input)")
            }
            let timeoutMillis = integer(method == "post" ? 3 : 2) ?? 30_000
            guard timeoutMillis >= 0 else { throw JsEngineError.exception("timeout 不可为负数") }
            let timeout = timeoutMillis == 0 ? TimeInterval.greatestFiniteMagnitude : Double(timeoutMillis) / 1000
            var requestHeaders = headers
            if requestHeaders.httpHeader("User-Agent") == nil { requestHeaders["User-Agent"] = UrlRequestBuilder.defaultUserAgent }
            if method == "post", requestHeaders.httpHeader("Content-Type") == nil { requestHeaders["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8" }
            let request = HttpRequest(url: url, method: method.uppercased(), headers: requestHeaders, body: body,
                                      timeout: timeout, callTimeout: timeout, followRedirects: false,
                                      enabledCookieJar: engine.networkSource.enabledCookieJar)
            let client = engine.httpClient, store = engine.cookieStore, source = engine.networkSource, limiter = engine.rateLimiter
            let response = try HostAsyncBridge.wait {
                try await limiter.acquire(key: source.key, rate: source.concurrentRate)
                return try await client.send(request, cookieStore: store)
            }
            guard response.status >= 200 && response.status < 400 else {
                throw JsEngineError.exception("HTTP error fetching URL. Status=\(response.status), URL=[\(url.absoluteString)]")
            }
            var object = Self.bridge(.init(raw: response, body: method == "head" ? "" : try ResponseDecoder.decode(response.body, headers: response.headers)))
            object["__connectionResponse"] = true
            let cookies = response.headers.httpHeader("Set-Cookie").map {
                HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": $0], for: response.finalURL)
            } ?? []
            object["cookies"] = Dictionary(cookies.map { ($0.name, $0.value) }, uniquingKeysWith: { _, new in new })
            return object
        case "downloadFile", "cacheFile":
            try require(1...2)
            let input = method == "downloadFile" && arguments.count == 2 ? string(1) : string(0)
            let executor = try AnalyzeUrlExecutor(input, engine: engine)
            let digest = Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
            let key = String(digest.dropFirst(8).prefix(16))
            let extensionName = URL(string: UrlOptions.parse(input).url)?.pathExtension ?? ""
            let validExtension = extensionName.range(of: "^[a-zA-Z0-9]{1,5}$", options: .regularExpression) != nil
            let suffix = executor.options.type ?? (validExtension ? extensionName : "ext")
            let path = "/\(key).\(suffix)"
            let store = engine.downloadStore, cache = engine.cacheManager
            let saveTime = Int32(truncatingIfNeeded: integer(1) ?? 0)
            if method == "downloadFile", arguments.count == 2 {
                guard executor.options.type != nil else { return "" }
                let text = Array(string(0))
                guard text.count.isMultiple(of: 2) else { throw JsEngineError.exception("无效十六进制数据") }
                let bytes = try stride(from: 0, to: text.count, by: 2).map { index -> UInt8 in
                    guard let byte = UInt8(String(text[index...index + 1]), radix: 16) else { throw JsEngineError.exception("无效十六进制数据") }
                    return byte
                }
                return try HostAsyncBridge.wait { try await store.save(Data(bytes), path: path) }
            }
            return try HostAsyncBridge.wait {
                if method == "cacheFile", let cached = try await cache.get(key), let bytes = try await store.read(cached) {
                    return try ResponseDecoder.decode(bytes, headers: [:])
                }
                let data = try await executor.getByteArray()
                let saved = try await store.save(data, path: path)
                if method == "downloadFile" { return saved }
                try await cache.put(key, value: saved, saveTime: saveTime)
                return try ResponseDecoder.decode(data, headers: [:])
            }
        default: throw JsEngineError.unimplemented("java.\(method)")
        }
    }

    private static func headers(_ input: Any?, allowMap: Bool = true) throws -> [String: String] {
        guard let input, !(input is NSNull) else { return [:] }
        let object: [String: Any]
        if let text = input as? String, let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] { object = parsed }
        else if allowMap, let parsed = input as? [String: Any] { object = parsed }
        else { throw JsEngineError.exception("Request headers must be a map or JSON string") }
        return try object.mapValues {
            guard !($0 is NSNull) else { throw JsEngineError.exception("Request header names and values cannot be null") }
            return ruleText($0)
        }
    }

    private static func bridge(_ response: AnalyzeUrlExecutor.Response) -> [String: Any] {
        ["__strResponse": true, "body": response.body, "url": response.url, "code": response.code, "headers": response.headers,
         "callTime": response.callTime, "isSuccessful": response.isSuccessful,
         "raw": ["url": response.url, "code": response.code, "headers": response.headers, "body": Array(response.raw.body)]]
    }

    private static func errorText(_ error: Error) -> String {
        String(describing: error) + "\n" + Thread.callStackSymbols.joined(separator: "\n")
    }
}
