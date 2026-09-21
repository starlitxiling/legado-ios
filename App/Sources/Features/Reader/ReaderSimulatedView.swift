import SwiftUI
import LegadoCore

struct ReaderSimulatedView: View {
    let model: ReaderViewModel
    @State private var enabled = false
    @State private var startDate = Date()
    @State private var startChapter = 1
    @State private var dailyChapters = 3
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("模拟追读", isOn: $enabled)
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                Stepper("开始章节：\(startChapter)", value: $startChapter, in: 1...max(1, model.chapters.count))
                Stepper("每日更新：\(dailyChapters) 章", value: $dailyChapters, in: 1...1000)
                Text("当前已解锁 \(model.availableChapterCount) / \(model.chapters.count) 章").foregroundStyle(.secondary)
            }.disabled(saving).legadoNavigationTitle("模拟追读")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(saving) }
                }
        }.interactiveDismissDisabled(saving)
            .onAppear {
                let config = model.readerBook?.readConfig
                enabled = config?.readSimulating ?? false
                startChapter = min(max(1, model.chapters.count), max(1, (config?.startChapter ?? model.chapterIndex) + 1))
                dailyChapters = min(1000, max(1, config?.dailyChapters ?? 3))
                if let date = config?.startDate {
                    startDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: date.year, month: date.month, day: date.day)) ?? Date()
                }
            }
            .alert("模拟追读设置", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func save() {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: startDate)
        guard let year = components.year, let month = components.month, let day = components.day,
              let date = KotlinLocalDate(year: year, month: month, day: day) else { return }
        let enabled = enabled, chapter = startChapter - 1, daily = dailyChapters
        saving = true
        Task {
            await model.updateReadConfig { config in
                config.readSimulating = enabled; config.startDate = date; config.startChapter = chapter; config.dailyChapters = daily
            }
            saving = false
            if let message = model.errorMessage { error = message } else { dismiss() }
        }
    }
}
