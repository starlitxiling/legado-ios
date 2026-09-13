import SwiftUI
import UIKit
import CoreText
import UniformTypeIdentifiers

@MainActor
enum ReaderFonts {
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("fonts", isDirectory: true)
    }

    static func registerInstalled() {
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func install(_ url: URL) throws -> String {
        guard ["ttf", "otf"].contains(url.pathExtension.lowercased()) else { throw FontImportError.invalidFont }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else { throw FontImportError.invalidFont }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension.lowercased())
        try FileManager.default.copyItem(at: url, to: destination)
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &error) else {
            try? FileManager.default.removeItem(at: destination)
            if let error { throw error.takeRetainedValue() as Error }
            throw FontImportError.invalidFont
        }
        return name
    }
}

private enum FontImportError: LocalizedError {
    case invalidFont
    var errorDescription: String? { "无法读取或注册该字体文件。请选择有效的 TTF 或 OTF 字体。" }
}

struct FontPicker: View {
    @Binding var selection: String
    @State private var showsImporter = false
    @State private var errorMessage: String?
    @State private var names: [String] = []

    var body: some View {
        List {
            Button("系统默认") { selection = "" }
            Button("导入 TTF / OTF 字体") { showsImporter = true }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            ForEach(names, id: \.self) { name in
                Button { selection = name } label: {
                    HStack {
                        Text(name).font(.custom(name, size: 17))
                        Spacer()
                        if selection == name { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .navigationTitle("字体")
        .task { ReaderFonts.registerInstalled(); reload() }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.font]) { result in
            do { selection = try ReaderFonts.install(result.get()); errorMessage = nil; reload() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func reload() { names = UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) }.sorted() }
}
