import SwiftUI

struct ReadAloudPanel: View {
    @Bindable var controller: ReadAloudController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if let paragraph = controller.engine.current { Text(paragraph.text).lineLimit(4) }
                HStack {
                    Button("上一段") { controller.previousParagraph() }
                    Spacer()
                    Button(controller.engine.state == .playing ? "暂停" : "播放") { controller.toggle() }
                    Spacer()
                    Button("下一段") { controller.nextParagraph() }
                    Button("停止") { controller.stop() }
                }
                Picker("语音源", selection: Binding(get: { controller.preferences.sourceID }, set: { controller.selectSource($0) })) {
                    Text("系统语音").tag(nil as Int64?)
                    ForEach(controller.sources) { source in Text(source.name).tag(Optional(source.id)) }
                }
                Section("语速：\(controller.preferences.rate, specifier: "%.1f") 倍") {
                    Slider(value: Binding(get: { controller.preferences.rate }, set: { controller.changeRate($0) }), in: 0.5...3, step: 0.1)
                }
                Section("音量") {
                    Slider(value: Binding(get: { controller.preferences.volume }, set: { controller.changeVolume($0) }), in: 0...1)
                }
                Toggle("按页朗读", isOn: Binding(get: { controller.preferences.readAloudByPage }, set: { controller.changePageMode($0) }))
                Menu("定时停止") {
                    Button("取消定时") { controller.engine.setTimer(seconds: nil) }
                    ForEach([5, 15, 30, 60], id: \.self) { minutes in
                        Button("\(minutes) 分钟") { controller.engine.setTimer(seconds: Double(minutes * 60)) }
                    }
                }
                if let seconds = controller.engine.remainingSeconds { Text("剩余播放时间：\(Int(seconds.rounded(.up))) 秒") }
                if let error = controller.errorMessage ?? controller.engine.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("听书")
            .toolbar { Button("完成") { dismiss() } }
        }.presentationDetents([.medium, .large])
    }
}
