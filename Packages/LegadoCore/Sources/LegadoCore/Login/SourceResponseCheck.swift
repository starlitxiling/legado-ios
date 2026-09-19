import Foundation

enum SourceResponseCheck {
    static func check(source: BookSource, response: StrResponse,
                      evaluate: (String, [String: Any]) async throws -> Any?) async throws -> StrResponse {
        guard let code = source.loginCheckJs, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return response }
        let loginCode = SourceLogin.loginScript(source)
        let definitions = loginCode.hasPrefix("http://") || loginCode.hasPrefix("https://") ? "" : loginCode
        let setup = definitions + "\n" + """
        var result = {
            body:function(){return __response.body}, code:function(){return __response.code},
            url:function(){return __response.url}, headers:function(){return __response.headers},
            header:function(name){var key=Object.keys(__response.headers).find(k=>k.toLowerCase()===String(name).toLowerCase());return key===undefined?null:__response.headers[key]},
            isSuccessful:function(){return __response.code>=200&&__response.code<300}
        };
        var __checked = eval(__checkCode);
        if (__checked === false || __checked == null) throw 'Login check rejected';
        ({body:typeof __checked.body === 'function' ? String(__checked.body()) : __response.body,
          code:typeof __checked.code === 'function' ? Number(__checked.code()) : __response.code,
          url:typeof __checked.url === 'function' ? String(__checked.url()) : __response.url});
        """
        let data: [String: Any] = ["body": response.body, "code": response.code, "url": response.url, "headers": response.headers]
        let value = try await evaluate(setup, ["__response": data, "__checkCode": SourceLogin.script(code)])
        guard let checked = value as? [String: Any], let body = checked["body"] as? String,
              let status = checked["code"] as? NSNumber, let address = checked["url"] as? String,
              let url = URL(string: address) else { throw SourceLoginError.rejected }
        let raw = HttpResponse(status: status.intValue, body: response.raw.body, finalURL: url, headers: response.headers)
        return StrResponse(raw: raw, body: body)
    }
}
