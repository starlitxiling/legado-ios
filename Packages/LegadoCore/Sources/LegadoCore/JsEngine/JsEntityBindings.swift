import Foundation

protocol JsEntityBinding: RuleVariableStorage {
    func scriptObject() throws -> [String: Any]
}

public final class JsBookBinding: RuleVariableStorage, JsEntityBinding {
    public var book: Book
    public let store: RuleVariableStore
    public var name: String {
        get { book.name ?? "" }
        set { book.name = newValue }
    }

    public init(_ book: Book) throws {
        self.book = book
        store = try RuleVariableStore(json: book.variable)
    }

    public func value(for key: String) -> String? { store.value(for: key) }
    public func setValue(_ value: String?, for key: String) { store.setValue(value, for: key) }
    public func snapshot() throws -> Book {
        var result = book
        result.variable = try store.json(or: book.variable)
        return result
    }
    func scriptObject() throws -> [String: Any] { try entityObject(snapshot()) }
}

public final class JsChapterBinding: RuleVariableStorage, JsEntityBinding {
    public var chapter: BookChapter
    public let store: RuleVariableStore
    public var name: String { chapter.title ?? "" }

    public init(_ chapter: BookChapter) throws {
        self.chapter = chapter
        store = try RuleVariableStore(json: chapter.variable)
    }

    public func value(for key: String) -> String? { store.value(for: key) }
    public func setValue(_ value: String?, for key: String) { store.setValue(value, for: key) }
    public func snapshot() throws -> BookChapter {
        var result = chapter
        result.variable = try store.json(or: chapter.variable)
        return result
    }
    func scriptObject() throws -> [String: Any] { try entityObject(snapshot()) }
}

public final class JsSourceBinding: RuleVariableStorage, JsEntityBinding {
    public let source: BookSource
    var readVariable: ((String) throws -> String?)?
    var writeVariable: ((String, String?) throws -> Void)?
    public let api: JsSourceApi
    public var name: String { source.bookSourceName ?? "" }

    public init(_ source: BookSource, api: JsSourceApi = JsSourceApi()) {
        self.source = source
        self.api = api
    }

    public func value(for key: String) throws -> String? {
        if let readVariable { return try readVariable(key) }
        return api.value(for: "v_" + key)
    }
    public func setValue(_ value: String?, for key: String) throws {
        if let writeVariable { try writeVariable(key, value) }
        else { api.setValue(value, for: "v_" + key) }
    }
    func scriptObject() throws -> [String: Any] { try entityObject(source) }
}

extension RuleVariableStore {
    convenience init(json: String?) throws {
        guard let json, !json.isEmpty else { self.init(); return }
        do { self.init(try JSONDecoder().decode([String: String].self, from: Data(json.utf8))) }
        catch { throw JsEngineError.exception("Invalid entity variable JSON: \(error)") }
    }

    func json(or original: String? = nil) throws -> String? {
        guard !variables.isEmpty || original?.isEmpty == false else { return original }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(variables), as: UTF8.self)
    }

    func replace(with values: [String: String]) {
        for key in Array(variables.keys) { setValue(nil, for: key) }
        for (key, value) in values { setValue(value, for: key) }
    }
}

private func entityObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] else {
        throw JsEngineError.exception("Script entity must encode as an object")
    }
    return object
}
