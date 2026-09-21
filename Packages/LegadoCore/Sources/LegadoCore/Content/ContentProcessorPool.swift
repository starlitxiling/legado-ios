import Foundation

public final class ContentProcessorPool {
    public struct Configuration: Hashable, Sendable {
        public var manualReplace: Bool
        public var paragraphIndent: String
        public var chineseConverterType: Int
        public var replaceEnableDefault: Bool
        public var adaptSpecialStyle: Bool
        public var cacheDirectory: URL?

        public init(paragraphIndent: String = "　　", chineseConverterType: Int = 0,
                    replaceEnableDefault: Bool = true, adaptSpecialStyle: Bool = true, cacheDirectory: URL? = nil, manualReplace: Bool = false) {
            self.manualReplace = manualReplace
            self.paragraphIndent = paragraphIndent
            self.chineseConverterType = chineseConverterType
            self.replaceEnableDefault = replaceEnableDefault
            self.adaptSpecialStyle = adaptSpecialStyle
            self.cacheDirectory = cacheDirectory
        }
    }

    private struct Key: Hashable {
        let name: String
        let origin: String
        let configuration: Configuration
    }
    private let lock = NSLock()
    private let capacity: Int
    private var processors: [Key: ContentProcessor] = [:]
    private var order: [Key] = []

    public init(capacity: Int = 32) { self.capacity = max(1, capacity) }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return processors.count
    }

    public func get(book: Book, rules: [ReplaceRule], configuration: Configuration = .init()) -> ContentProcessor {
        let key = Key(name: book.name ?? "", origin: book.origin ?? "", configuration: configuration)
        lock.lock()
        let processor: ContentProcessor
        if let existing = processors[key] { processor = existing }
        else {
            processor = ContentProcessor(rules: rules, paragraphIndent: configuration.paragraphIndent,
                chineseConverterType: configuration.chineseConverterType, replaceEnableDefault: configuration.replaceEnableDefault,
                adaptSpecialStyle: configuration.adaptSpecialStyle, cacheDirectory: configuration.cacheDirectory, manualReplace: configuration.manualReplace)
            processors[key] = processor
        }
        order.removeAll { $0 == key }; order.append(key)
        if order.count > capacity { processors.removeValue(forKey: order.removeFirst()) }
        lock.unlock()
        processor.upReplaceRules(rules)
        return processor
    }

    public func upReplaceRules(_ rules: [ReplaceRule]) {
        lock.lock()
        let current = Array(processors.values)
        lock.unlock()
        for processor in current { processor.upReplaceRules(rules) }
    }
}
