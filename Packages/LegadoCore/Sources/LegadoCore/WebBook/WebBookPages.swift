import Foundation

extension WebBookContext {
    func mapPages<Value>(_ urls: [String], chapter: BookChapter? = nil,
                         operation: @escaping (WebBookContext, String) async throws -> Value) async throws -> [Value] {
        let initialBook = try bookStore.snapshot()
        let initialChapter = try chapter.map { try chapterBinding($0).snapshot() }
        let bookVariables = bookStore.store.variables
        let chapterVariables = try chapter.map { try chapterBinding($0).store.variables } ?? [:]
        let contexts = try urls.map { _ in
            let context = try WebBookContext(source: source, client: client, book: book == nil ? nil : initialBook,
                cookies: cookies, sourceAPI: sourceStore.api, configuration: configuration)
            context.bookStore.store.replace(with: bookVariables)
            if let initialChapter { _ = try context.chapterBinding(initialChapter) }
            return context
        }
        let values = try await withThrowingTaskGroup(of: (Int, Value).self) { group in
            var next = 0
            func enqueue() {
                guard next < urls.count else { return }
                let index = next
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    return (index, try await operation(contexts[index], urls[index]))
                }
            }
            for _ in 0..<min(urls.count, max(1, min(128, configuration.threadCount))) { enqueue() }
            var results: [(Int, Value)] = []
            for try await value in group {
                results.append(value)
                enqueue()
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        try Task.checkCancellation()
        func merge(_ store: RuleVariableStore, original: [String: String], changed: [String: String]) {
            for key in Set(original.keys).union(changed.keys) where original[key] != changed[key] {
                store.setValue(changed[key], for: key)
            }
        }
        for context in contexts {
            merge(bookStore.store, original: bookVariables, changed: context.bookStore.store.variables)
            if let chapter {
                merge(try chapterBinding(chapter).store, original: chapterVariables,
                    changed: try context.chapterBinding(chapter).store.variables)
            }
        }
        return values
    }
}
