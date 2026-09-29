import Foundation
import JavaScriptCore

enum CryptoJSLibrary {
    private static let script = Result<String, Error> {
        guard let url = Bundle.module.url(forResource: "crypto-js", withExtension: "js") else {
            throw JsEngineError.exception("Missing bundled CryptoJS resource")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func install(in context: JSContext) {
        let load: @convention(block) () -> Void = { [weak context] in
            guard let context else { return }
            do { context.evaluateScript(try script.get()) }
            catch { context.exception = JSValue(newErrorFromMessage: String(describing: error), in: context) }
        }
        let random: @convention(block) (Int) -> [UInt8]? = { [weak context] count in
            do { return Array(try JavaHostCrypto.random(count)) }
            catch {
                if let context { context.exception = JSValue(newErrorFromMessage: String(describing: error), in: context) }
                return nil
            }
        }
        context.setObject(load, forKeyedSubscript: "__loadCryptoJS" as NSString)
        context.setObject(random, forKeyedSubscript: "__cryptoRandom" as NSString)
        context.evaluateScript("""
        (function(load,random) {
            if (typeof globalThis.crypto === 'undefined') {
                globalThis.crypto = {getRandomValues:function(array) {
                    if (!ArrayBuffer.isView(array) || array instanceof DataView || array instanceof Float32Array || array instanceof Float64Array)
                        throw new TypeError('Expected an integer typed array');
                    new Uint8Array(array.buffer,array.byteOffset,array.byteLength).set(random(array.byteLength));
                    return array;
                }};
            }
            Object.defineProperty(globalThis,'CryptoJS',{configurable:true,get:function() {
                delete globalThis.CryptoJS;
                load();
                return globalThis.CryptoJS;
            },set:function(value) {
                Object.defineProperty(globalThis,'CryptoJS',{value:value,writable:true,configurable:true});
            }});
        })(__loadCryptoJS,__cryptoRandom);
        delete globalThis.__loadCryptoJS;
        delete globalThis.__cryptoRandom;
        """)
    }
}
