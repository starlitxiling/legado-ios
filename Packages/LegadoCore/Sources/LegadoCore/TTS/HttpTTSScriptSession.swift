import Foundation
import JavaScriptCore

final class HttpTTSScriptSession {
    let engine: JsEngine
    private let source: HttpTTS
    private let bridge: SourceScriptBridge
    init(source: HttpTTS, database: AppDatabase, client: any HttpClient, cookies: CookieStore, secrets: any SourceSecretStore) throws {
        self.source = source
        var bookSource = BookSource()
        bookSource.bookSourceUrl = "httpTts:\(source.id)"; bookSource.bookSourceName = source.name
        bookSource.loginUrl = source.loginUrl; bookSource.loginUi = source.loginUi; bookSource.loginCheckJs = source.loginCheckJs
        bookSource.header = source.header; bookSource.jsLib = source.jsLib
        bookSource.concurrentRate = source.concurrentRate; bookSource.enabledCookieJar = source.enabledCookieJar
        bridge = SourceScriptBridge(source: bookSource, database: database, secrets: secrets)
        engine = JsEngine(baseUrl: source.url, httpClient: client, cookieStore: cookies,
            networkSource: .init(key: "httpTts:\(source.id)", enabledCookieJar: source.enabledCookieJar ?? false, concurrentRate: source.concurrentRate))
        let bridge = bridge, fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source))
        engine.sourceBindingInstaller = { [weak engine] context in
            try bridge.install(in: context, engine: engine)
            context.setObject(fields, forKeyedSubscript: "__ttsFields" as NSString)
            context.evaluateScript("Object.assign(source, __ttsFields);")
        }
        if let library = source.jsLib, !library.isEmpty {
            engine.libraryInitializer = { context in
                context.evaluateScript(library)
                if let exception = context.exception { throw JsEngineError.exception(exception.toString() ?? "TTS jsLib") }
            }
        }
    }
    func executor(text: String, speed: Int) throws -> AnalyzeUrlExecutor {
        let bindings: [String: Any] = ["speakText": text, "speakSpeed": speed]
        var headers: [String: String] = [:]
        if let header = source.header, !header.isEmpty {
            let value = header.hasPrefix("@js:") ? String(describing: try engine.evaluateScript(String(header.dropFirst(4)), bindings: bindings) ?? "{}") : header
            headers = try JSONDecoder().decode([String: String].self, from: Data(value.utf8))
        }
        if let login = try bridge.read("loginHeader") {
            for (key, value) in try JSONDecoder().decode([String: String].self, from: Data(login.utf8)) { headers.setHTTPHeader(key, value) }
        }
        return try AnalyzeUrlExecutor(source.url, engine: engine, bindings: bindings, headers: headers, callTimeout: 300_000)
    }
    func check(_ response: HttpResponse) throws -> HttpResponse {
        guard let code = source.loginCheckJs, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return response }
        let script = Self.script(code)
        let login = Self.script(source.loginUrl ?? "")
        let definitions = login.hasPrefix("http://") || login.hasPrefix("https://") ? "" : login
        let setup = definitions + "\n" + """
        var result = {code:function(){return __code},url:function(){return __url},
          header:function(k){return __headers[k]}, headers:function(){return __headers},
          isSuccessful:function(){return __code>=200&&__code<300},
          body:function(){return {string:function(){return __body},bytes:function(){return __bytes}}}};
        var original=result;
        var checked=eval(__check);
        if(checked==null || checked===false) throw 'Login check rejected';
        var same=checked===original;
        if (!same && typeof checked.raw==='function') checked=checked.raw();
        var body=same?null:(typeof checked.body==='function'?checked.body():checked.body);
        ({same:same,code:typeof checked.code==='function'?Number(checked.code()):(checked.code==null?__code:Number(checked.code)),
          url:typeof checked.url==='function'?String(checked.url()):(checked.url || __url),
          headers:typeof checked.headers==='function'?checked.headers():(checked.headers || __headers),
          body:body&&typeof body.bytes==='function'?body.bytes():body});
        """
        let value = try engine.evaluateScript(setup, bindings: ["__code": response.status, "__url": response.finalURL.absoluteString,
            "__headers": response.headers, "__body": String(decoding: response.body, as: UTF8.self), "__bytes": Array(response.body), "__check": script])
        guard let result = value as? [String: Any], let status = result["code"] as? NSNumber,
              let address = result["url"] as? String, let url = URL(string: address) else { throw SourceLoginError.rejected }
        let body: Data
        if (result["same"] as? Bool) == true { body = response.body }
        else if let bytes = result["body"] as? [NSNumber] { body = Data(bytes.map { UInt8(truncating: $0) }) }
        else if let text = result["body"] as? String { body = Data(text.utf8) }
        else { throw SourceLoginError.rejected }
        return HttpResponse(status: status.intValue, body: body, finalURL: url, headers: result["headers"] as? [String: String] ?? response.headers)
    }
    private static func script(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("@js:") { return String(text.dropFirst(4)) }
        if text.hasPrefix("<js>"), text.hasSuffix("</js>") { return String(text.dropFirst(4).dropLast(5)) }
        return text
    }
}
