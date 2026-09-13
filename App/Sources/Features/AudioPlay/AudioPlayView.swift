import SwiftUI
import LegadoCore

struct AudioPlayView: View {
    @Environment(AppContainer.self) private var container
    @State private var library: MediaBookLibrary

    init(book: Book, database: AppDatabase, client: any HttpClient) {
        _library = State(initialValue: MediaBookLibrary(book: book, database: database, client: client))
    }

    var body: some View {
        VStack(spacing: 24) {
            if library.isLoading { ProgressView("正在加载音频目录") }
            if let error = library.errorMessage {
                Text(error).foregroundStyle(.red)
                Button("重试") { Task { await load() } }
            }
            if let engine = container.audioPlayback.engine,
               container.audioPlayback.library?.book.bookUrl == library.book.bookUrl {
                Text(library.book.name ?? "音频").font(.title2)
                if library.chapters.indices.contains(engine.chapter) {
                    Text(library.chapters[engine.chapter].title ?? "")
                }
                if engine.state == .loading { ProgressView("正在加载音频") }
                if let error = engine.errorMessage { Text(error).foregroundStyle(.red) }
                Slider(value: Binding(get: { Double(engine.position) }, set: { engine.seek(to: Int($0)) }),
                       in: 0...Double(max(1, engine.duration)))
                    .disabled(engine.duration <= 0)
                Text("\(time(engine.position)) / \(time(engine.duration))").monospacedDigit()
                HStack(spacing: 24) {
                    Button("上一章", systemImage: "backward.end") { engine.previous() }.disabled(engine.chapter <= 0)
                    Button(engine.state == .playing || engine.state == .loading ? "暂停" : "播放",
                           systemImage: engine.state == .playing || engine.state == .loading ? "pause.fill" : "play.fill") {
                        if engine.state == .playing || engine.state == .loading { engine.pause() } else { engine.play() }
                    }
                    Button("下一章", systemImage: "forward.end") { engine.next() }
                        .disabled(engine.chapter + 1 >= engine.chapterCount)
                }
                Button("停止") { engine.stop() }
                Menu(engine.timerDeadline == nil ? "定时停止" : "定时已开启") {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button("\(minutes) 分钟后停止") { engine.setTimer(seconds: Double(minutes * 60)) }
                    }
                    Button("取消定时") { engine.setTimer(seconds: nil) }
                }
                Picker("章节", selection: Binding(get: { engine.chapter }, set: { engine.select($0) })) {
                    ForEach(library.chapters.indices, id: \.self) { index in
                        Text(library.chapters[index].title ?? "第 \(index + 1) 章").tag(index)
                    }
                }
            }
            Spacer()
        }
        .padding().navigationTitle("音频播放")
        .task { await load() }
    }

    private func load() async {
        if let existing = container.audioPlayback.library, existing.book.bookUrl == library.book.bookUrl {
            library = existing
            return
        }
        await library.load()
        if library.errorMessage == nil, !Task.isCancelled { container.audioPlayback.open(library) }
    }
    private func time(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
