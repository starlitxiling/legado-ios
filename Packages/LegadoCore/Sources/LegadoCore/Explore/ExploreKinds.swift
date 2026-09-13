import Foundation
import CryptoKit

public struct ExploreKind: Decodable, Equatable, Sendable {
    public let title: String
    public let url: String?
    public let type: String
    public let action: String?
    public var isHeading: Bool { type == "text" || (url ?? "").isEmpty }

    public init(title: String, url: String? = nil, type: String = "url", action: String? = nil) {
        self.title = title; self.url = url; self.type = type; self.action = action
    }

    private enum CodingKeys: String, CodingKey { case title, url, type, action }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url)
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "url"
        action = try values.decodeIfPresent(String.self, forKey: .action)
    }
}

public enum ExploreKinds {
    public static func parse(_ text: String) throws -> [ExploreKind] {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        if value.hasPrefix("[") { return try JSONDecoder().decode([ExploreKind].self, from: Data(value.utf8)) }
        return value.replacingOccurrences(of: "&&", with: "\n").components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let parts = line.components(separatedBy: "::")
                return ExploreKind(title: parts[0], url: parts.count > 1 ? parts[1] : nil)
            }
    }

    public static func load(source: BookSource, client: any HttpClient,
                            cookies: CookieStore = CookieStore()) throws -> [ExploreKind] {
        var state: [String: String] = [:]
        return try parse(evaluate(source: source, client: client, cookies: cookies, state: &state,
                                  now: Date().timeIntervalSince1970))
    }

    public static func load(source: BookSource, client: any HttpClient, stateRepository: SourceStateRepository,
                            cookies: CookieStore = CookieStore(), now: TimeInterval = Date().timeIntervalSince1970) async throws -> [ExploreKind] {
        let key = source.bookSourceUrl ?? ""
        let original = try await stateRepository.load(source: key)
        if let cached = original[cacheKey(source)] { return try parse(cached) }
        var state = original
        do {
            let text = try evaluate(source: source, client: client, cookies: cookies, state: &state, now: now)
            let kinds = try parse(text)
            state[cacheKey(source)] = text
            try await stateRepository.merge(source: key, original: original, updated: state)
            return kinds
        } catch {
            try await stateRepository.merge(source: key, original: original, updated: state)
            throw error
        }
    }

    public static func clearCache(source: BookSource, stateRepository: SourceStateRepository) async throws {
        let original = try await stateRepository.load(source: source.bookSourceUrl ?? "")
        var updated = original; updated.removeValue(forKey: cacheKey(source))
        try await stateRepository.merge(source: source.bookSourceUrl ?? "", original: original, updated: updated)
    }

    private static func cacheKey(_ source: BookSource) -> String {
        let hash = Insecure.MD5.hash(data: Data(((source.bookSourceUrl ?? "") + (source.exploreUrl ?? "")).utf8))
        return "explore.kinds." + hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func evaluate(source: BookSource, client: any HttpClient, cookies: CookieStore,
                                 state: inout [String: String], now: TimeInterval) throws -> String {
        var text = (source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let script: String?
        if lower.hasPrefix("@js:") { script = String(text.dropFirst(4)) }
        else if lower.hasPrefix("<js>"), lower.hasSuffix("</js>") { script = String(text.dropFirst(4).dropLast(5)) }
        else { script = nil }
        if let script {
            let context = WebBookContext(source: source, client: client, cookies: cookies)
            let engine = try context.engine(baseURL: source.bookSourceUrl ?? "")
            let library = engine.libraryInitializer
            let stateJSON = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
            var finalState = state
            defer { state = finalState }
            let save: @convention(block) (String) -> Void = { json in
                if let values = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)) { finalState = values }
            }
            engine.libraryInitializer = { context in
                context.setObject(save, forKeyedSubscript: "__saveExploreState" as NSString)
                context.evaluateScript("var __exploreState = \(stateJSON); var __exploreNow = \(now);" + bridge)
                try library?(context)
            }
            let result = try engine.evaluateScript("try { eval(__exploreCode); } finally { if(infoMap.needSave) infoMap.saveNow(); __saveExploreState(JSON.stringify(__exploreState)); }",
                bindings: ["source": try WebBookContext.object(source), "__exploreCode": script])
            if let array = result as? [Any] {
                text = String(decoding: try JSONSerialization.data(withJSONObject: array), as: UTF8.self)
            } else { text = ruleText(result) }
        }
        try Task.checkCancellation()
        return text
    }

    private static let bridge = """
    source.getVariable = function(){return __exploreState.variable || '';};
    source.setVariable = function(v){if(v == null) delete __exploreState.variable; else __exploreState.variable = String(v);};
    source.putVariable = source.setVariable;
    source.get = function(k){return __exploreState['v_' + k] || '';};
    source.put = function(k,v){__exploreState['v_' + k] = String(v); return String(v);};
    var __infoValues = JSON.parse(__exploreState['explore.infoMap'] || '{}');
    if (Number(__exploreState['explore.infoMapExpires'] || 0) > 0 && Number(__exploreState['explore.infoMapExpires']) <= __exploreNow) __infoValues = {};
    var __infoTime = 0;
    var infoMap = {
      needSave:false,
      get:function(k){return arguments.length === 0 ? __infoValues : (Object.prototype.hasOwnProperty.call(__infoValues,k) ? __infoValues[k] : null);},
      put:function(k,v){var old=this.get(k); __infoValues[k]=String(v); return old;},
      remove:function(k){var old=this.get(k); delete __infoValues[k]; return old;},
      set:function(v){__infoValues=Object.assign({},v);},
      putAll:function(v){Object.assign(__infoValues,v);},
      containsKey:function(k){return Object.prototype.hasOwnProperty.call(__infoValues,k);},
      containsValue:function(v){return Object.keys(__infoValues).some(function(k){return __infoValues[k] === v;});},
      isEmpty:function(){return Object.keys(__infoValues).length === 0;},
      clear:function(){__infoValues={};},
      save:function(time,need){__infoTime=Number(time || 0); this.needSave=need === undefined ? true : Boolean(need);},
      saveNow:function(){__exploreState['explore.infoMap']=JSON.stringify(__infoValues); __exploreState['explore.infoMapExpires']=String(__infoTime > 0 ? __exploreNow + __infoTime : 0); this.needSave=false;}
    };
    Object.defineProperty(infoMap,'size',{get:function(){return Object.keys(__infoValues).length;}});
    """
}
