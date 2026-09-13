import SwiftUI
import UIKit
import CoreText
import LegadoCore

struct ReaderView: View {
    let destination: ReaderDestination
    @State private var model: ReaderViewModel
    @State private var showsControls = false
    @State private var showsSettings = false
    @State private var showsChapters = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(destination: ReaderDestination, database: AppDatabase, client: any HttpClient,
         cacheDirectory: URL? = nil) {
        self.destination = destination
        let directory = cacheDirectory ?? URL.applicationSupportDirectory
            .appendingPathComponent("Legado/ReaderCache", isDirectory: true)
        _model = State(initialValue: ReaderViewModel(database: database, client: client,
            cacheDirectory: directory, settings: ReaderSettings.load()))
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
                    ZStack(alignment: .topLeading) {
                        if let pagination = model.pagination, pagination.pages.indices.contains(model.pageIndex) {
                            CoreTextReaderPage(pagination: pagination, pageIndex: model.pageIndex)
                                .frame(width: pagination.contentSize.width, height: pagination.contentSize.height)
                                .padding(.leading, model.settings.paddingLeft)
                                .padding(.top, model.settings.paddingTop)
                                .accessibilityLabel(pagination.pages[model.pageIndex].text.string)
                        }
                    }
                    .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        Task {
                            if value.translation.width < 0 { await model.nextPage() }
                            else { await model.previousPage() }
                        }
                    })
                    .onTapGesture(coordinateSpace: .local) { point in
                        if point.x < pageSize.width / 3 { Task { await model.previousPage() } }
                        else if point.x > pageSize.width * 2 / 3 { Task { await model.nextPage() } }
                        else { showsControls.toggle() }
                    }
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
        .statusBarHidden(!showsControls)
        .sheet(isPresented: $showsSettings) { settingsPanel }
        .sheet(isPresented: $showsChapters) { chapterPanel }
        .task(id: destination) {
            await model.load(bookURL: destination.bookURL, chapterIndex: destination.chapterIndex)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.saveProgress() } }
        }
        .onDisappear { Task { await model.close() } }
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
                    Button("上一章") { Task { await model.previousChapter() } }
                        .disabled(model.chapterPosition == 0 || model.isLoading)
                    Spacer()
                    Button("目录") { showsChapters = true }
                    Spacer()
                    Button("设置") { showsSettings = true }
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
        }.presentationDetents([.medium])
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
                        if chapter.index == model.chapterIndex { Spacer(); Image(systemName: "checkmark") }
                    }
                }.disabled(model.isLoading)
            }
            .navigationTitle("目录")
            .toolbar { Button("完成") { showsChapters = false } }
        }
    }
}

private struct CoreTextReaderPage: UIViewRepresentable {
    let pagination: ReaderPagination
    let pageIndex: Int

    func makeUIView(context: Context) -> ReaderTextCanvas { ReaderTextCanvas() }

    func updateUIView(_ view: ReaderTextCanvas, context: Context) {
        view.pagination = pagination; view.pageIndex = pageIndex; view.setNeedsDisplay()
    }
}

private final class ReaderTextCanvas: UIView {
    var pagination: ReaderPagination?
    var pageIndex = 0

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
        CTFrameDraw(frame, context)
    }
}
