import Foundation

public enum SourceCallback {
    public static func imageClick(script: String, src: String, source: BookSource, book: Book,
                                  chapter: BookChapter?, client: any HttpClient) throws -> String {
        let session = (client as? any SourceSessionClientProviding)?.client(for: source) ?? client
        let context = try WebBookContext(source: source, client: session, book: book)
        let baseURL = chapter?.url ?? book.bookUrl ?? source.bookSourceUrl ?? ""
        let engine = try context.engine(baseURL: baseURL)
        let parser = try context.parser("", baseURL: baseURL, chapter: chapter, engine: engine)
        return ruleText(try engine.evaluateScript(script, bindings: ["src": src, "result": src], context: parser))
    }

    public static func run(source: BookSource, book: Book, chapter: BookChapter? = nil,
                           event: String, result: String? = nil, client: any HttpClient) throws -> Bool {
        guard source.eventListener == true, let script = source.ruleContent?.callBackJs, !script.isEmpty else { return false }
        let session = (client as? any SourceSessionClientProviding)?.client(for: source) ?? client
        let context = try WebBookContext(source: source, client: session, book: book)
        let engine = try context.engine(baseURL: book.bookUrl ?? source.bookSourceUrl ?? "")
        let parser = try context.parser("", baseURL: book.bookUrl ?? "", chapter: chapter, engine: engine)
        let value = try engine.evaluateScript(script, bindings: ["event": event, "result": result as Any? ?? NSNull()], context: parser)
        return ruleText(value).lowercased() == "true"
    }
}
