import XCTest
import LegadoCore
@testable import MediaCheck

final class MangaReaderModelTests: XCTestCase {
    @MainActor func testUndecodableImageBecomesErrorAndRetryReplacesIt() async {
        var bytes = Data("not an image".utf8)
        let model = MangaReaderModel(chapterCount: 1,
            loadContent: { _ in [MediaResource(url: URL(string: "https://site.test/a")!)] },
            loadImage: { _ in bytes }, saveProgress: { _, _ in })
        await model.open(chapter: 0)
        XCTAssertNotNil(model.imageErrors[0])
        XCTAssertNil(model.imageData[0])
        XCTAssertEqual(model.imageState(at: 0), .failed("图片解码失败"))
        bytes = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
        await model.prefetch()
        XCTAssertNil(model.imageErrors[0])
        XCTAssertEqual(model.imageData[0], bytes)
        XCTAssertEqual(model.imageState(at: 0), .ready(bytes))
    }

    func testPreloadWindowClampsInvalidInputs() {
        XCTAssertEqual(MangaReaderModel.preloadWindow(page: 2, count: 8, ahead: 3), [1, 2, 3, 4, 5])
        XCTAssertEqual(MangaReaderModel.preloadWindow(page: 7, count: 8, ahead: 10), [6, 7])
        XCTAssertEqual(MangaReaderModel.preloadWindow(page: -1, count: 3, ahead: -5), [0])
        XCTAssertEqual(MangaReaderModel.preloadWindow(page: 0, count: 0, ahead: 10), [])
    }

    @MainActor func testRestoreProgressAndChapterChanges() async {
        var saved: [(Int, Int)] = []
        let model = MangaReaderModel(chapterCount: 2, chapter: 1, page: 2,
            loadContent: { _ in (0..<4).map { MediaResource(url: URL(string: "https://site.test/\($0).jpg")!) } },
            loadImage: { _ in Data([1]) }, validateImage: { _ in true }, saveProgress: { saved.append(($0, $1)) })
        await model.open(chapter: 1, page: 2)
        XCTAssertEqual(model.page, 2)
        await model.show(page: 3)
        XCTAssertEqual(saved.last?.0, 1); XCTAssertEqual(saved.last?.1, 3)
        await model.previousChapter()
        XCTAssertEqual(model.chapter, 0); XCTAssertEqual(model.page, 0)
        await model.nextChapter()
        XCTAssertEqual(model.chapter, 1); XCTAssertEqual(model.page, 0)
        await model.nextChapter()
        XCTAssertEqual(model.chapter, 1)
    }

    @MainActor func testPrefetchBoundedAndErrorsVisible() async {
        var loaded: [String] = []
        let model = MangaReaderModel(chapterCount: 1, preloadCount: 2,
            loadContent: { _ in (0..<10).map { MediaResource(url: URL(string: "https://site.test/\($0)")!) } },
            loadImage: { resource in loaded.append(resource.url.lastPathComponent); return Data([1]) },
            validateImage: { _ in true },
            saveProgress: { _, _ in })
        await model.open(chapter: 0)
        XCTAssertEqual(loaded, ["0", "1", "2"])
        XCTAssertEqual(model.imageData.count, 3)
        await model.show(page: 9)
        XCTAssertLessThanOrEqual(model.imageData.count, 4)
        let bad = MangaReaderModel(chapterCount: 1, loadContent: { _ in throw URLError(.badServerResponse) },
            loadImage: { _ in Data() }, saveProgress: { _, _ in })
        await bad.open(chapter: 0)
        XCTAssertNotNil(bad.errorMessage)
    }

    @MainActor func testConcurrentPageChangesSerializeImageRequests() async {
        let gate = MangaImageGate()
        let started = expectation(description: "图片请求已开始")
        var requests = 0
        let model = MangaReaderModel(chapterCount: 1, preloadCount: 1,
            loadContent: { _ in (0..<4).map { MediaResource(url: URL(string: "https://site.test/\($0)")!) } },
            loadImage: { _ in
                requests += 1
                if requests == 1 { started.fulfill() }
                await gate.wait()
                return Data([1])
            }, validateImage: { _ in true }, saveProgress: { _, _ in })
        let opening = Task { await model.open(chapter: 0) }
        await fulfillment(of: [started], timeout: 2)
        let moving = Task { await model.show(page: 3) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(requests, 1)
        gate.release()
        await opening.value; await moving.value
        XCTAssertEqual(model.page, 3)
        XCTAssertEqual(Set(model.imageData.keys), [2, 3])
    }

    @MainActor func testAudioOwnershipStopsPreviousBeforeStartingNext() {
        let first = UUID(), second = UUID()
        var stopped = 0
        AudioSessionOwnership.claim(first) { stopped += 1 }
        AudioSessionOwnership.claim(first) { stopped += 10 }
        XCTAssertEqual(stopped, 0)
        AudioSessionOwnership.claim(second) { stopped += 100 }
        XCTAssertEqual(stopped, 1)
        AudioSessionOwnership.relinquish(first)
        XCTAssertTrue(AudioSessionOwnership.isOwner(second))
        AudioSessionOwnership.relinquish(second)
        XCTAssertFalse(AudioSessionOwnership.isOwner(second))
    }

    @MainActor func testLibraryPersistsMangaAndAudioPositions() async throws {
        let database = try AppDatabase.inMemory()
        var source = BookSource(); source.bookSourceUrl = "https://site.test"; source.bookSourceType = 2
        var toc = TocRule(); toc.chapterList = "tag.a"; toc.chapterName = "text"; toc.chapterUrl = "href"
        source.ruleToc = toc
        try await BookSourceRepository(database: database).upsert(DiscoveryStorage.row(source, defaults: BookSourceRow()))
        var book = Book(now: 0); book.bookUrl = "https://site.test/book"; book.tocUrl = "https://site.test/toc"
        book.origin = "https://site.test"; book.type = 64
        let library = MediaBookLibrary(book: book, database: database, client: MangaLibraryClient())
        await library.load()
        XCTAssertNil(library.errorMessage)
        XCTAssertEqual(library.chapters.count, 2)
        try await library.save(chapter: 1, position: 8)
        let restored = MediaBookLibrary(book: book, database: database, client: MangaLibraryClient())
        await restored.load()
        XCTAssertEqual(restored.initialChapter, 1); XCTAssertEqual(restored.book.durChapterPos, 8)
        library.record(chapter: 0, position: 42000)
        try await library.save(chapter: 1, position: 125000)
        let saved = try await BookshelfRepository(database: database).get(bookUrl: book.bookUrl!)
        XCTAssertEqual(saved?.durChapterIndex, 1); XCTAssertEqual(saved?.durChapterPos, 125000)
        XCTAssertEqual(saved?.type, 64 | 1024)
    }
}

private struct MangaLibraryClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: 200, body: Data(#"<a href="/one">第一章</a><a href="/two">第二章</a>"#.utf8), finalURL: request.url)
    }
}

@MainActor private final class MangaImageGate {
    private var open = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if open { return }
        await withCheckedContinuation { pending.append($0) }
    }
    func release() { open = true; pending.forEach { $0.resume() }; pending = [] }
}
