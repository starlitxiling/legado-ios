import Foundation
import CryptoKit
import LegadoCore

struct CachedReaderChapter: Codable {
    let rawContent: String
}

actor ReaderChapterCache {
    private struct Download {
        let id: UUID
        let task: Task<Void, Never>
        var consumers: [UUID: CheckedContinuation<CachedReaderChapter, Error>]
    }

    private let directory: URL
    private var pending: [String: Download] = [:]

    init(directory: URL) { self.directory = directory }

    var pendingConsumerCount: Int { pending.values.reduce(0) { $0 + $1.consumers.count } }

    private func fileURL(book: Book, chapter: BookChapter) throws -> URL {
        try ReaderCacheStatus.fileURL(book: book, chapter: chapter, directory: directory)
    }

    func hasContent(book: Book, chapter: BookChapter) -> Bool {
        ReaderCacheStatus.hasContent(book: book, chapter: chapter, directory: directory)
            || BookHelp.hasContent(directory: directory, book: book, chapter: chapter)
    }

    func cancelPending() {
        let downloads = pending.values
        pending.removeAll()
        for download in downloads {
            download.task.cancel()
            for consumer in download.consumers.values { consumer.resume(throwing: CancellationError()) }
        }
    }

    func content(book: Book, chapter: BookChapter, nextURL: String?, source: BookSource?,
                 client: any HttpClient) async throws -> CachedReaderChapter {
        try Task.checkCancellation()
        let url = try fileURL(book: book, chapter: chapter)
        let key = url.deletingPathExtension().lastPathComponent
        if let data = try? Data(contentsOf: url), let cached = try? JSONDecoder().decode(CachedReaderChapter.self, from: data) {
            return cached
        }
        if let content = try BookHelp.content(directory: directory, book: book, chapter: chapter) {
            return CachedReaderChapter(rawContent: content)
        }
        let source = source ?? (LocalBook.isLocal(book) ? BookSource() : nil)
        guard let source else { throw ReaderError.missingSource }
        let consumerID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if pending[key] != nil {
                    pending[key]?.consumers[consumerID] = continuation
                    return
                }
                let downloadID = UUID()
                let task = Task {
                    let result: Result<CachedReaderChapter, Error>
                    do {
                        let response = try await BookContent.load(source: source, book: book, chapter: chapter,
                            client: client, nextChapterURL: nextURL, includeTitle: false)
                        try Task.checkCancellation()
                        result = .success(CachedReaderChapter(rawContent: response.rawContent))
                    } catch { result = .failure(error) }
                    finish(key: key, id: downloadID, url: url, result: result)
                }
                pending[key] = Download(id: downloadID, task: task, consumers: [consumerID: continuation])
            }
        } onCancel: {
            Task { await self.release(key: key, consumerID: consumerID) }
        }
    }

    private func release(key: String, consumerID: UUID) {
        guard var download = pending[key], let consumer = download.consumers.removeValue(forKey: consumerID) else { return }
        if download.consumers.isEmpty {
            pending[key] = nil
            download.task.cancel()
        } else { pending[key] = download }
        consumer.resume(throwing: CancellationError())
    }

    private func finish(key: String, id: UUID, url: URL, result: Result<CachedReaderChapter, Error>) {
        guard let download = pending[key], download.id == id else { return }
        pending[key] = nil
        let result = result.flatMap { cached in
            Result {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(cached).write(to: url, options: .atomic)
                return cached
            }
        }
        for consumer in download.consumers.values { consumer.resume(with: result) }
    }
}
enum ReaderError: LocalizedError {
    case missingBook, missingSource, emptyChapters
    var errorDescription: String? {
        switch self {
        case .missingBook: return "书架中找不到这本书。"
        case .missingSource: return "正文尚未缓存，且找不到对应书源。"
        case .emptyChapters: return "目录为空，请先更新目录。"
        }
    }
}

enum ReaderEntityBridge {
    static func decode<T: Decodable>(_ type: T.Type, row: some Encodable) throws -> T {
        let data = try JSONEncoder().encode(row)
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        for key in ["readConfig", "ruleExplore", "ruleSearch", "ruleBookInfo", "ruleToc", "ruleContent", "ruleReview"] {
            if let text = object[key] as? String {
                object[key] = try JSONSerialization.jsonObject(with: Data(text.utf8))
            }
        }
        if let order = object.removeValue(forKey: "sortOrder") { object["order"] = order }
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
}
