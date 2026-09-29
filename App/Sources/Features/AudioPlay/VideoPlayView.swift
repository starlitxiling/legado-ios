import SwiftUI
import AVKit
import LegadoCore

@MainActor
@Observable
final class VideoPlaybackModel {
    let library: MediaBookLibrary
    let player = AVPlayer()
    private(set) var chapter = 0
    private(set) var isLoadingVideo = false
    private(set) var userError: UserFacingError?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?

    init(library: MediaBookLibrary) { self.library = library }

    var title: String {
        library.chapters.indices.contains(chapter) ? library.chapters[chapter].title ?? "" : ""
    }

    func start() async {
        if library.chapters.isEmpty { await library.load() }
        guard library.userError == nil, !library.chapters.isEmpty else { return }
        observe()
        select(library.initialChapter, position: library.book.durChapterPos)
    }

    func select(_ index: Int, position: Int = 0) {
        guard library.chapters.indices.contains(index) else { return }
        saveProgress()
        chapter = index
        userError = nil
        isLoadingVideo = true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resource = try await library.video(index)
                guard !Task.isCancelled, chapter == index else { return }
                let asset = AVURLAsset(url: resource.url, options: ["AVURLAssetHTTPHeaderFieldsKey": resource.headers])
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                if position > 0 { await player.seek(to: CMTime(value: CMTimeValue(position), timescale: 1000)) }
                player.play()
            } catch {
                guard !Task.isCancelled else { return }
                userError = error.presentation(operation: "加载视频", subject: title, actions: [.retry])
            }
            if chapter == index { isLoadingVideo = false }
        }
    }

    func retry() { select(chapter, position: currentPosition) }

    func dismissError() { userError = nil }

    func stop() {
        saveProgress()
        loadTask?.cancel()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
    }

    private var currentPosition: Int {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, Int(seconds * 1000)) : 0
    }

    private func saveProgress() {
        guard library.chapters.indices.contains(chapter), player.currentItem != nil else { return }
        let index = chapter, position = currentPosition
        Task { try? await library.save(chapter: index, position: position) }
    }

    private func observe() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil,
                                                             queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, (notification.object as? AVPlayerItem) === self.player.currentItem else { return }
                if self.chapter + 1 < self.library.chapters.count { self.select(self.chapter + 1) } else { self.saveProgress() }
            }
        }
    }
}

struct VideoPlayView: View {
    @State private var model: VideoPlaybackModel
    @Environment(\.themeColors) private var colors

    init(book: Book, database: AppDatabase, client: any HttpClient) {
        _model = State(initialValue: VideoPlaybackModel(library: MediaBookLibrary(book: book, database: database, client: client)))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: model.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.black)
                .overlay { if model.isLoadingVideo { ProgressView().tint(.white) } }
                .accessibilityIdentifier("video.player")
            List {
                Section {
                    if model.library.isLoading { ProgressView("正在加载视频目录") }
                    if let error = model.library.userError {
                        ErrorBanner(error: error, dismiss: model.library.dismissError) { _ in Task { await model.start() } }
                    }
                    if let error = model.userError {
                        ErrorBanner(error: error, dismiss: model.dismissError) { _ in model.retry() }
                    }
                    Text(model.library.book.name ?? "视频").font(.headline)
                    if !model.title.isEmpty { Text(model.title).foregroundStyle(colors.textSecondary) }
                    HStack(spacing: 24) {
                        Button("上一集", systemImage: "backward.end") { model.select(model.chapter - 1) }
                            .disabled(model.chapter <= 0)
                        Button("下一集", systemImage: "forward.end") { model.select(model.chapter + 1) }
                            .disabled(model.chapter + 1 >= model.library.chapters.count)
                    }.buttonStyle(.borderless)
                }
                Section("选集") {
                    ForEach(model.library.chapters.indices, id: \.self) { index in
                        Button { model.select(index) } label: {
                            HStack {
                                Text(model.library.chapters[index].title ?? "第 \(index + 1) 集")
                                Spacer()
                                if index == model.chapter { Image(systemName: "play.fill").foregroundStyle(colors.accent) }
                            }
                        }.accessibilityIdentifier("video.episode.\(index)")
                    }
                }
            }.listStyle(.insetGrouped)
        }
        .legadoNavigationTitle("视频播放")
        .task { await model.start() }
        .onDisappear { model.stop() }
    }
}
