import Foundation
import JavaScriptCore

final class SourceScriptBridge {
    let repository: SourceStateRepository
    let source: BookSource
    let secrets: any SourceSecretStore
    private let api = JsSourceApi()
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
    func install(in context: JSContext, engine: JsEngine? = nil, javaAliases: Bool = false) throws {
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
        context.setObject(try WebBookContext.object(source), forKeyedSubscript: "__sourceFields" as NSString)
        context.evaluateScript("var source=Object.assign({},__sourceFields,source || {});")
        api.installMethods(in: context, engine: engine, refreshExplore: {
            let source = self.source, repository = self.repository
            try HostAsyncBridge.wait { try await ExploreKinds.clearCache(source: source, stateRepository: repository) }
        })
        if javaAliases { context.evaluateScript("Object.keys(__sourceMethods).forEach(function(k){java[k]=source[k];});") }
        if let exception = context.exception { throw JsEngineError.exception(exception.toString()) }
    }
    private static func raise(_ error: Error) {
        if let context = JSContext.current() { context.exception = JSValue(newErrorFromMessage: String(describing: error), in: context) }
    }
}
