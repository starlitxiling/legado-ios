import SwiftUI
import UIKit
import CoreText
import LegadoCore
import Network

@MainActor
struct ReaderView: View {
    let destination: ReaderDestination
    @Environment(\.themeColors) private var themeColors
    @State private var model: ReaderViewModel
    @State private var readAloud: ReadAloudController
    @State private var showsReadAloud = false
    @State private var showsControls = false
    @State private var showsSettings = false
    @State private var styles: ReaderStyleStore
    @State private var styleError: String?
    @State private var showsChapters = false
    @State private var showsBookmarks = false
    @State private var showsSelection = false
    @State private var showsHighlights = false
    @State private var showsReviews = false
    @State private var autoRead = AutoReadController()
    @State private var networkMonitor: NWPathMonitor?
    @State private var networkAvailable: Bool?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(destination: ReaderDestination, database: AppDatabase, client: any HttpClient,
         cacheDirectory: URL? = nil) {
        self.destination = destination
        _styles = State(initialValue: ReaderStyleStore(database: database))
        let directory = cacheDirectory ?? URL.applicationSupportDirectory
            .appendingPathComponent("Legado/ReaderCache", isDirectory: true)
        let model = ReaderViewModel(database: database, client: client,
            cacheDirectory: directory, settings: ReaderSettings.load(),
            threadCount: UserDefaults.standard.object(forKey: "threadCount") as? Int ?? 32,
            adaptSpecialStyle: UserDefaults.standard.object(forKey: "adaptSpecialStyle") as? Bool ?? true, preDownloadCount: {
                UserDefaults.standard.object(forKey: "preDownloadNum") as? Int ?? 2
            })
        model.chineseConverterType = { UserDefaults.standard.integer(forKey: "chineseConverterType") }
        model.replaceEnableDefault = { UserDefaults.standard.object(forKey: "replaceEnableDefault") as? Bool ?? true }
        @MainActor func webDavClient() throws -> WebDavClient? {
            let settings = SettingsViewModel(store: KeychainStore(), httpClient: client)
            guard !settings.address.isEmpty else { return nil }
            let credentials = try settings.credentials()
            return WebDavClient(baseURL: credentials.baseURL, username: credentials.username, password: credentials.password, httpClient: client)
        }
        model.prepareLocalBook = { book in
            let preferences = AppPreferences.shared
            guard book.origin == "loc_book" || book.origin.hasPrefix("webDav::"),
                  preferences.boolean("webDavBookAutoRestore") || book.origin.hasPrefix("webDav::") else { return book }
            let dav: WebDavClient
            let remote = book.origin.hasPrefix("webDav::") ? String(book.origin.dropFirst("webDav::".count)) : ""
            if UrlOptions.parse(remote).options.serverID != nil {
                dav = try await WebDavClient.fromPath(remote, servers: ServerRepository(database: database), httpClient: client)
            } else if let fallback = try webDavClient() {
                dav = fallback
            } else { return book }
            return try await WebDavLocalBookRestore(client: dav, directory: preferences.string("webDavDir"),
                destination: URL.applicationSupportDirectory.appendingPathComponent("Legado/LocalBooks", isDirectory: true))
                .restore(book, enabled: preferences.boolean("webDavBookAutoRestore"))
        }
        model.synchronizeWebDav = { book, exiting in
            let preferences = AppPreferences.shared
            let action = BookProgressSync.readingAction(syncEnabled: preferences.boolean("syncBookProgress"),
                plusEnabled: preferences.boolean("syncBookProgressPlus"), exiting: exiting)
            guard action != .none, let dav = try webDavClient() else { return nil }
            let sync = BookProgressSync(client: dav, directory: preferences.string("webDavDir"))
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if action == .synchronize {
                let result = try await sync.synchronizeReading(book, now: now)
                if result.book.syncTime != book.syncTime {
                    try await BookProgressSync.save(result.book, replacing: book, database: database)
                }
                return exiting ? nil : result.remoteProgress
            }
            let uploaded = try await sync.upload(book, now: now)
            try await BookProgressSync.save(uploaded, replacing: book, database: database)
            return nil
        }
        _model = State(initialValue: model)
        _readAloud = State(initialValue: ReadAloudController(database: database, client: client))
    }

    init(book: BookRow, chapterIndex: Int? = nil, database: AppDatabase, client: any HttpClient) {
        self.init(destination: ReaderDestination(bookURL: book.bookUrl, chapterIndex: chapterIndex),
                  database: database, client: client)
    }

    init(book: Book, chapterIndex: Int? = nil, database: AppDatabase, client: any HttpClient) {
        self.init(destination: ReaderDestination(bookURL: book.bookUrl ?? "", chapterIndex: chapterIndex),
                  database: database, client: client)
    }

    private var background: some View { ReaderBackgroundView(settings: model.settings) }

    private var infoValues: ReaderInfoValues {
        let count = max(1, model.pagination?.pages.count ?? 1)
        let total = max(1, model.chapters.count)
        let progress = (Double(model.chapterPosition) + Double(model.pageIndex + 1) / Double(count)) / Double(total)
        return ReaderInfoValues(bookName: model.book?.name ?? "", chapterTitle: model.chapterTitle,
                                page: "\(model.pageIndex + 1)", totalPages: "\(count)",
                                readProgress: String(format: "%.1f%%", progress * 100),
                                chapter: "\(model.chapterPosition + 1)", totalChapters: "\(total)")
    }

    var body: some View {
        GeometryReader { geometry in
            let pageSize = CGSize(width: geometry.size.width, height: max(1, geometry.size.height - ReaderInfoView.height(settings: model.settings, header: true) - ReaderInfoView.height(settings: model.settings, header: false)))
            ZStack {
                background.ignoresSafeArea()
                VStack(spacing: 0) {
                    ReaderInfoView(settings: model.settings, header: true, values: infoValues)
                    ReaderPagePresentation(mode: themeColors.palette.pageAnimation(model.settings.pageAnim),
                        page: model.chapterPosition * 1_000_000 + model.pageIndex,
                        progress: autoRead.progress, turn: scrollTurnPage) {
                        pageContent(index: model.pageIndex, size: pageSize)
                    } next: {
                        if let preview = model.nextPagePreview {
                            pageContent(index: preview.index, size: pageSize, preview: preview.pagination, currentChapter: preview.currentChapter)
                        } else if model.chapterPosition + 1 < model.chapters.count {
                            ProgressView("正在加载下一章…").frame(width: pageSize.width, height: pageSize.height)
                        } else {
                            background.frame(width: pageSize.width, height: pageSize.height)
                        }
                    }
                    .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        autoRead.stop()
                        turnPage(value.translation.width < 0)
                    })
                    .onTapGesture(coordinateSpace: .local) { point in
                        autoRead.stop()
                        switch ReaderTouchMap.action(x: point.x, y: point.y, width: pageSize.width, height: pageSize.height) {
                        case .previous: turnPage(false)
                        case .next: turnPage(true)
                        case .menu: showsControls.toggle()
                        default: break
                        }
                    }
                    .onLongPressGesture { autoRead.stop(); showsSelection = true }
                    ReaderInfoView(settings: model.settings, header: false, values: infoValues)
                }
                if model.isLoading { ProgressView("正在加载正文…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                if let error = model.errorMessage {
                    VStack(spacing: 12) {
                        Text(error)
                        Button("重试") {
                            Task { await model.retry() }
                        }
                        Button("返回") { Task { await model.close(); dismiss() } }
                    }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if showsControls { controls }
            }
            .task(id: pageSize) {
                await model.reflow(size: pageSize)
            }
        }
        .foregroundStyle(model.settings.theme == .night ? Color(white: 0.68) : Color.primary)
        .preferredColorScheme(model.settings.theme == .night ? .dark : .light)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .statusBarHidden(model.settings.hideStatusBar && !showsControls)
        .sheet(isPresented: $showsSettings) {
            ReaderInterfacePanel(store: styles, settings: model.settings) { settings in await model.reflow(settings: settings) }
        }
        .alert("阅读样式加载失败", isPresented: Binding(get: { styleError != nil }, set: { if !$0 { styleError = nil } })) {
            Button("好", role: .cancel) { styleError = nil }
        } message: { Text(styleError ?? "") }
        .sheet(isPresented: $showsChapters) { chapterPanel }
        .sheet(isPresented: $showsReadAloud) { ReadAloudPanel(controller: readAloud) }
        .sheet(isPresented: $showsBookmarks) { BookmarkListView(model: model) }
        .sheet(isPresented: $showsSelection) { selectionPanel }
        .sheet(isPresented: $showsHighlights) { highlightsPanel }
        .sheet(isPresented: $showsReviews) { ReaderReviewView(model: model) }
        .task(id: destination) {
            ReaderFonts.registerInstalled()
            UIDevice.current.isBatteryMonitoringEnabled = true
            do {
                try await styles.load()
                var settings = ReaderSettings.load(); settings.isEInk = themeColors.isEInk
                await model.reflow(settings: settings)
            } catch { styleError = error.localizedDescription }
            await model.load(bookURL: destination.bookURL, chapterIndex: destination.chapterIndex)
            await readAloud.attach(model)
            await model.refreshHighlights()
            let monitor = NWPathMonitor()
            networkAvailable = nil
            monitor.pathUpdateHandler = { path in
                let available = path.status == .satisfied
                Task { @MainActor in
                    let restored = networkAvailable == false && available
                    networkAvailable = available
                    if restored { await model.syncWebDavProgress() }
                }
            }
            networkMonitor?.cancel()
            networkMonitor = monitor
            monitor.start(queue: DispatchQueue(label: "Legado.reader.webdav.network"))
        }
        .alert("发现更新的阅读进度", isPresented: Binding(get: { model.pendingWebDavProgress != nil }, set: { if !$0 { model.pendingWebDavProgress = nil } }), presenting: model.pendingWebDavProgress) { progress in
            Button("跳转") {
                Task { await model.acceptWebDavProgress(progress) }
            }
            Button("取消", role: .cancel) { model.pendingWebDavProgress = nil }
        } message: { _ in
            Text("是否跳转到远端的阅读位置？")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { autoRead.stop(); Task { await model.saveProgress() } }
        }
        .onChange(of: model.chapterIndex) { _, chapter in
            Task { await model.refreshHighlights() }
            if readAloud.engine.state != .loading, readAloud.engine.chapterIndex != chapter { readAloud.engine.stop() }
        }
        .onChange(of: model.characterOffset) { _, offset in
            if readAloud.engine.state == .playing || readAloud.engine.state == .paused,
               readAloud.engine.chapterIndex == model.chapterIndex,
               readAloud.engine.characterOffset != offset { readAloud.stop() }
        }
        .onDisappear { networkMonitor?.cancel(); networkMonitor = nil; autoRead.stop(); readAloud.detach(); Task { await model.close() } }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button("返回", systemImage: "chevron.left") { Task { await model.close(); dismiss() } }
                Spacer()
                Text(model.book?.name ?? "阅读器").lineLimit(1)
                Spacer()
                Button("收起", systemImage: "xmark") { showsControls = false }
            }.padding().background(.regularMaterial)
            Spacer()
            VStack {
                HStack {
                    Button("书签") { autoRead.stop(); showsBookmarks = true }
                    Button("批注") { autoRead.stop(); showsHighlights = true }
                    if model.supportsReviews { Button("段评") { autoRead.stop(); showsReviews = true } }
                    Spacer()
                    Button(autoRead.isRunning ? "停止自动阅读" : "自动阅读") {
                        if autoRead.isRunning { autoRead.stop() }
                        else {
                            readAloud.stop(); showsControls = false
                            autoRead.start(speed: model.settings.autoReadSpeed) {
                                let chapter = model.chapterIndex, offset = model.characterOffset
                                await model.nextPage()
                                return chapter != model.chapterIndex || offset != model.characterOffset
                            }
                        }
                    }
                }
                HStack {
                    Button("上一章") { Task { await model.previousChapter() } }
                        .disabled(model.chapterPosition == 0 || model.isLoading)
                    Spacer()
                    Button("目录") { showsChapters = true }
                    Spacer()
                    Button("界面") { showsSettings = true }
                    Button("听书") { showsReadAloud = true }
                    Spacer()
                    Button("下一章") { Task { await model.nextChapter() } }
                        .disabled(model.chapterPosition + 1 >= model.chapters.count || model.isLoading)
                }
                if let pagination = model.pagination, pagination.pages.count > 1 {
                    Slider(value: Binding(get: { Double(model.pageIndex) }, set: { index in
                        Task { await model.selectPage(Int(index)) }
                    }), in: 0...Double(pagination.pages.count - 1), step: 1)
                    .accessibilityLabel("本章阅读进度")
                }
            }.padding().background(.regularMaterial)
        }
    }

    private var chapterPanel: some View {
        NavigationStack {
            List(model.chapters, id: \.index) { chapter in
                Button {
                    showsChapters = false
                    Task { await model.goToChapter(chapter.index) }
                } label: {
                    HStack {
                        Text(chapter.title)
                        if model.cachedChapterIndices.contains(chapter.index) {
                            Image(systemName: "circle.fill").font(.system(size: 5)).accessibilityLabel("已缓存")
                        }
                        if chapter.index == model.chapterIndex { Spacer(); Image(systemName: "checkmark") }
                    }
                }.disabled(model.isLoading)
            }
            .legadoNavigationTitle("目录")
            .safeAreaInset(edge: .bottom) {
                Text("已缓存 \(model.cachedChapterIndices.count) / \(model.chapters.count) 章").font(.caption).padding()
            }
            .task { await model.waitForPrefetch(); await model.refreshCacheStatus() }
            .toolbar { Button("完成") { showsChapters = false } }
        }
    }

    private func turnPage(_ forward: Bool) {
        autoRead.stop()
        Task { if forward { await model.nextPage() } else { await model.previousPage() } }
    }

    private func scrollTurnPage(_ forward: Bool) async -> Bool {
        autoRead.stop()
        let chapter = model.chapterIndex, page = model.pageIndex
        if forward { await model.nextPage() } else { await model.previousPage() }
        return chapter != model.chapterIndex || page != model.pageIndex
    }

    @ViewBuilder private func pageContent(index: Int, size: CGSize, preview: ReaderPagination? = nil, currentChapter: Bool = true) -> some View {
        ZStack(alignment: .topLeading) {
            background
            if let pagination = preview ?? model.pagination, pagination.pages.indices.contains(index) {
                if let imageURL = pagination.pages[index].imageURL {
                    RemoteImage(url: imageURL, origin: model.book?.origin,
                        book: model.book.flatMap { try? DiscoveryStorage.book($0) }, isCover: false)
                        .frame(width: pagination.contentSize.width, height: pagination.contentSize.height)
                        .padding(.leading, model.settings.paddingLeft).padding(.top, model.settings.paddingTop)
                } else {
                    CoreTextReaderPage(pagination: pagination, pageIndex: index, highlight: currentChapter ? model.readAloudRange : nil,
                        annotations: (currentChapter ? model.highlights : []).map { item in
                            let titleLength = pagination.titleLength
                            let start = item.bodyStart(currentTitleLength: titleLength) + titleLength
                            let end = item.bodyEnd(currentTitleLength: titleLength) + titleLength
                            return NSRange(location: start, length: max(0, end - start))
                        })
                        .frame(width: pagination.contentSize.width, height: pagination.contentSize.height)
                        .padding(.leading, model.settings.paddingLeft).padding(.top, model.settings.paddingTop)
                        .accessibilityLabel(pagination.pages[index].text.string)
                        .accessibilityIdentifier("reader.body")
                }
            }
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder private var selectionPanel: some View {
        if let pagination = model.pagination, pagination.pages.indices.contains(model.pageIndex) {
            let page = pagination.pages[model.pageIndex]
            HighlightSelectionView(text: page.text, pageOffset: page.range.location, save: { range, note in
                Task { await model.addHighlight(range: range, note: note) }
            }, readAloud: { range in
                model.followReadAloud(chapter: model.chapterIndex, range: range)
                readAloud.play()
            })
        }
    }

    private var highlightsPanel: some View {
        NavigationStack {
            List(model.highlights, id: \.time) { item in
                VStack(alignment: .leading) {
                    Text(item.bookText)
                    if !item.note.isEmpty { Text(item.note).foregroundStyle(.secondary) }
                }
                .swipeActions { Button("删除", role: .destructive) { Task { await model.deleteHighlight(item) } } }
            }.legadoNavigationTitle("本章高亮与批注")
                .toolbar { Button("完成") { showsHighlights = false } }
        }
    }
}

private struct CoreTextReaderPage: UIViewRepresentable {
    let pagination: ReaderPagination
    let pageIndex: Int
    let highlight: NSRange?
    var annotations: [NSRange] = []

    func makeUIView(context: Context) -> ReaderTextCanvas { ReaderTextCanvas() }

    func updateUIView(_ view: ReaderTextCanvas, context: Context) {
        view.pagination = pagination; view.pageIndex = pageIndex; view.highlight = highlight
        view.annotations = annotations; view.setNeedsDisplay()
    }
}

private final class ReaderTextCanvas: UIView {
    var pagination: ReaderPagination?
    var pageIndex = 0
    var highlight: NSRange?
    var annotations: [NSRange] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let pagination,
              pagination.pages.indices.contains(pageIndex) else { return }
        let page = pagination.pages[pageIndex]
        guard page.frame != nil else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        defer { context.restoreGState() }
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        for highlight in annotations + (highlight.map { [$0] } ?? []) {
            let lines = page.lines
            let origins = page.lineOrigins
            context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.3).cgColor)
            for (index, line) in lines.enumerated() {
                let range = CTLineGetStringRange(line)
                let intersection = NSIntersectionRange(highlight, NSRange(location: range.location, length: range.length))
                guard intersection.length > 0 else { continue }
                var ascent: CGFloat = 0, descent: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                let start = CTLineGetOffsetForStringIndex(line, intersection.location, nil)
                let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(intersection), nil)
                context.fill(CGRect(x: origins[index].x + min(start, end), y: origins[index].y - descent,
                                    width: abs(end - start), height: ascent + descent))
            }
        }
        for (index, line) in page.lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let offset = (attributes[ReaderPunctuation.offsetKey.rawValue] as? NSNumber)?.doubleValue ?? 0
                context.textPosition = CGPoint(x: page.lineOrigins[index].x + offset, y: page.lineOrigins[index].y)
                CTRunDraw(run, context, CFRange(location: 0, length: 0))
            }
        }
    }
}
