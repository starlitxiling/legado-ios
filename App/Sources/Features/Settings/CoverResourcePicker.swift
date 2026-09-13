import SwiftUI
import UniformTypeIdentifiers
import LegadoCore

@MainActor struct CoverResourcePicker: View {
    let title: String
    let key: String
    let directory: String
    let preferences: AppPreferences
    @State private var importing = false
    @State private var error: String?
    var body: some View {
        Button(title) { importing = true }
            .fileImporter(isPresented: $importing, allowedContentTypes: key == "coverFont" ? [.font] : [.image]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let folder = BackupResources.defaultDirectory.appendingPathComponent(directory)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let filename = key.hasPrefix("defaultCover") ? key + ".image" : key + "-" + UUID().uuidString + "." + (url.pathExtension.isEmpty ? "image" : url.pathExtension)
                    let target = folder.appendingPathComponent(filename)
                    try Data(contentsOf: url).write(to: target, options: .atomic)
                    preferences.set(key, .string(target.path))
                } catch { self.error = error.localizedDescription }
            }
            .alert("导入失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("确定") { error = nil }
            } message: { Text(error ?? "") }
    }
}
