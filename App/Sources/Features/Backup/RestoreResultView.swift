import SwiftUI
import LegadoCore

struct RestoreResultView: View {
    let report: BackupImportReport

    var body: some View {
        Section(report.failures.isEmpty ? "恢复结果" : "恢复结果（部分文件失败）") {
            ForEach(report.importedCounts.keys.sorted(), id: \.self) { name in
                LabeledContent(name, value: "\(report.importedCounts[name] ?? 0) 行")
            }
            if report.importedCounts.isEmpty { Text("没有导入任何数据表。") }
        }
        if !report.skippedFiles.isEmpty {
            Section("跳过的文件") {
                ForEach(report.skippedFiles, id: \.self) { Text($0) }
            }
        }
        if !report.failures.isEmpty {
            Section("失败的文件") {
                ForEach(report.failures.keys.sorted(), id: \.self) { name in
                    VStack(alignment: .leading) {
                        Text(name)
                        Text(report.failures[name] ?? "").font(.footnote).foregroundStyle(.red)
                    }
                }
            }
        }
        if !report.discardedFields.isEmpty {
            Section("未保留的字段") {
                ForEach(report.discardedFields.keys.sorted(), id: \.self) { name in
                    Text("\(name)：\((report.discardedFields[name] ?? []).joined(separator: "、"))")
                }
            }
        }
    }
}
