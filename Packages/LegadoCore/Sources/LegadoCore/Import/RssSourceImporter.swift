import Foundation

public enum RssSourceImportResult: Equatable {
    case sources([RssSource]), urls([String]), invalid
}

public extension SourceImporter {
    func parseRssSources(_ text: String) -> RssSourceImportResult {
        guard let data = text.data(using: .utf8) else { return .invalid }
        do {
            let tree = try GsonValue.parse(data)
            let decoder = GsonJSONDecoder()
            func urls(_ values: [GsonValue]) -> RssSourceImportResult {
                let urls = values.compactMap(\.stringValue)
                return urls.count == values.count && urls.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ? .urls(urls) : .invalid
            }
            let sources: [RssSource]
            switch tree {
            case let .array(values):
                if !values.isEmpty, values.allSatisfy({ if case .string = $0 { return true }; return false }) { return urls(values) }
                sources = try decoder.decode([RssSource].self, from: data)
            case .object:
                if case let .array(values)? = tree["sourceUrls"] { return urls(values) }
                sources = [try decoder.decode(RssSource.self, from: data)]
            default: return .invalid
            }
            return sources.allSatisfy({ !$0.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ? .sources(sources) : .invalid
        } catch { return .invalid }
    }
}
