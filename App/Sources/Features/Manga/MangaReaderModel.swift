import Foundation
import ImageIO
import Observation
import LegadoCore

@Observable @MainActor
final class MangaReaderModel {
    enum ImageState: Equatable { case loading, ready(Data), failed(String) }
    private(set) var chapter: Int
    private(set) var page: Int
    let chapterCount: Int
    var preloadCount: Int
    private(set) var images: [MediaResource] = []
    private(set) var imageData: [Int: Data] = [:]
    private(set) var imageErrors: [Int: String] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let loadContent: (Int) async throws -> [MediaResource]
    private let loadImage: (MediaResource) async throws -> Data
    private let saveProgress: (Int, Int) async throws -> Void
    private let validateImage: (Data) -> Bool
    private var generation = 0
    private var prefetchGeneration = 0
    private var imageWork: Task<Void, Never>?

    init(chapterCount: Int, chapter: Int = 0, page: Int = 0, preloadCount: Int = 10,
         loadContent: @escaping (Int) async throws -> [MediaResource],
         loadImage: @escaping (MediaResource) async throws -> Data,
         validateImage: @escaping (Data) -> Bool = MangaReaderModel.canDecodeImage,
         saveProgress: @escaping (Int, Int) async throws -> Void) {
        self.chapterCount = max(0, chapterCount); self.chapter = chapter; self.page = page
        self.preloadCount = min(max(0, preloadCount), 30)
        self.loadContent = loadContent; self.loadImage = loadImage; self.saveProgress = saveProgress
        self.validateImage = validateImage
    }

    nonisolated static func canDecodeImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    func imageState(at index: Int) -> ImageState {
        if let error = imageErrors[index] { return .failed(error) }
        if let data = imageData[index] { return .ready(data) }
        return .loading
    }

    func imageDecodingFailed(at index: Int) {
        guard images.indices.contains(index) else { return }
        imageData[index] = nil; imageErrors[index] = "图片解码失败"
    }

    nonisolated static func preloadWindow(page: Int, count: Int, ahead: Int) -> [Int] {
        guard count > 0 else { return [] }
        let current = min(max(0, page), count - 1)
        return Array(max(0, current - 1)...(current + min(max(0, ahead), count - current - 1)))
    }

    func open(chapter index: Int, page requestedPage: Int = 0) async {
        guard (0..<chapterCount).contains(index) else { return }
        generation += 1; prefetchGeneration += 1
        let token = generation
        isLoading = true; errorMessage = nil
        images = []; imageData = [:]; imageErrors = [:]
        defer { if generation == token { isLoading = false } }
        do {
            let result = try await loadContent(index)
            guard token == generation, !Task.isCancelled else { return }
            guard !result.isEmpty else { throw WebBookError.emptyContent }
            chapter = index; images = result
            page = min(max(0, requestedPage), result.count - 1)
            try await saveProgress(chapter, page)
            guard token == generation else { return }
            isLoading = false
            await prefetch()
        } catch {
            if token == generation, !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func show(page index: Int) async {
        guard !isLoading, images.indices.contains(index) else { return }
        page = index
        do { try await saveProgress(chapter, page) }
        catch { errorMessage = error.localizedDescription }
        await prefetch()
    }

    func previousChapter() async { await open(chapter: chapter - 1) }
    func nextChapter() async { await open(chapter: chapter + 1) }

    func cancel() {
        generation += 1; prefetchGeneration += 1
        imageWork?.cancel(); isLoading = false
    }

    func prefetch() async {
        prefetchGeneration += 1
        let token = generation
        let prefetchToken = prefetchGeneration
        let window = Self.preloadWindow(page: page, count: images.count, ahead: min(max(0, preloadCount), 30))
        imageData = imageData.filter { window.contains($0.key) }
        imageErrors = imageErrors.filter { window.contains($0.key) }
        let previous = imageWork
        previous?.cancel()
        let work = Task {
            await previous?.value
            await fetchWindow(window, token: token, prefetchToken: prefetchToken)
        }
        imageWork = work
        await work.value
    }

    private func fetchWindow(_ window: [Int], token: Int, prefetchToken: Int) async {
        // 等旧请求退出后才启动新窗口，非协作取消的加载器也不会突破并发限制。
        for index in window {
            guard token == generation, prefetchToken == prefetchGeneration, !Task.isCancelled else { return }
            if imageData[index] != nil { continue }
            let resource = images[index]
            do {
                let data = try await loadImage(resource)
                guard token == generation, prefetchToken == prefetchGeneration, !Task.isCancelled else { return }
                guard validateImage(data) else { imageDecodingFailed(at: index); continue }
                imageData[index] = data; imageErrors[index] = nil
            } catch {
                guard token == generation, prefetchToken == prefetchGeneration, !Task.isCancelled else { return }
                if let imageError = error as? ImageDownloadError, case .invalidDecodeResult = imageError {
                    imageDecodingFailed(at: index)
                } else { imageErrors[index] = error.localizedDescription }
            }
        }
    }
}
