import Foundation

/// 黄金用例 README 的数据模型；不执行规则或推断期望值。
public struct ConformanceCase: Codable, Equatable {
    public let id: String
    public let source: Source
    public let kind: String
    public let input: Input
    public let expect: Expectation
    public let notes: String
    public let requiresAndroid: Bool
    /// 扩展元数据尚未规定结构，按 JSON 原类型保留。
    public let derivedFrom: JSONValue?
    public let verification: JSONValue?

    public struct Source: Codable, Equatable {
        public let file: String
        public let method: String
        public let line: Int
        public let commit: String
    }

    public struct Input: Codable, Equatable {
        public let document: String?
        public let documentType: String
        public let rule: String
        public let baseUrl: String?
        public let variables: [String: JSONValue]?

        private enum CodingKeys: String, CodingKey {
            case document, documentType, rule, baseUrl, variables
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            document = try container.decode(String?.self, forKey: .document)
            documentType = try container.decode(String.self, forKey: .documentType)
            rule = try container.decode(String.self, forKey: .rule)
            baseUrl = try container.decodeIfPresent(String.self, forKey: .baseUrl)
            variables = try container.decodeIfPresent([String: JSONValue].self, forKey: .variables)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(document, forKey: .document)
            try container.encode(documentType, forKey: .documentType)
            try container.encode(rule, forKey: .rule)
            try container.encodeIfPresent(baseUrl, forKey: .baseUrl)
            try container.encodeIfPresent(variables, forKey: .variables)
        }
    }

    public enum Expectation: Codable, Equatable {
        case string(String)
        case stringList([String])
        case error(String)

        private enum CodingKeys: String, CodingKey { case type, value }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "string": self = .string(try container.decode(String.self, forKey: .value))
            case "stringList": self = .stringList(try container.decode([String].self, forKey: .value))
            case "error": self = .error(try container.decode(String.self, forKey: .value))
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "未知期望类型：\(type)")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .string(let value):
                try container.encode("string", forKey: .type)
                try container.encode(value, forKey: .value)
            case .stringList(let value):
                try container.encode("stringList", forKey: .type)
                try container.encode(value, forKey: .value)
            case .error(let value):
                try container.encode("error", forKey: .type)
                try container.encode(value, forKey: .value)
            }
        }
    }

    public enum JSONValue: Codable, Equatable {
        case null
        case bool(Bool)
        case number(Decimal)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Decimal.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
            else { self = .object(try container.decode([String: JSONValue].self)) }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }
    }
}
