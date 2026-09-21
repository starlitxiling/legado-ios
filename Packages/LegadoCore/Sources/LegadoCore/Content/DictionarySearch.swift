import Foundation

extension DictRule {
    public func search(word: String, client: any HttpClient) async throws -> String {
        try Task.checkCancellation()
        let engine = JsEngine(httpClient: client)
        let request = try AnalyzeUrlExecutor(urlRule, engine: engine, bindings: ["key": word])
        let response = try await request.getStrResponseAwait()
        try Task.checkCancellation()
        guard !showRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return response.body }
        let parser = AnalyzeRule(content: response.body, engines: [.default: AnalyzeByJSoup(),
            .xpath: AnalyzeByXPath(), .json: AnalyzeByJSonPath(), .js: engine])
        return try parser.getString(showRule)
    }
}
