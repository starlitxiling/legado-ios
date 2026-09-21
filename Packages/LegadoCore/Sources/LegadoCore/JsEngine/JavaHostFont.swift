import Foundation
import CryptoKit

final class JavaHostFont {
    static let methods = ["queryTTF", "queryBase64TTF", "replaceFont"]
    private final class Entry: NSObject { let font: QueryTTF; init(_ font: QueryTTF) { self.font = font } }
    private static let cache: NSCache<NSString, Entry> = { let cache = NSCache<NSString, Entry>(); cache.countLimit = 16; return cache }()
    private var handles: [QueryTTF] = []

    func call(_ method: String, arguments: [Any], network: JavaHostNetwork, bindings: [String: Any]) throws -> Any? {
        func value(_ index: Int) -> Any? { arguments.indices.contains(index) ? arguments[index] : nil }
        func font(_ index: Int) -> QueryTTF? {
            guard let marker = value(index) as? [String: Any], let id = marker["__legadoFont"] as? Int, handles.indices.contains(id) else { return nil }
            return handles[id]
        }
        if method == "replaceFont" {
            let text = ruleText(value(0))
            guard let error = font(1), let correct = font(2) else { return text }
            let filter = value(3) as? Bool ?? false
            return text.unicodeScalars.map { scalar -> String in
                let code = Int(scalar.value)
                if error.isBlankUnicode(code) { return String(scalar) }
                let glyph = error.getGlyfIdByUnicode(code) == 0 ? nil : error.getGlyfByUnicode(code)
                if filter && glyph == nil { return "" }
                let replacement = correct.getUnicodeByGlyf(glyph)
                return replacement != 0 ? Unicode.Scalar(replacement).map(String.init) ?? String(scalar) : String(scalar)
            }.joined()
        }
        if method.hasPrefix("font.") {
            guard let id = value(0) as? Int, handles.indices.contains(id) else { throw JsEngineError.exception("queryTTF invalid font handle") }
            let font = handles[id], code = (value(1) as? NSNumber)?.intValue ?? 0
            switch String(method.dropFirst(5)) {
            case "getGlyfById": return font.getGlyfById(code)
            case "getGlyfIdByUnicode": return font.getGlyfIdByUnicode(code)
            case "getGlyfByUnicode": return font.getGlyfByUnicode(code)
            case "getUnicodeByGlyf": return font.getUnicodeByGlyf(value(1) as? String)
            case "isBlankUnicode": return font.isBlankUnicode(code)
            default: throw JsEngineError.exception("unknown font method " + method)
            }
        }
        if method == "queryBase64TTF" { network.engine.logger("queryBase64TTF is deprecated; use queryTTF") }
        guard let input = value(0), !(input is NSNull) else { return nil }
        let raw: Data
        if let string = input as? String { raw = Data(string.utf8) }
        else if input is [Any] || input is Data { raw = try JavaHostEncoding.bytes(input) }
        else { return nil }
        let key = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined() as NSString
        let useCache = value(1) as? Bool ?? true
        let font: QueryTTF
        if useCache, let cached = Self.cache.object(forKey: key) { font = cached.font }
        else {
            let data: Data
            if let string = input as? String {
                if string.hasPrefix("https://") || string.hasPrefix("http://") {
                    let executor = try AnalyzeUrlExecutor(string, engine: network.engine, bindings: bindings)
                    data = try HostAsyncBridge.wait { try await executor.getByteArray() }
                } else {
                    if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                    data = try JavaHostEncoding.base64(string, flags: 0)
                }
            } else { data = raw }
            font = try QueryTTF(data)
            if useCache { Self.cache.setObject(Entry(font), forKey: key) }
        }
        let id: Int
        if let existing = handles.firstIndex(where: { $0 === font }) { id = existing }
        else { id = handles.count; handles.append(font) }
        return ["__legadoFont": id,
            "unicodeToGlyph": Dictionary(uniqueKeysWithValues: font.unicodeToGlyph.map { (String($0.key), $0.value) }),
            "unicodeToGlyphId": Dictionary(uniqueKeysWithValues: font.unicodeToGlyphId.map { (String($0.key), $0.value) }),
            "glyphToUnicode": font.glyphToUnicode]
    }
}
