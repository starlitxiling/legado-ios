import Foundation
import CryptoKit

public enum ImageDownloadError: Error { case invalidDecodeResult, emptyImage }

public actor ImageDownloader {
    private let client: any HttpClient
    private let directory: URL
    private let cookies: CookieStore

    public init(client: any HttpClient, cacheDirectory: URL? = nil, cookies: CookieStore = CookieStore()) {
        self.client = client; self.cookies = cookies
        directory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("legado/images", isDirectory: true)
    }

    public func load(url: String, source: BookSource? = nil, book: Book? = nil,
                     isCover: Bool = true, cacheFile: URL? = nil) async throws -> Data {
        try await load(url: url, source: source, book: book, isCover: isCover, cacheFile: cacheFile, validate: { _ in true })
    }

    public func load(url: String, source: BookSource? = nil, book: Book? = nil,
                     isCover: Bool = true, cacheFile: URL? = nil,
                     validate: @Sendable (Data) -> Bool) async throws -> Data {
        try Task.checkCancellation()
        let source = source ?? BookSource()
        let scope: String
        if isCover {
            scope = "covers/" + Self.md5(source.bookSourceUrl ?? "") + Self.md5(source.coverDecodeJs ?? "")
        } else if let book {
            scope = Self.bookScope(book)
        } else { scope = "content/" + Self.md5(source.bookSourceUrl ?? "") }
        let path = cacheFile ?? directory.appendingPathComponent(scope, isDirectory: true)
            .appendingPathComponent(Self.md5(url) + "." + Self.suffix(url))
        if let data = try? Data(contentsOf: path), !data.isEmpty {
            if validate(data) { return data }
            try FileManager.default.removeItem(at: path)
        }
        let context = WebBookContext(source: source, client: client, book: book, cookies: cookies)
        let engine = try context.engine(baseURL: source.bookSourceUrl ?? "")
        var bindings: [String: Any] = ["source": try WebBookContext.object(source), "src": url]
        if let book { bindings["book"] = try WebBookContext.object(book) }
        let executor = try AnalyzeUrlExecutor(url, engine: engine, bindings: bindings)
        var data: Data
        if executor.url.hasPrefix("data:") { data = try await executor.getByteArray() }
        else {
            let response = try await executor.getResponse()
            guard (200..<300).contains(response.status) else {
                throw WebBookError.httpStatus(response.status, response.finalURL.absoluteString)
            }
            data = response.body
        }
        let rule = isCover ? source.coverDecodeJs : source.ruleContent?.imageDecode
        if let rule, !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bindings["result"] = data.map { Int(Int8(bitPattern: $0)) }
            guard let values = try engine.evaluateScript(rule, bindings: bindings) as? [NSNumber] else {
                throw ImageDownloadError.invalidDecodeResult
            }
            var bytes: [UInt8] = []
            for value in values {
                let number = value.doubleValue
                guard number.isFinite, number.rounded() == number, (-128...255).contains(number) else {
                    throw ImageDownloadError.invalidDecodeResult
                }
                bytes.append(UInt8(truncatingIfNeeded: value.intValue))
            }
            data = Data(bytes)
        }
        guard !data.isEmpty else { throw ImageDownloadError.emptyImage }
        guard validate(data) else { throw ImageDownloadError.invalidDecodeResult }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: path, options: .atomic)
        return data
    }

    public func recordChapterImages(book: Book, chapterIndex: Int, urls: [String]) throws {
        let folder = directory.appendingPathComponent(Self.bookScope(book), isDirectory: true)
        let indexFile = folder.appendingPathComponent("chapters.json")
        var chapters = try chapterImages(indexFile)
        chapters[String(chapterIndex)] = urls.map { Self.md5($0) + "." + Self.suffix($0) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(chapters).write(to: indexFile, options: .atomic)
    }

    public func pruneChapterImages(book: Book, chapterIndex: Int, retainPrevious: Int, preDownload: Int) throws {
        guard retainPrevious > 0 else { return }
        let folder = directory.appendingPathComponent(Self.bookScope(book), isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let indexFile = folder.appendingPathComponent("chapters.json")
        guard FileManager.default.fileExists(atPath: indexFile.path) else { return }
        let chapters = try chapterImages(indexFile)
        let start = chapterIndex.subtractingReportingOverflow(retainPrevious)
        let end = chapterIndex.addingReportingOverflow(max(0, preDownload))
        let lower = start.overflow ? Int.min : start.partialValue
        let upper = end.overflow ? Int.max : end.partialValue
        let retained = Set(chapters.filter { Int($0.key).map { (lower...upper).contains($0) } == true }.values.flatMap { $0 })
        let indexed = Set(chapters.values.flatMap { $0 })
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard indexed.contains(file.lastPathComponent), !retained.contains(file.lastPathComponent),
                  try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }

    private func chapterImages(_ file: URL) throws -> [String: [String]] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        return try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: file))
    }

    private static func bookScope(_ book: Book) -> String {
        let name = (book.name ?? "").replacingOccurrences(of: #"[\\/:*?"<>|.]"#, with: "", options: .regularExpression)
        return String(decoding: Array(name.utf16.prefix(9)), as: UTF16.self) + md5(book.bookUrl ?? "")
    }

    private static func md5(_ value: String) -> String {
        String(Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().dropFirst(8).prefix(16))
    }

    private static func suffix(_ url: String) -> String {
        let filename = UrlOptions.parse(url).url.components(separatedBy: "/").last ?? ""
        let path = filename.components(separatedBy: "?")[0].components(separatedBy: "#")[0]
        guard let dot = path.lastIndex(of: ".") else { return "jpg" }
        let suffix = String(path[path.index(after: dot)...])
        return suffix.range(of: #"^[a-zA-Z0-9]{1,5}$"#, options: .regularExpression) == nil ? "jpg" : suffix
    }
}
