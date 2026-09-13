import Foundation
import LegadoCore

struct SmokeOptions {
    let sourcePath: String
    let keyword: String
    var pick = 0
    var chapters = 2
    var sourceIndex = 0
    var timeout: Double = 60

    init(arguments: [String]) throws {
        var values: [String: String] = [:]
        let allowed = ["--source", "--keyword", "--pick", "--chapters", "--source-index", "--timeout"]
        guard arguments.count.isMultiple(of: 2) else { throw SmokeError.invalidArguments }
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let flag = arguments[index]
            guard allowed.contains(flag), values[flag] == nil else { throw SmokeError.invalidArguments }
            values[flag] = arguments[index + 1]
        }
        guard let path = values["--source"], !path.isEmpty,
              let key = values["--keyword"], !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let pick = Int(values["--pick"] ?? "0"), pick >= 0,
              let chapters = Int(values["--chapters"] ?? "2"), chapters > 0,
              let sourceIndex = Int(values["--source-index"] ?? "0"), sourceIndex >= 0,
              let timeout = Double(values["--timeout"] ?? "60"), timeout.isFinite, timeout > 0 else {
            throw SmokeError.invalidArguments
        }
        sourcePath = path; keyword = key
        self.pick = pick; self.chapters = chapters; self.sourceIndex = sourceIndex; self.timeout = timeout
    }
}

enum SmokeError: Error {
    case invalidArguments, invalidSource, unsupportedSource, sourceIndexOutOfBounds, pickOutOfBounds, noReadableChapters
}

struct SmokeFailure: Error {
    let stage: String
    let context: String
    let errorCase: String
}

struct SmokeReport {
    let searchCount: Int
    let chapterCount: Int
    let contentCount: Int
}

struct TimeoutClient: HttpClient {
    let base: any HttpClient
    let seconds: Double

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        try await send(request, cookieStore: nil)
    }

    func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse {
        var request = request
        request.timeout = min(request.timeout, seconds)
        request.callTimeout = min(request.callTimeout, seconds)
        return try await base.send(request, cookieStore: cookieStore)
    }
}

func safeText(_ text: String) -> String {
    var result = text
    for pattern in [#"(?i)(?:cookie|authorization|password|passwd|token|api[_-]?key)\s*[:=].*"#,
                    #"(?i)(?:https?://|www\.)[^\s<>]+"#,
                    #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
                    #"[A-Za-z0-9_+/=-]{24,}"#] {
        result = result.replacingOccurrences(of: pattern, with: "[已隐藏]", options: .regularExpression)
    }
    return result.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
}

func safeError(_ error: Error) -> String {
    if case let WebBookError.httpStatus(status, _) = error { return "WebBookError.httpStatus(\(status))" }
    if let error = error as? URLError { return "URLError(code: \(error.code.rawValue))" }
    if error is CancellationError { return "CancellationError" }
    let mirror = Mirror(reflecting: error)
    let type = String(describing: Swift.type(of: error))
    guard mirror.displayStyle == .enum else { return type }
    if let label = mirror.children.first?.label { return "\(type).\(label)" }
    let value = String(describing: error)
    guard value.range(of: #"^[A-Za-z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { return type }
    return "\(type).\(value)"
}

func addressSummary(_ address: String?) -> String {
    let url = address.flatMap { URL(string: UrlOptions.parse($0).url) }
    return "host=\(safeText(url?.host ?? "未知"))，路径长度=\(url?.path.count ?? 0)"
}

func runSmoke(options: SmokeOptions, client: any HttpClient,
              emit: (String) -> Void = { print($0) }) async throws -> SmokeReport {
    var stage = "解析书源"
    var context = "source-index=\(options.sourceIndex)"
    var start = ContinuousClock.now
    func elapsed() -> String {
        let parts = start.duration(to: .now).components
        return String(format: "%.3f 秒", locale: Locale(identifier: "en_US_POSIX"),
                      Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }
    func complete() { emit("\(stage)完成，耗时 \(elapsed())") }
    do {
        let text = try String(contentsOfFile: options.sourcePath, encoding: .utf8)
        guard case let .sources(sources) = SourceImporter().parseBookSources(text) else { throw SmokeError.invalidSource }
        guard sources.indices.contains(options.sourceIndex) else { throw SmokeError.sourceIndexOutOfBounds }
        let imported = sources[options.sourceIndex]
        guard imported.support == .supported else { throw SmokeError.unsupportedSource }
        let source = imported.source
        emit("书源：\(safeText(source.bookSourceName ?? "未命名"))，\(addressSummary(source.bookSourceUrl))")
        complete()
        let web = WebBook(source: source, client: TimeoutClient(base: client, seconds: options.timeout))
        stage = "搜索"; context = "关键词长度=\(options.keyword.count)，page=1"; start = .now
        let results = try await web.search(key: options.keyword)
        emit("搜索结果数：\(results.count)")
        for (index, result) in results.prefix(5).enumerated() {
            emit("[\(index)] \(safeText(result.name ?? "")) / \(safeText(result.author ?? ""))，\(addressSummary(result.bookUrl))")
        }
        context = "pick=\(options.pick)，结果数=\(results.count)"
        guard results.indices.contains(options.pick) else { throw SmokeError.pickOutOfBounds }
        complete()
        stage = "详情"; context = "pick=\(options.pick)，\(addressSummary(results[options.pick].bookUrl))"; start = .now
        var book = try await web.bookInfo(results[options.pick])
        emit("详情：\(safeText(book.name ?? "")) / \(safeText(book.author ?? ""))")
        complete()
        stage = "目录"; context = addressSummary(book.tocUrl); start = .now
        let chapters = try await web.chapterList(book: &book)
        emit("章节数：\(chapters.count)")
        emit("前 3 章：\(chapters.prefix(3).map { safeText($0.title ?? "") }.joined(separator: " / "))")
        emit("后 3 章：\(chapters.suffix(3).map { safeText($0.title ?? "") }.joined(separator: " / "))")
        complete()
        let readable = chapters.indices.filter { !chapters[$0].isVolume }.prefix(options.chapters)
        guard !readable.isEmpty else { throw SmokeError.noReadableChapters }
        for index in readable {
            stage = "正文"; context = "章节索引=\(index)，\(addressSummary(chapters[index].url))"; start = .now
            let next = chapters.indices.contains(index + 1) ? chapters[index + 1].url : nil
            let content = try await web.content(book: book, chapter: chapters[index], nextChapterUrl: next, includeTitle: false)
            emit("正文[\(index)] 字数=\(content.text.filter { !$0.isWhitespace }.count)，前 60 字：\(safeText(content.text).prefix(60))")
            complete()
        }
        return SmokeReport(searchCount: results.count, chapterCount: chapters.count, contentCount: readable.count)
    } catch {
        emit("\(stage)失败，耗时 \(elapsed())")
        throw SmokeFailure(stage: stage, context: context, errorCase: safeError(error))
    }
}

@main
struct WebBookSmoke {
    static func main() async {
        do {
            let options = try SmokeOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            _ = try await runSmoke(options: options, client: URLSessionHttpClient())
        } catch {
            let message: String
            if let failure = error as? SmokeFailure {
                message = "失败（\(failure.stage)，\(failure.context)）：\(failure.errorCase)"
            } else { message = "失败（参数解析）：\(safeError(error))" }
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }
}
