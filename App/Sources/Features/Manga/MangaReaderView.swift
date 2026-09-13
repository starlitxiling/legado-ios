import SwiftUI
import UIKit
import LegadoCore
import Network

@MainActor
struct MangaReaderView: View {
    @State private var library: MediaBookLibrary
    @State private var model: MangaReaderModel?
    @AppStorage("mangaHorizontal") private var horizontal = false
    @AppStorage("mangaPreloadCount") private var preloadCount = 10
    private let database: AppDatabase
    private let client: any HttpClient
    @State private var networkMonitor: NWPathMonitor?
    @State private var networkAvailable: Bool?
    @State private var pendingProgress: BookProgress?
    @State private var syncError: String?
    @State private var synchronizing = false
    @State private var syncWaiters: [CheckedContinuation<Void, Never>] = []
    @State private var exited = false

    init(book: Book, database: AppDatabase, client: any HttpClient) {
        self.database = database; self.client = client
        _library = State(initialValue: MediaBookLibrary(book: book, database: database, client: client, imageRetention: {
            (UserDefaults.standard.integer(forKey: "imageRetainNum"),
             (UserDefaults.standard.object(forKey: "preDownloadNum") as? NSNumber)?.intValue ?? 2)
        }))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let syncError { Text(syncError).foregroundStyle(.red) }
            if let error = library.errorMessage {
                Text(error).foregroundStyle(.red)
                Button("重试") { Task { await load() } }
            }
            if let model {
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button("重试章节") { Task { await model.open(chapter: model.chapter, page: model.page) } }
                }
                if model.isLoading { ProgressView("正在加载漫画") }
                else {
                    MangaPages(model: model, horizontal: horizontal).id(model.chapter)
                    HStack {
                        Button("上一章") { Task { await model.previousChapter() } }.disabled(model.chapter <= 0)
                        Spacer()
                        Text("\(model.page + 1) / \(model.images.count)").font(.caption)
                        Spacer()
                        Button("下一章") { Task { await model.nextChapter() } }
                            .disabled(model.chapter + 1 >= model.chapterCount)
                    }.padding()
                }
            } else if library.isLoading { ProgressView("正在加载目录") }
        }
        .navigationTitle(model.flatMap { library.chapters.indices.contains($0.chapter) ? library.chapters[$0.chapter].title : nil } ?? "漫画")
        .toolbar {
            Menu("阅读设置") {
                Toggle("横向翻页", isOn: $horizontal)
                Picker("预加载图片", selection: $preloadCount) {
                    ForEach([0, 5, 10, 20], id: \.self) { Text("\($0) 张").tag($0) }
                }
                if let model {
                    Picker("章节", selection: Binding(get: { model.chapter }, set: { index in
                        Task { await model.open(chapter: index) }
                    })) {
                        ForEach(library.chapters.indices, id: \.self) { index in
                            Text(library.chapters[index].title ?? "第 \(index + 1) 章").tag(index)
                        }
                    }
                }
            }
        }
        .onChange(of: preloadCount) { _, count in
            model?.preloadCount = count
            Task { await model?.prefetch() }
        }
        .task {
            exited = false
            if let model {
                if model.images.isEmpty { await model.open(chapter: model.chapter, page: model.page) }
                else { await model.prefetch() }
            } else { await load() }
            let monitor = NWPathMonitor()
            networkAvailable = nil
            monitor.pathUpdateHandler = { path in
                let available = path.status == .satisfied
                Task { @MainActor in
                    let restored = networkAvailable == false && available
                    networkAvailable = available
                    if restored, !exited { await synchronizeProgress(exiting: false) }
                }
            }
            networkMonitor?.cancel(); networkMonitor = monitor
            monitor.start(queue: DispatchQueue(label: "Legado.manga.webdav.network"))
        }
        .alert("发现更新的阅读进度", isPresented: Binding(get: { pendingProgress != nil }, set: { if !$0 { pendingProgress = nil } }), presenting: pendingProgress) { progress in
            Button("跳转") {
                if let index = library.chapters.firstIndex(where: { $0.index == progress.durChapterIndex }) {
                    Task { await model?.open(chapter: index, page: progress.durChapterPos) }
                }
            }
            Button("取消", role: .cancel) { pendingProgress = nil }
        } message: { _ in
            Text("是否跳转到远端的阅读位置？")
        }
        .onDisappear {
            networkMonitor?.cancel(); networkMonitor = nil; model?.cancel()
            if !exited { exited = true; Task { await synchronizeProgress(exiting: true) } }
        }
    }

    private func synchronizeProgress(exiting: Bool) async {
        if exiting, synchronizing {
            await withCheckedContinuation { syncWaiters.append($0) }
        }
        let preferences = AppPreferences.shared
        let action = BookProgressSync.readingAction(syncEnabled: preferences.boolean("syncBookProgress"),
            plusEnabled: preferences.boolean("syncBookProgressPlus"), exiting: exiting)
        guard action != .none, !synchronizing, let model, !model.isLoading,
              library.book.type & DiscoveryStorage.hiddenBook == 0 else { return }
        synchronizing = true
        syncError = nil
        defer {
            synchronizing = false
            let waiters = syncWaiters
            syncWaiters = []
            for waiter in waiters { waiter.resume() }
        }
        do {
            let settings = SettingsViewModel(store: KeychainStore(), httpClient: client)
            guard !settings.address.isEmpty else { return }
            let credentials = try settings.credentials()
            let dav = WebDavClient(baseURL: credentials.baseURL, username: credentials.username, password: credentials.password, httpClient: client)
            let sync = BookProgressSync(client: dav, directory: preferences.string("webDavDir"))
            try await library.save(chapter: model.chapter, position: model.page)
            guard let current = try await BookshelfRepository(database: database).get(bookUrl: library.book.bookUrl ?? "") else { return }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if action == .synchronize {
                let result = try await sync.synchronizeReading(current, now: now)
                if result.book.syncTime != current.syncTime {
                    try await BookProgressSync.save(result.book, replacing: current, database: database)
                }
                if !exiting, !exited { pendingProgress = result.remoteProgress }
            } else {
                let uploaded = try await sync.upload(current, now: now)
                try await BookProgressSync.save(uploaded, replacing: current, database: database)
            }
        } catch { syncError = error.localizedDescription }
    }

    private func load() async {
        await library.load()
        guard library.errorMessage == nil, !Task.isCancelled else { return }
        let library = library
        let model = MangaReaderModel(chapterCount: library.chapters.count, chapter: library.initialChapter,
            page: library.book.durChapterPos, preloadCount: preloadCount,
            loadContent: { try await library.images($0) }, loadImage: { try await library.image($0) },
            saveProgress: { try await library.save(chapter: $0, position: $1) })
        self.model = model
        await model.open(chapter: library.initialChapter, page: library.book.durChapterPos)
    }
}

private struct MangaPages: View {
    let model: MangaReaderModel
    let horizontal: Bool
    @State private var scrollPage: Int?
    @State private var ratios: [Int: CGFloat] = [:]

    var body: some View {
        Group {
            if horizontal {
                TabView(selection: Binding(get: { model.page }, set: { page in Task { await model.show(page: page) } })) {
                    ForEach(model.images.indices, id: \.self) { index in page(index).tag(index) }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.images.indices, id: \.self) { index in
                            page(index).aspectRatio(ratios[index] ?? 0.7, contentMode: .fit).id(index)
                        }
                    }.scrollTargetLayout()
                }
                .scrollPosition(id: $scrollPage, anchor: .top)
                .onChange(of: scrollPage) { _, page in
                    if let page, page != model.page { Task { await model.show(page: page) } }
                }
            }
        }
        .onAppear { scrollPage = model.page; updateRatios() }
        .onChange(of: horizontal) { _, _ in scrollPage = model.page }
        .onChange(of: model.imageData) { _, _ in updateRatios() }
    }

    private func updateRatios() {
        for (index, data) in model.imageData {
            if let image = UIImage(data: data), image.size.height > 0 { ratios[index] = image.size.width / image.size.height }
        }
    }

    @ViewBuilder private func page(_ index: Int) -> some View {
        switch model.imageState(at: index) {
        case .ready(let data):
            if let image = UIImage(data: data) { MangaZoomImage(image: image) }
            else { imageError("图片解码失败").task { model.imageDecodingFailed(at: index) } }
        case .failed(let message): imageError(message)
        case .loading: ProgressView().frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private func imageError(_ message: String) -> some View {
        VStack { Text(message).font(.caption); Button("重试图片") { Task { await model.prefetch() } } }
            .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct MangaZoomImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var translation = CGSize.zero

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .scaleEffect(min(5, max(1, scale * magnification)))
            .offset(x: offset.width + translation.width, y: offset.height + translation.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    scale = min(5, max(1, scale * value.magnification))
                    if scale == 1 { offset = .zero }
                })
            .simultaneousGesture(DragGesture().updating($translation) { value, state, _ in
                if scale > 1 { state = value.translation }
            }.onEnded { value in
                if scale > 1 { offset.width += value.translation.width; offset.height += value.translation.height }
            }, including: scale > 1 ? .all : .subviews)
            .onTapGesture(count: 2) { scale = 1; offset = .zero }
    }
}
