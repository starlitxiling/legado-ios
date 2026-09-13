import SwiftUI
import UIKit
import CoreText
import LegadoCore

struct ReaderView: View {
    let destination: ReaderDestination
    @State private var model: ReaderViewModel
    @State private var readAloud: ReadAloudController
    @State private var showsReadAloud = false
    @State private var showsControls = false
    @State private var showsSettings = false
    @State private var showsChapters = false
    @State private var showsBookmarks = false
    @State private var showsSelection = false
    @State private var showsHighlights = false
    @State private var showsReviews = false
    @State private var autoRead = AutoReadController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(destination: ReaderDestination, database: AppDatabase, client: any HttpClient,
         cacheDirectory: URL? = nil) {
        self.destination = destination
        let directory = cacheDirectory ?? URL.applicationSupportDirectory
            .appendingPathComponent("Legado/ReaderCache", isDirectory: true)
        _model = State(initialValue: ReaderViewModel(database: database, client: client,
            cacheDirectory: directory, settings: ReaderSettings.load()))
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

    private var background: Color {
        switch model.settings.theme {
        case .day: return Color(white: 238 / 255)
        case .night: return .black
        case .eyeCare: return Color(red: 0.8, green: 0.91, blue: 0.81)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let pageSize = CGSize(width: geometry.size.width, height: max(1, geometry.size.height - 28))
            ZStack {
                background.ignoresSafeArea()
                VStack(spacing: 0) {
                    ReaderPagePresentation(mode: model.settings.pageAnim,
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
                        case nil: break
                        }
                    }
                    .onLongPressGesture { autoRead.stop(); showsSelection = true }
                    HStack {
                        Text(model.chapterTitle).lineLimit(1)
                        Spacer()
                        Text("\(model.pageIndex + 1) / \(model.pagination?.pages.count ?? 0)")
                    }
                    .font(.caption).padding(.horizontal, 16).frame(height: 28)
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
        .sheet(isPresented: $showsSettings) { settingsPanel }
        .sheet(isPresented: $showsChapters) { chapterPanel }
        .sheet(isPresented: $showsReadAloud) { ReadAloudPanel(controller: readAloud) }
        .sheet(isPresented: $showsBookmarks) { BookmarkListView(model: model) }
        .sheet(isPresented: $showsSelection) { selectionPanel }
        .sheet(isPresented: $showsHighlights) { highlightsPanel }
        .sheet(isPresented: $showsReviews) { ReaderReviewView(model: model) }
        .task(id: destination) {
            ReaderFonts.registerInstalled()
            await model.load(bookURL: destination.bookURL, chapterIndex: destination.chapterIndex)
            await readAloud.attach(model)
            await model.refreshHighlights()
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
        .onDisappear { autoRead.stop(); readAloud.detach(); Task { await model.close() } }
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
                    Button("设置") { showsSettings = true }
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

    private func setting(_ keyPath: WritableKeyPath<ReaderSettings, Double>) -> Binding<Double> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in
            var settings = model.settings; settings[keyPath: keyPath] = value
            settings.save()
            Task { await model.reflow(settings: settings) }
        })
    }

    private var settingsPanel: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    Picker("对齐", selection: integerSetting(\.titleMode)) {
                        Text("左对齐").tag(0); Text("居中").tag(1); Text("隐藏").tag(2); Text("右对齐").tag(3)
                    }
                    Slider(value: Binding(get: { (model.settings.textSize + model.settings.titleSize) / model.settings.textSize },
                        set: { setting(\.titleSize).wrappedValue = model.settings.textSize * ($0 - 1) }), in: 0.8...2, step: 0.1)
                        .accessibilityLabel("标题字号倍数")
                    LabeledContent("上边距") { Slider(value: setting(\.titleTopSpacing), in: 0...80, step: 1) }
                    LabeledContent("下边距") { Slider(value: setting(\.titleBottomSpacing), in: 0...80, step: 1) }
                }
                NavigationLink("字体") {
                    FontPicker(selection: Binding(get: { model.settings.textFont }, set: { font in
                        var settings = model.settings; settings.textFont = font; settings.save()
                        Task { await model.reflow(settings: settings) }
                    }))
                }
                Picker("翻页动画", selection: integerSetting(\.pageAnim)) {
                    Text("覆盖").tag(0); Text("滑动").tag(1); Text("仿真").tag(2); Text("滚动").tag(3); Text("无动画").tag(4)
                }
                Section("自动阅读：每屏 \(Int(model.settings.autoReadSpeed)) 秒") {
                    Slider(value: setting(\.autoReadSpeed), in: 1...120, step: 1)
                }
                Section("字号：\(Int(model.settings.textSize))") {
                    Slider(value: setting(\.textSize), in: 12...48, step: 1)
                }
                Section("行距：\(model.settings.lineSpacingMultiplier, specifier: "%.1f") 倍") {
                    Slider(value: setting(\.lineSpacingMultiplier), in: 1...3, step: 0.1)
                }
                Picker("主题", selection: Binding(get: { model.settings.theme }, set: { theme in
                    var settings = model.settings; settings.theme = theme; settings.save()
                    Task { await model.reflow(settings: settings) }
                })) {
                    Text("日间").tag(ReaderTheme.day)
                    Text("夜间").tag(ReaderTheme.night)
                    Text("护眼").tag(ReaderTheme.eyeCare)
                }
            }
            .navigationTitle("阅读设置")
            .toolbar { Button("完成") { showsSettings = false } }
        }.presentationDetents([.large])
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
            .navigationTitle("目录")
            .safeAreaInset(edge: .bottom) {
                Text("已缓存 \(model.cachedChapterIndices.count) / \(model.chapters.count) 章").font(.caption).padding()
            }
            .task { await model.waitForPrefetch(); await model.refreshCacheStatus() }
            .toolbar { Button("完成") { showsChapters = false } }
        }
    }

    private func integerSetting(_ keyPath: WritableKeyPath<ReaderSettings, Int>) -> Binding<Int> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { value in
            autoRead.stop()
            var settings = model.settings; settings[keyPath: keyPath] = value; settings.save()
            Task { await model.reflow(settings: settings) }
        })
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
                            let titleLength = model.settings.titleMode == 2 ? 0 : (model.chapterTitle as NSString).length + 1
                            let start = item.bodyStart(currentTitleLength: titleLength) + titleLength
                            let end = item.bodyEnd(currentTitleLength: titleLength) + titleLength
                            return NSRange(location: start, length: max(0, end - start))
                        })
                        .frame(width: pagination.contentSize.width, height: pagination.contentSize.height)
                        .padding(.leading, model.settings.paddingLeft).padding(.top, model.settings.paddingTop)
                        .accessibilityLabel(pagination.pages[index].text.string)
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
            }.navigationTitle("本章高亮与批注")
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
        guard let frame = page.frame else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        for highlight in annotations + (highlight.map { [$0] } ?? []) {
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
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
        CTFrameDraw(frame, context)
    }
}
