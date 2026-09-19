import Foundation

// Preserve NativeObject rule semantics without retaining its JavaScript context.
final class JsObject: NSDictionary {
    let values: [String: Any]

    init(_ values: [String: Any]) {
        self.values = values
        super.init()
    }

    static func snapshot(_ value: Any?) -> Any? {
        if let object = value as? [String: Any] {
            return JsObject(object.mapValues { snapshot($0) ?? NSNull() })
        }
        if let list = value as? [Any] { return list.map { snapshot($0) ?? NSNull() } }
        return value
    }

    override var count: Int { values.count }
    override func keyEnumerator() -> NSEnumerator { (Array(values.keys) as NSArray).objectEnumerator() }
    override func object(forKey key: Any) -> Any? { (key as? String).flatMap { values[$0] } }
    required init?(coder: NSCoder) { return nil }
    override convenience init() { self.init([:]) }
    override convenience init(objects: UnsafePointer<AnyObject>?, forKeys keys: UnsafePointer<NSCopying>?, count: Int) {
        var values: [String: Any] = [:]
        if let objects, let keys {
            for index in 0..<count {
                if let key = keys[index] as? String { values[key] = objects[index] }
            }
        }
        self.init(values)
    }
}
