import Foundation

public final class MobiParserCache {
    public static let shared = MobiParserCache()
    private struct Item { let signature: String; let parser: MobiFile }
    private let lock = NSLock()
    private let capacity: Int
    private let maximumBytes: Int
    private var items: [String: Item] = [:]
    private var order: [String] = []

    public init(capacity: Int = 3, maximumBytes: Int = 64 * 1024 * 1024) {
        self.capacity = max(0, capacity); self.maximumBytes = max(0, maximumBytes)
    }

    public func invalidate(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        let key = url.standardizedFileURL.path
        items[key] = nil; order.removeAll { $0 == key }
    }

    public func parser(for url: URL) throws -> MobiFile {
        lock.lock(); defer { lock.unlock() }
        let key = url.standardizedFileURL.path
        let attributes = try FileManager.default.attributesOfItem(atPath: key)
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate
        let signature = [String(describing: attributes[.systemFileNumber]), String(describing: attributes[.size]), String(describing: modified)].joined(separator: ":")
        if let item = items[key], item.signature == signature {
            order.removeAll { $0 == key }; order.append(key)
            return item.parser
        }
        items[key] = nil; order.removeAll { $0 == key }
        let parser = try MobiFile(url: url)
        guard capacity > 0 else { return parser }
        while !order.isEmpty && (items.count >= capacity || items.values.reduce(0, { $0 + $1.parser.cacheCost }) + parser.cacheCost > maximumBytes) {
            items[order.removeFirst()] = nil
        }
        items[key] = Item(signature: signature, parser: parser); order.append(key)
        return parser
    }
}
