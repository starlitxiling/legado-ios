import SwiftUI
import UIKit
import CoreText
import LegadoCore
import Network

@MainActor
struct ReaderView: View {
    let destination: ReaderDestination
    @Environment(AppContainer.self) private var container
    @Environment(\.themeColors) private var themeColors
    @State private var model: ReaderViewModel
    @State private var readAloud: ReadAloudController
    @State private var showsReadAloud = false
    @State private var showsControls = false
    @State private var showsSettings = false
    @State private var behavior = ReaderBehaviorConfiguration()
    @State private var device = ReaderDeviceController()
    @State private var showsBehavior = false
    @State private var actionSheet: ReaderActionSheet?
    @State private var columns = 1
    @State private var customRunning = false
    @State private var selectedParagraph: NSRange?
    @State private var previewImageURL: String?
    @FocusState private var keyboardFocused: Bool
    @State private var styles: ReaderStyleStore
    @State private var styleError: UserFacingError?
    @State private var showsChapters = false
    @State private var showsBookmarks = false
    @State private var showsSelection = false
    @State private var showsHighlights = false
    @State private var showsReviews = false
    @State private var autoRead = AutoReadController()
    @State private var networkMonitor: NWPathMonitor?
    @State private var networkAvailable: Bool?
    @State private var confirmsCloudOverwrite = false
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
        model.autoChangeSource = { ReaderBehaviorConfiguration().boolean("autoChangeSource") }
        model.manualReplace = { UserDefaults.standard.bool(forKey: "manualReplaceRule") }
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
        model.manualWebDav = { book, overwrite in
            guard let dav = try webDavClient() else {
                throw NSError(domain: "ReaderWebDav", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先在备份与恢复中设置 WebDAV。"])
            }
            let sync = BookProgressSync(client: dav, directory: AppPreferences.shared.string("webDavDir"))
            if !overwrite { return try await sync.pull(book) }
            let uploaded = try await sync.upload(book, now: Int64(Date().timeIntervalSince1970 * 1000))
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
            let count = behavior.doublePage(width: geometry.size.width, height: geometry.size.height, tablet: UIDevice.current.userInterfaceIdiom == .pad) ? 2 : 1
            let pageSize = CGSize(width: geometry.size.width / Double(count), height: max(1, geometry.size.height - ReaderInfoView.height(settings: model.settings, header: true) - ReaderInfoView.height(settings: model.settings, header: false)))
            ZStack {
                background.ignoresSafeArea()
                VStack(spacing: 0) {
                    ReaderInfoView(settings: model.settings, header: true, values: infoValues)
                    ReaderPagePresentation(mode: animation,
                        page: model.chapterPosition * 1_000_000 + model.pageIndex,
                        progress: autoRead.progress, enabled: acceptsInput,
                        canPrevious: model.pageIndex > 0 || model.chapterPosition > 0,
                        canNext: model.pageIndex + count < (model.pagination?.pages.count ?? 0) || model.chapterPosition + 1 < model.availableChapterCount,
                        forward: model.lastTurnForward, touchSlop: Double(behavior.integer("pageTouchSlop")), pageHeight: spreadHeight(index: model.pageIndex, size: pageSize, count: count),
                        scrollPages: animation == 3 ? continuousPages(size: pageSize, count: count) : [], scrollSelect: selectScrollPage, turn: scrollTurnPage) {
                        pageSpread(index: model.pageIndex, size: pageSize, count: count)
                    } next: {
                        if let pagination = model.pagination, model.pageIndex + count < pagination.pages.count {
                            pageSpread(index: model.pageIndex + count, size: pageSize, count: count)
                        } else if let pagination = model.nextChapterPagination {
                            pageSpread(index: 0, size: pageSize, count: count, preview: pagination, currentChapter: false)
                        } else { background.frame(width: geometry.size.width, height: pageSize.height) }
                    } previous: {
                        if model.pageIndex >= count {
                            pageSpread(index: model.pageIndex - count, size: pageSize, count: count)
                        } else if let pagination = model.previousChapterPagination {
                            pageSpread(index: max(0, (pagination.pages.count - 1) / count * count), size: pageSize,
                                       count: count, preview: pagination, currentChapter: false)
                        } else { background.frame(width: geometry.size.width, height: pageSize.height) }
                    }
                    .frame(width: geometry.size.width, height: pageSize.height, alignment: .topLeading)
                    .background {
                        ReaderInputView(configuration: behavior, enabled: acceptsInput, scrollMode: animation == 3, interactivePaging: (0...2).contains(animation),
                            tap: { point, taps in tapped(point, taps: taps, size: CGSize(width: geometry.size.width, height: pageSize.height)) },
                            longPress: { point in held(point, size: CGSize(width: geometry.size.width, height: pageSize.height)) },
                            turn: turnPage, bookmark: { Task { await model.toggleBookmark() } },
                            preview: { showPanel("preview") })
                    }

                    ReaderInfoView(settings: model.settings, header: false, values: infoValues)
                }
                if model.isLoading {
                    ProgressView("正在加载正文…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        if let message = model.recoveringMessage {
                            HStack {
                                ProgressView(); Text(message)
                                Button("停止") { model.cancelSourceRecovery() }
                            }.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(.bottom, 24).padding(.horizontal, 12)
                }
                if showsControls { controls }
            }
            .errorBanner(model.isLoading || showsControls ? nil : model.userError, dismiss: model.dismissError) { action in
                switch action {
                case .retry: Task { await model.retry() }
                case .changeSource: model.cancelSourceRecovery(); showPanel("source")
                case .manageSources: model.cancelSourceRecovery(); showPanel("sources")
                case .openSettings: showsBehavior = true
                case .back: leaveReader()
                }
            }
            .task(id: pageSize) {
                columns = count
                await model.reflow(size: pageSize)
            }
        }
        .ignoresSafeArea(.container, edges: readingEdges)
        .focusable().focused($keyboardFocused)
        .onKeyPress(phases: [.down, .repeat]) { press in
            guard acceptsInput, press.phase != .repeat || behavior.boolean("keyPageOnLongPress") else { return .ignored }
            if press.key == .escape {
                guard !behavior.boolean("disableReturnKey") else { return .handled }
                leaveReader(); return .handled
            }
            guard let code = ReaderKeyboard.androidCode(character: String(press.key.character)),
                  let forward = ReaderKeyboard.forward(code: code, previous: UserDefaults.standard.string(forKey: "prevKeys") ?? "", next: UserDefaults.standard.string(forKey: "nextKeys") ?? "") else { return .ignored }
            turnPage(forward); return .handled
        }
        .persistentSystemOverlays(behavior.boolean("hideNavigationBar") && !showsControls ? .hidden : .automatic)
        .background(ReaderNavigationGuard(disabled: behavior.boolean("disableReturnKey")))
        .sheet(isPresented: $showsBehavior) { ReaderBehaviorPanel(configuration: $behavior) }
        .sheet(item: $actionSheet) { destination in actionPanel(destination.key) }
        .onChange(of: behavior) { _, value in device.update(value); Task { await model.applyBehavior(value) } }
        .foregroundStyle(model.settings.theme == .night ? Color(white: 0.68) : Color.primary)
        .preferredColorScheme(model.settings.theme == .night ? .dark : .light)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .statusBarHidden(model.settings.hideStatusBar && !showsControls)
        .sheet(isPresented: $showsSettings) {
            ReaderInterfacePanel(store: styles, settings: model.settings) { settings in await model.reflow(settings: settings) }
        }
        .alert(styleError?.title ?? "阅读操作失败", isPresented: Binding(get: { styleError != nil }, set: { if !$0 { styleError = nil } })) {
            Button("好", role: .cancel) { styleError = nil }
        } message: { Text(styleError?.message ?? "") }
        .fullScreenCover(isPresented: $showsChapters) { ReaderTocView(model: model, database: container.database) }
        .sheet(isPresented: $showsReadAloud) { ReadAloudPanel(controller: readAloud) }
        .sheet(isPresented: $showsBookmarks) { BookmarkListView(model: model) }
        .sheet(isPresented: $showsSelection) { selectionPanel }
        .sheet(isPresented: $showsHighlights) { highlightsPanel }
        .sheet(isPresented: $showsReviews) { ReaderReviewView(model: model) }
        .task(id: destination) {
            ReaderFonts.registerInstalled()
            device.begin(behavior); keyboardFocused = true
            UIDevice.current.isBatteryMonitoringEnabled = true
            do {
                try await styles.load()
            } catch { AppLogStore.shared.append("Reader style loading: \(String(reflecting: error))") }
            var settings = ReaderSettings.load(); settings.isEInk = themeColors.isEInk
            await model.reflow(settings: settings)
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
        .confirmationDialog("用当前阅读位置覆盖云端进度？", isPresented: $confirmsCloudOverwrite) {
            Button("覆盖云端进度", role: .destructive) { Task { await model.requestCloudProgress(overwrite: true) } }
        }
        .alert("云端阅读进度", isPresented: Binding(get: { model.pendingWebDavProgress != nil }, set: { if !$0 { model.pendingWebDavProgress = nil } }), presenting: model.pendingWebDavProgress) { progress in
            Button("跳转") {
                Task { await model.acceptWebDavProgress(progress) }
            }
            Button("取消", role: .cancel) { model.pendingWebDavProgress = nil }
        } message: { _ in
            Text("是否跳转到远端的阅读位置？")
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("Legado.script.refresh"))) { notification in
            if let event = notification.object as? String { Task { await model.refreshFromScript(event) } }
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
        .onDisappear { guard !showsChapters else { return }; device.end(); networkMonitor?.cancel(); networkMonitor = nil; autoRead.stop(); readAloud.detach(); Task { await model.close() } }
    }

    private var animation: Int {
        let value = themeColors.palette.pageAnimation(model.readerBook?.readConfig?.pageAnim ?? model.settings.pageAnim, eInkMode: model.settings.configuration.pageAnimEInk)
        return !themeColors.isEInk && value == 4 && behavior.boolean("noAnimScrollPage") ? 3 : value
    }
    private var acceptsInput: Bool {
        !showsControls && !showsSettings && !showsBehavior && !showsChapters && !showsReadAloud && !showsBookmarks && !showsSelection && !showsHighlights && !showsReviews && actionSheet == nil && model.acceptsInput && scenePhase == .active
    }
    private func leaveReader() {
        model.cancelSourceRecovery()
        dismiss()
        Task { await model.close() }
    }

    private var readingEdges: Edge.Set {
        if behavior.boolean("paddingDisplayCutouts") { return [] }
        var edges: Edge.Set = []
        if model.settings.hideStatusBar && behavior.boolean("readBodyToLh") { edges.insert(.top) }
        if behavior.boolean("hideNavigationBar") { edges.insert(.bottom) }
        return edges
    }
    private var controls: some View {
        ReaderMenuView(model: model, configuration: behavior, device: device, automatic: autoRead.isRunning,
                       close: { showsControls = false }, leave: leaveReader,
                       action: perform, show: showPanel, autoRead: toggleAutoRead, night: toggleNight)
            .transition(themeColors.isEInk ? .identity : .opacity)
    }
    private func perform(_ action: ReaderTapAction) {
        device.interaction(); autoRead.stop()
        switch action {
        case .noAction: break
        case .menu: withAnimation(themeColors.isEInk ? nil : .easeInOut(duration: 0.15)) { showsControls.toggle() }
        case .next: turnPage(true)
        case .previous: turnPage(false)
        case .nextChapter: Task { await model.nextChapter() }
        case .previousChapter: Task { await model.previousChapter() }
        case .previousParagraph: readAloud.previousParagraph()
        case .nextParagraph: readAloud.nextParagraph()
        case .bookmark: Task { await model.addBookmark() }
        case .editContent: showPanel("editContent")
        case .toggleReplace:
            let enabled = !(model.readerBook?.useReplaceRule(defaultEnabled: model.replaceEnableDefault()) ?? true)
            Task { await model.updateReadConfig { $0.useReplaceRule = enabled } }
        case .toc: showsControls = false; showsChapters = true
        case .search: showPanel("search")
        case .sync: Task { await model.requestCloudProgress(overwrite: false) }
        case .readAloud: readAloud.toggle()
        }
    }
    private func touchedPosition(_ point: CGPoint, size: CGSize) -> (page: Int, offset: Int?) {
        let width = size.width / Double(columns)
        let column = min(columns - 1, max(0, Int(point.x / max(1, width))))
        let page = model.pageIndex + column
        let local = CGPoint(x: point.x - Double(column) * width - model.settings.paddingLeft, y: point.y - model.settings.paddingTop)
        return (page, model.pagination?.characterOffset(at: local, on: page))
    }
    private func opensHighlight(_ offset: Int?) -> Bool {
        guard let offset, let pagination = model.pagination else { return false }
        return model.highlights.contains { item in
            let start = item.bodyStart(currentTitleLength: pagination.titleLength) + pagination.titleLength
            let end = item.bodyEnd(currentTitleLength: pagination.titleLength) + pagination.titleLength
            return offset >= start && offset < end
        }
    }
    private func held(_ point: CGPoint, size: CGSize) {
        let position = touchedPosition(point, size: size)
        autoRead.stop(); device.interaction()
        if behavior.string("highlightActionTrigger") == "longPress", opensHighlight(position.offset) { showsHighlights = true; return }
        guard behavior.boolean("selectText") else { return }
        selectedParagraph = nil
        if behavior.boolean("longPressSelectParagraph"), let offset = position.offset, let pagination = model.pagination, offset < pagination.text.length {
            selectedParagraph = (pagination.text.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        }
        showsSelection = true
    }
    private func tapped(_ point: CGPoint, taps: Int, size: CGSize) {
        device.interaction()
        let position = touchedPosition(point, size: size)
        let trigger = behavior.string("highlightActionTrigger")
        if (trigger == "click" && taps == 1 || trigger == "doubleTap" && taps == 2), opensHighlight(position.offset) { showsHighlights = true; return }
        if let pagination = model.pagination, pagination.pages.indices.contains(position.page),
           let image = pagination.pages[position.page].images.first(where: { $0.offset == position.offset }) {
            do {
                switch try ReaderImageAction.resolve(image, mode: behavior.string("clickImgWay"), taps: taps,
                    onlineText: model.readerBook?.isOnLineTxt == true) {
                case .none: break
                case .consume: return
                case .preview: previewImageURL = image.url; showPanel("image"); return
                case .script(let code, let result): runImageScript(code, result: result); return
                }
            } catch { styleError = error.presentation(operation: "处理图片点击", subject: model.book?.name); return }
        }
        guard taps == 1, let action = ReaderTouchMap.action(x: point.x, y: point.y, width: size.width, height: size.height, actions: ReaderTouchMap.load()) else { return }
        perform(action)
    }
    private func showPanel(_ key: String) {
        autoRead.stop()
        switch key {
        case "interface": showsSettings = true
        case "settings": showsBehavior = true
        case "aloud": showsReadAloud = true
        case "bookmarks": showsBookmarks = true
        case "highlights": showsHighlights = true
        case "reviews": showsReviews = true
        case "custom": customButton()
        case "coverProgress": confirmsCloudOverwrite = true
        default: actionSheet = ReaderActionSheet(key: key)
        }
    }
    @ViewBuilder private func actionPanel(_ key: String) -> some View {
        switch key {
        case "search": ReaderSearchView(model: model)
        case "editContent": ReaderContentEditor(model: model)
        case "replace": NavigationStack { ReplaceRulesView(repository: container.replaceRules, httpClient: container.httpClient) }
        case "cache": if let book = model.book { NavigationStack { BookCacheExportView(book: book, model: container.downloads) } }
        case "sources":
            NavigationStack {
                SourcesView(repository: container.bookSources, replaceRules: container.replaceRules,
                    httpClient: container.httpClient, sourceLogin: container.sourceLogin, sourceChecker: container.sourceChecker)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { actionSheet = nil } } }
            }
        case "source":
            NavigationStack {
                BookSourceSwitchView(book: model.readerBook, initial: [], container: container) { result in
                    let detail = BookDetailViewModel(results: [result], sources: container.bookSources, bookshelf: container.bookshelf, client: container.httpClient)
                    await detail.load()
                    if let book = await detail.prepareForReading(database: container.database), let url = book.bookUrl {
                        actionSheet = nil; await model.load(bookURL: url); await readAloud.attach(model)
                    } else { styleError = detail.errorMessage.map { UserFacingError(title: "切换书源失败", message: $0) } }
                }
            }
        case "log": NavigationStack { AppLogView() }
        case "image": if let url = previewImageURL { ReaderImagePreview(url: url, model: model) }
        case "preview": ReaderReplacePreviewView(model: model)
        case "memo": if let book = model.book { ReaderMemoView(bookURL: book.bookUrl, database: container.database) }
        case "reimportSource":
            if let sourceURL = model.book?.origin {
                ReaderSourceReimportView(sourceURL: sourceURL, repository: container.bookSources, client: container.httpClient) { await model.reloadSource() }
            }
        case "highlightRule": ReaderHighlightRulesView(repository: HighlightRuleRepository(database: container.database)) { await model.reflow() }
        case "effectiveReplaces": ReaderManualReplaceView(model: model, repository: container.replaceRules)
        case "simulatedReading": ReaderSimulatedView(model: model)
        case "updateToc", "charset": ReaderTextParsingView(model: model, database: container.database)
        case "autoSpeed":
            NavigationStack {
                Form {
                    LabeledContent("每页秒数", value: "\(Int(model.settings.autoReadSpeed))")
                    Slider(value: Binding(get: { model.settings.autoReadSpeed }, set: { value in
                        var settings = model.settings; settings.autoReadSpeed = value; settings.save()
                        Task { await model.reflow(settings: settings) }
                    }), in: 1...120, step: 1)
                }.legadoNavigationTitle("自动阅读速度")
            }
        default:
            NavigationStack {
                ScrollView { Text("点击中央区域打开阅读菜单。左右滑动翻页，长按正文选择文本。可在设置中自定义九宫格、外接键盘按键、双页显示和菜单。") .padding() }
                    .legadoNavigationTitle("阅读帮助")
            }
        }
    }
    private func runImageScript(_ script: String, result: String) {
        guard let source = model.readerSource, let book = model.readerBook else { return }
        let chapter = model.readerChapter, client = container.httpClient
        Task {
            do { _ = try await Task.detached { try SourceCallback.imageClick(script: script, src: result, source: source, book: book, chapter: chapter, client: client) }.value }
            catch { styleError = error.presentation(operation: "执行图片脚本", subject: book.name) }
        }
    }
    private func customButton() {
        guard !customRunning, let source = model.readerSource, let book = model.readerBook else { return }
        customRunning = true
        let client = container.httpClient, chapter = model.readerChapter
        Task {
            defer { customRunning = false }
            do { _ = try await Task.detached { try SourceCallback.run(source: source, book: book, chapter: chapter, event: "clickCustomButton", client: client) }.value }
            catch { styleError = error.presentation(operation: "执行书源自定义按钮", subject: source.bookSourceName) }
        }
    }
    private func toggleNight() {
        var settings = model.settings; settings.theme = settings.theme == .night ? .day : .night; settings.save()
        Task { await model.reflow(settings: settings) }
    }
    private func toggleAutoRead() {
        if autoRead.isRunning { autoRead.stop(); return }
        readAloud.stop(); showsControls = false
        autoRead.start(speed: model.settings.autoReadSpeed) {
            let chapter = model.chapterIndex, offset = model.characterOffset
            await model.advanceSpread(forward: true, columns: columns)
            return chapter != model.chapterIndex || offset != model.characterOffset
        }
    }
    private func spreadHeight(index: Int, size: CGSize, count: Int, preview: ReaderPagination? = nil) -> Double {
        guard animation == 3, let pagination = preview ?? model.pagination else { return size.height }
        return (index..<index + count).filter { pagination.pages.indices.contains($0) }.map {
            max(size.height, pagination.pages[$0].height + model.settings.paddingTop + model.settings.paddingBottom)
        }.max() ?? size.height
    }
    private func pageSpread(index: Int, size: CGSize, count: Int, preview: ReaderPagination? = nil, currentChapter: Bool = true, chapterPosition: Int? = nil) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<count, id: \.self) { column in
                pageContent(index: index + column, size: size, preview: preview, currentChapter: currentChapter, chapterPosition: chapterPosition)
            }
        }
    }

    private func continuousPages(size: CGSize, count: Int) -> [ReaderScrollPage] {
        var result: [ReaderScrollPage] = []
        let position = model.chapterPosition
        let chapters: [(Int, ReaderPagination?)] = [(position - 1, model.previousChapterPagination),
            (position, model.pagination), (position + 1, model.nextChapterPagination)]
        for (chapter, pagination) in chapters where chapter >= 0 && chapter < model.availableChapterCount {
            if let pagination {
                for index in stride(from: 0, to: pagination.pages.count, by: count) {
                    result.append(ReaderScrollPage(id: chapter * 1_000_000 + index,
                        height: spreadHeight(index: index, size: size, count: count, preview: pagination),
                        content: AnyView(pageSpread(index: index, size: size, count: count, preview: pagination,
                            currentChapter: chapter == position, chapterPosition: chapter))))
                }
            } else if chapter != position {
                result.append(ReaderScrollPage(id: chapter * 1_000_000, height: size.height,
                    content: AnyView(background.overlay(Text(chapter > position ? "继续滚动加载下一章" : "继续滚动加载上一章")))))
            }
        }
        return result
    }

    private func selectScrollPage(_ location: Int) async {
        let chapter = location / 1_000_000, page = location % 1_000_000
        guard chapter >= 0, chapter < model.availableChapterCount else { return }
        if chapter != model.chapterPosition {
            await model.goToChapter(model.chapters[chapter].index)
        }
        guard chapter == model.chapterPosition else { return }
        await model.selectPage(page)
    }

    private func turnPage(_ forward: Bool) {
        autoRead.stop()
        device.interaction()
        Task { await model.advanceSpread(forward: forward, columns: columns) }
    }

    private func scrollTurnPage(_ forward: Bool) async -> Bool {
        autoRead.stop()
        let chapter = model.chapterIndex, page = model.pageIndex
        await model.advanceSpread(forward: forward, columns: columns)
        return chapter != model.chapterIndex || page != model.pageIndex
    }

    @ViewBuilder private func pageContent(index: Int, size: CGSize, preview: ReaderPagination? = nil, currentChapter: Bool = true, chapterPosition: Int? = nil) -> some View {
        ZStack(alignment: .topLeading) {
            background
            if let pagination = preview ?? model.pagination, pagination.pages.indices.contains(index) {
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
                    .accessibilityValue("第 \((chapterPosition ?? model.chapterPosition) + 1) 章，第 \(index + 1) 页")
                ForEach(Array(pagination.pages[index].images.enumerated()), id: \.offset) { _, image in
                    RemoteImage(url: image.url, origin: model.book?.origin, book: model.readerBook, isCover: false)
                        .frame(width: image.rect.width, height: image.rect.height)
                        .offset(x: model.settings.paddingLeft + image.rect.minX, y: model.settings.paddingTop + image.rect.minY)
                        .allowsHitTesting(false)
                }
            }
        }.frame(width: size.width, height: spreadHeight(index: index, size: size, count: 1, preview: preview), alignment: .topLeading)
    }

    @ViewBuilder private var selectionPanel: some View {
        if let pagination = model.pagination, pagination.pages.indices.contains(model.pageIndex) {
            let page = pagination.pages[model.pageIndex]
            let range = selectedParagraph.map { NSIntersectionRange($0, NSRange(location: 0, length: pagination.text.length)) } ?? page.range
            HighlightSelectionView(text: pagination.text.attributedSubstring(from: range), pageOffset: range.location,
                initialSelection: selectedParagraph == nil ? nil : NSRange(location: 0, length: range.length), model: model, container: container, save: { range, note in
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
        view.annotations = annotations
        view.layer.shouldRasterize = UserDefaults.standard.bool(forKey: "optimizeRender")
        view.layer.rasterizationScale = view.window?.screen.scale ?? 2
        view.setNeedsDisplay()
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
        for (index, line) in page.lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let style = attributes[ReaderRuleHighlight.styleKey.rawValue] as? HighlightStyle else { continue }
                let foreground = attributes[kCTForegroundColorAttributeName] as! CGColor
                ReaderRuleHighlight.draw(style, in: highlightRect(run: run, line: line, origin: page.lineOrigins[index]),
                    baseline: page.lineOrigins[index].y, foreground: foreground, context: context, background: true)
            }
        }
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
                context.saveGState()
                let style = attributes[ReaderRuleHighlight.styleKey.rawValue] as? HighlightStyle
                if let shadow = style?.shadow {
                    context.setShadow(offset: CGSize(width: shadow.dx, height: -shadow.dy), blur: shadow.radius, color: ReaderRuleHighlight.color(shadow.color))
                }
                CTRunDraw(run, context, CFRange(location: 0, length: 0))
                context.restoreGState()
                if let style {
                    let foreground = attributes[kCTForegroundColorAttributeName] as! CGColor
                    ReaderRuleHighlight.draw(style, in: highlightRect(run: run, line: line, origin: page.lineOrigins[index]),
                        baseline: page.lineOrigins[index].y, foreground: foreground, context: context, background: false)
                    if let emphasis = style.emphasis {
                        context.setFillColor(emphasis.color == 0 ? foreground : ReaderRuleHighlight.color(emphasis.color))
                        let count = CTRunGetGlyphCount(run)
                        var positions = [CGPoint](repeating: .zero, count: count)
                        var advances = [CGSize](repeating: .zero, count: count)
                        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                        CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                        let top = highlightRect(run: run, line: line, origin: page.lineOrigins[index]).maxY
                        for glyph in 0..<count {
                            context.fillEllipse(in: CGRect(x: page.lineOrigins[index].x + positions[glyph].x + advances[glyph].width / 2 - 1.5,
                                y: top + 1, width: 3, height: 3))
                        }
                    }
                }
            }
        }
    }
    private func highlightRect(run: CTRun, line: CTLine, origin: CGPoint) -> CGRect {
        let range = CTRunGetStringRange(run)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        _ = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil)
        let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
        let end = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
        return CGRect(x: origin.x + min(start, end), y: origin.y - descent, width: abs(end - start), height: ascent + descent)
    }
}

private struct ReaderActionSheet: Identifiable {
    let key: String
    var id: String { key }
}

private struct ReaderImagePreview: View {
    let url: String
    let model: ReaderViewModel
    @State private var scale: CGFloat = 1
    var body: some View {
        NavigationStack {
            RemoteImage(url: url, origin: model.book?.origin, book: model.readerBook, isCover: false)
                .scaleEffect(scale).gesture(MagnifyGesture().onChanged { scale = max(1, min(5, $0.magnification)) })
                .onTapGesture(count: 2) { scale = scale == 1 ? 2 : 1 }
                .legadoNavigationTitle("图片预览")
        }
    }
}
