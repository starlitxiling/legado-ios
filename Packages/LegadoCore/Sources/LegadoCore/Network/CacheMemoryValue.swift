import Foundation
import CoreFoundation

public indirect enum CacheMemoryValue: Sendable {
    case null, string(String), number(Double), boolean(Bool), bytes(Data)
    case array([CacheMemoryValue]), object([String: CacheMemoryValue])

    public init(_ value: Any) throws {
        switch value {
        case is NSNull: self = .null
        case let bytes as Data: self = .bytes(bytes)
        case let text as String: self = .string(text)
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .boolean(number.boolValue) : .number(number.doubleValue)
        case let array as [Any]: self = .array(try array.map(Self.init))
        case let object as [String: Any]: self = .object(try object.mapValues(Self.init))
        default: throw JsEngineError.exception("Unsupported memory cache value: " + String(describing: type(of: value)))
        }
    }

    public var value: Any {
        switch self {
        case .null: return NSNull()
        case .string(let text): return text
        case .number(let number): return number
        case .boolean(let value): return value
        case .bytes(let data): return data
        case .array(let items): return items.map(\.value)
        case .object(let items): return items.mapValues(\.value)
        }
    }

    var size: Int {
        switch self {
        case .null: return 8
        case .string(let text): return text.utf16.count * 2
        case .number, .boolean: return 16
        case .bytes(let data): return data.count
        case .array(let values): return values.reduce(16) { $0 + $1.size }
        case .object(let values): return values.reduce(16) { $0 + $1.key.utf16.count * 2 + $1.value.size }
        }
    }
}
