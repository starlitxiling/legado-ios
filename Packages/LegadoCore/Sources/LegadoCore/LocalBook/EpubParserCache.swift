import Foundation

public final class EpubParserCache {
    public static let shared = EpubParserCache()
    private struct Item {
        let signature: String
        let parser: EpubParser
    }
    private let capacity: Int
    private let maximumBytes: Int
    private let lock = NSLock()
    private var items: [String: Item] = [:]
    private var order: [String] = []

    public init(capacity: Int = 3, maximumBytes: Int = 32 * 1024 * 1024) {
        self.capacity = max(0, capacity); self.maximumBytes = max(0, maximumBytes)
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
    public var cachedBytes: Int { lock.lock(); defer { lock.unlock() }; return cost }
    private var cost: Int { items.values.reduce(0) { $0 + $1.parser.cacheCost } }

    public func invalidate(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        let key = url.standardizedFileURL.path
        items[key] = nil; order.removeAll { $0 == key }
    }

    public func parser(for url: URL) throws -> EpubParser {
        lock.lock(); defer { lock.unlock() }
        let key = url.standardizedFileURL.path
        let attributes = try FileManager.default.attributesOfItem(atPath: key)
        let signature = [FileAttributeKey.systemFileNumber, .size, .modificationDate]
            .map { String(describing: attributes[$0]) }.joined(separator: ":")
        if let item = items[key], item.signature == signature {
            order.removeAll { $0 == key }; order.append(key)
            return item.parser
        }
        items[key] = nil; order.removeAll { $0 == key }
        let parser = try EpubParser(url: url)
        guard capacity > 0, parser.cacheCost <= maximumBytes else { return parser }
        while !order.isEmpty && (items.count >= capacity || cost + parser.cacheCost > maximumBytes) {
            items[order.removeFirst()] = nil
        }
        items[key] = Item(signature: signature, parser: parser); order.append(key)
        return parser
    }
}
