import Foundation

public final class CustomUrl: CustomStringConvertible {
    public enum AttributeError: Error, Equatable { case invalidValue(String) }
    private let url: String
    private var attributeData = Data("{}".utf8)

    public init(_ value: String) {
        if let separator = value.range(of: #"\s*,\s*(?=\{)"#, options: .regularExpression) {
            url = String(value[..<separator.lowerBound])
            let json = String(value[separator.upperBound...])
            if let tree = try? GsonValue.parse(Data(json.utf8)), case .object = tree {
                attributeData = Data(tree.json.utf8)
            }
        } else { url = value }
    }

    @discardableResult
    public func putAttribute(_ key: String, _ value: Any?) throws -> CustomUrl {
        var attributes = try getAttr()
        if value == nil || value is NSNull { attributes.removeValue(forKey: key) }
        else { attributes[key] = value }
        guard JSONSerialization.isValidJSONObject(attributes) else { throw AttributeError.invalidValue(key) }
        attributeData = try JSONSerialization.data(withJSONObject: attributes, options: [.sortedKeys, .withoutEscapingSlashes])
        return self
    }

    public func getUrl() -> String { url }

    public func getAttr() throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: attributeData) as? [String: Any] else {
            throw AttributeError.invalidValue("attributes")
        }
        return object
    }

    public var description: String {
        let json = String(decoding: attributeData, as: UTF8.self)
        return json == "{}" ? url : url + "," + json
    }
}
