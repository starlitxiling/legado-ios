import Foundation
import JavaScriptCore

final class SourceScriptBridge {
    let repository: SourceStateRepository
    let source: BookSource
    let secrets: any SourceSecretStore
    var key: String { source.bookSourceUrl ?? "" }
    var secretKey: String { "source-login:" + key }
    init(source: BookSource, database: AppDatabase, secrets: any SourceSecretStore) {
        self.source = source; repository = SourceStateRepository(database: database); self.secrets = secrets
    }
    func read(_ name: String) throws -> String? {
        guard name == "loginInfo" else { return try repository.value(source: key, key: name) }
        if let legacy = try repository.value(source: key, key: name) {
            try secrets.write(legacy, account: secretKey)
            try repository.setValue(source: key, key: name, value: nil)
        }
        return try secrets.read(account: secretKey)
    }
    func write(_ name: String, value: String?) throws {
        if name == "loginInfo" {
            if let value { try secrets.write(value, account: secretKey) }
            else { try secrets.delete(account: secretKey) }
            try repository.setValue(source: key, key: name, value: nil)
        } else { try repository.setValue(source: key, key: name, value: value) }
    }
    func install(in context: JSContext, javaAliases: Bool = false) throws {
        _ = try read("loginInfo")
        let get: @convention(block) (String) -> String? = { name in
            do { return try self.read(name) }
            catch { Self.raise(error); return nil }
        }
        let put: @convention(block) (String, JSValue) -> Bool = { name, value in
            do { try self.write(name, value: value.isNull || value.isUndefined ? nil : value.toString()); return true }
            catch { Self.raise(error); return false }
        }
        context.setObject(get, forKeyedSubscript: "__sourceRead" as NSString)
        context.setObject(put, forKeyedSubscript: "__sourceWrite" as NSString)
        context.setObject(key, forKeyedSubscript: "__sourceKey" as NSString)
        context.setObject(source.bookSourceName ?? key, forKeyedSubscript: "__sourceName" as NSString)
        var loginCode = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if loginCode.lowercased().hasPrefix("@js:") { loginCode = String(loginCode.dropFirst(4)) }
        if loginCode.lowercased().hasPrefix("<js>"), loginCode.lowercased().hasSuffix("</js>") { loginCode = String(loginCode.dropFirst(4).dropLast(5)) }
        if loginCode.hasPrefix("http://") || loginCode.hasPrefix("https://") { loginCode = "" }
        context.setObject(loginCode, forKeyedSubscript: "__sourceLoginCode" as NSString)
        context.evaluateScript(Self.script)
        if javaAliases { context.evaluateScript("Object.keys(__sourceMethods).forEach(function(k){java[k]=source[k];});") }
        if let exception = context.exception { throw JsEngineError.exception(exception.toString()) }
    }
    private static func raise(_ error: Error) {
        if let context = JSContext.current() { context.exception = JSValue(newErrorFromMessage: String(describing: error), in: context) }
    }
    private static let script = """
    var __sourceMethods = {
      getVariable:function(){return __sourceRead('variable') || '';},
      setVariable:function(v){__sourceWrite('variable',v == null ? null : String(v));},
      getLoginHeader:function(){return __sourceRead('loginHeader');},
      putLoginHeader:function(v){var h=JSON.parse(String(v));__sourceWrite('loginHeader',String(v));Object.keys(h).forEach(function(k){if(k.toLowerCase()==='cookie')cookie.replaceCookie(__sourceKey,String(h[k]));});},
      removeLoginHeader:function(){__sourceWrite('loginHeader',null);cookie.removeCookie(__sourceKey);},
      getLoginInfo:function(){return __sourceRead('loginInfo');},
      getLoginInfoMap:function(){var v=JSON.parse(__sourceRead('loginInfo') || '{}');Object.defineProperty(v,'get',{value:function(k){return Object.prototype.hasOwnProperty.call(this,k)?this[k]:null;}});return v;},
      putLoginInfo:function(v){return __sourceWrite('loginInfo',String(v));},
      removeLoginInfo:function(){__sourceWrite('loginInfo',null);},
      put:function(k,v){__sourceWrite('v_'+k,String(v));return String(v);},
      get:function(k){return __sourceRead('v_'+k) || '';},
      getKey:function(){return __sourceKey;},getTag:function(){return __sourceName;},
      login:function(){return eval(__sourceLoginCode+'\\nif(typeof login !== "function")throw "Function login not implements";login();');}
    };
    __sourceMethods.putVariable=__sourceMethods.setVariable;
    var source=Object.assign(source || {},__sourceMethods);
    var sourceApi=source;
    """
}
