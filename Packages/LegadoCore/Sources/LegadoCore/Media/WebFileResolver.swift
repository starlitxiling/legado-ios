import Foundation

public struct WebFile: Equatable, Sendable, Identifiable {
    public let url: String
    public let name: String
    public var id: String { url }
    public var suffix: String { (name as NSString).pathExtension.lowercased() }
    public var isSupported: Bool { LocalBook.fileExtensions.contains(suffix) || BookArchive.formats.contains(suffix) }

    public init(url: String, name: String) { self.url = url; self.name = name }
}

public enum WebFileResolver {
    public struct Download: Sendable {
        public let name: String
        public let data: Data
    }

    /// Port of `normalizeWebFileName` in Android BookInfoViewModel.kt.
    public static func normalizedName(_ fileName: String, rawSuffix: String?, replaceExistingSuffix: Bool = true) -> String {
        guard let suffix = rawSuffix?.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              suffix.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$"#, options: .regularExpression) != nil else { return fileName }
        var base = fileName
        while base.hasSuffix(".") { base.removeLast() }
        guard !base.isEmpty else { return fileName }
        guard let dot = base.lastIndex(of: "."), dot != base.startIndex else { return base + "." + suffix }
        let current = base[base.index(after: dot)...]
        if current.caseInsensitiveCompare(suffix) == .orderedSame { return base }
        return replaceExistingSuffix ? String(base[..<dot]) + "." + suffix : base + "." + suffix
    }

    public static func fallbackName(book: Book) -> String {
        let name = book.name ?? "未命名"
        let author = (book.author ?? "").trimmingCharacters(in: .whitespaces)
        return author.isEmpty ? name : "\(name) 作者：\(author)"
    }

    static func pathName(_ address: String) -> String? {
        guard let url = URL(string: address) else { return nil }
        let last = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        guard !last.isEmpty, last != "/", (last as NSString).pathExtension.isEmpty == false else { return nil }
        return last
    }

    public static func files(book: Book, downloadURLs: [String]) -> [WebFile] {
        downloadURLs.map { rule in
            let parsed = UrlOptions.parse(rule)
            let fromPath = pathName(parsed.url)
            let name = normalizedName(fromPath ?? fallbackName(book: book), rawSuffix: parsed.options.type,
                                      replaceExistingSuffix: fromPath != nil)
            return WebFile(url: rule, name: name)
        }
    }

    public static func download(_ file: WebFile, source: BookSource, book: Book, client: any HttpClient,
                                cookies: CookieStore = CookieStore(), maximumBytes: Int = 256 * 1024 * 1024) async throws -> Download {
        let client = (client as? any SourceSessionClientProviding)?.client(for: source) ?? client
        let context = try WebBookContext(source: source, client: client, book: book, cookies: cookies)
        let engine = try context.engine(baseURL: book.bookUrl ?? source.bookSourceUrl ?? "")
        let bindings: [String: Any] = ["book": try WebBookContext.object(book), "source": try WebBookContext.object(source)]
        let executor = try AnalyzeUrlExecutor(file.url, engine: engine, bindings: bindings)
        let response = try await executor.getResponse()
        guard (200..<300).contains(response.status) else {
            throw WebBookError.httpStatus(response.status, response.finalURL.absoluteString)
        }
        guard response.body.count <= maximumBytes else { throw WebDavError.responseTooLarge }
        guard !response.body.isEmpty else { throw WebFileError.empty(file.name) }
        var name = file.name
        if pathName(UrlOptions.parse(file.url).url) == nil, let header = dispositionName(response.headers) {
            name = normalizedName(header, rawSuffix: executor.options.type, replaceExistingSuffix: true)
        }
        return Download(name: sanitized(name), data: response.body)
    }

    static func dispositionName(_ headers: [String: String]) -> String? {
        let disposition = headers.first { $0.key.caseInsensitiveCompare("Content-Disposition") == .orderedSame }?.value ?? ""
        let patterns = [#"(?i)(?:^|;)\s*filename\*\s*=\s*([^;]+)"#, #"(?i)(?:^|;)\s*filename\s*=\s*(?:"([^"]+)"|([^;]+))"#]
        for (patternIndex, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: disposition, range: NSRange(disposition.startIndex..., in: disposition)) else { continue }
            for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
                let value = (disposition as NSString).substring(with: match.range(at: index)).trimmingCharacters(in: .whitespaces)
                if patternIndex == 0 {
                    let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                    if pieces.count == 3, pieces[0].lowercased() == "utf-8", let decoded = String(pieces[2]).removingPercentEncoding {
                        return decoded
                    }
                } else if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func sanitized(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:\0")).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "download" : cleaned
    }
}

public enum WebFileError: LocalizedError, Equatable {
    case empty(String)
    case noDownloads

    public var errorDescription: String? {
        switch self {
        case .empty(let name): return "下载的文件「\(name)」为空"
        case .noDownloads: return "书源没有提供可下载的文件"
        }
    }

    public var recoverySuggestion: String? { "请重试，或切换书源。" }
}
