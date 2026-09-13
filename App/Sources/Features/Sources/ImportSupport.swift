import Foundation
import LegadoCore

struct ManagementImportPreview {
    let newCount: Int
    let overwriteCount: Int
    let unsupportedCount: Int
    var importableCount: Int { newCount + overwriteCount }
}

enum ManagementImportError: LocalizedError {
    case invalidURL, invalidText, unsupportedScript, urlCollection, httpStatus(Int), tooLarge
    case invalidSourceText(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入有效的 HTTP 或 HTTPS 地址。"
        case .invalidText: return "未找到有效的 JSON 数据，请检查文件或文本。"
        case .invalidSourceText(let preview): return "JSON 无效。内容预览：\(preview)"
        case .unsupportedScript: return "不支持脚本书源，请导入 JSON 书源。"
        case .urlCollection: return "这是书源地址集合，请单独导入其中的 JSON 下载地址。"
        case .httpStatus(let status): return "下载失败，HTTP 状态码：\(status)。"
        case .tooLarge: return "导入内容超过 16 MB 限制。"
        }
    }
}

enum ManagementImport {
    static let maximumBytes = 16 * 1024 * 1024

    static func isJavaScript(_ text: String) -> Bool {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = #"\A(?://[^\n]*(?:\n|$)|/\*[\s\S]*?\*/)\s*"#
        while let range = candidate.range(of: comment, options: .regularExpression) {
            candidate.removeSubrange(range)
        }
        guard let first = candidate.first, !"{[<".contains(first) else { return false }
        let declaration = #"\A(?:(?:async\s+)?function(?:\s+[A-Za-z_$][\w$]*)?\s*\([^)]*\)\s*\{|(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:\{|\[|function\b|[^;\r\n]+;|[^\r\n]*=>)|(?:mainJs|module\.exports|exports\.[A-Za-z_$][\w$]*)\s*=\s*(?:function\b|[^\r\n]*=>))"#
        return candidate.range(of: declaration, options: .regularExpression) != nil
    }

    static func groups(_ text: String?) -> [String] {
        (text ?? "").components(separatedBy: CharacterSet(charactersIn: ",;，；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func text(_ data: Data) throws -> String {
        guard data.count <= maximumBytes else { throw ManagementImportError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ManagementImportError.invalidText }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    static func download(_ address: String, client: any ResponseLimitedHttpClient) async throws -> String {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { throw ManagementImportError.invalidURL }
        let response = try await client.send(HttpRequest(url: url), maximumResponseBytes: maximumBytes)
        guard (200..<300).contains(response.status) else { throw ManagementImportError.httpStatus(response.status) }
        return try text(response.body)
    }

    // 规则对象在数据库中存为 JSON 文本，替换规则 order 对应 sortOrder 列。
    static func row<Value: Encodable, Row: StorageRow>(_ value: Value, defaults: Row) throws -> Row {
        let encoder = JSONEncoder()
        var fields = try JSONSerialization.jsonObject(with: encoder.encode(defaults)) as! [String: Any]
        let incoming = try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
        for (key, value) in incoming {
            let column = Row.self == ReplaceRuleRow.self && key == "order" ? "sortOrder" : key
            if value is [String: Any] || value is [Any] {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                fields[column] = String(decoding: data, as: UTF8.self)
            } else if !(value is NSNull) || fields[column] == nil || fields[column] is NSNull {
                fields[column] = value
            }
        }
        return try JSONDecoder().decode(Row.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}
