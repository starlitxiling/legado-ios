import Foundation

public enum BackupResources {
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LegadoResources", isDirectory: true)
    }

    static func persisted(_ name: String) -> Bool {
        name.range(of: #"^covers/[0-9a-fA-F]{32}\.cover$"#, options: .regularExpression) != nil
    }

    static func resource(_ name: String) -> Bool {
        ["covers/", "readRecordCovers/", "bg/"].contains { name.hasPrefix($0) } || name == "coverFont.ttf"
    }

    static func collect(root: URL, files: inout [(String, Data)], preferences: [String: AndroidPreferenceValue], selection: BackupSelection) throws {
        let manager = FileManager.default
        var referenced = Set<String>()
        func reference(_ path: String, directory: String) -> String? {
            let file: URL
            if path.hasPrefix("/") { file = URL(fileURLWithPath: path) }
            else if let url = URL(string: path), url.isFileURL { file = url }
            else { file = root.appendingPathComponent(path.hasPrefix(directory + "/") ? path : directory + "/" + path) }
            let canonical = file.resolvingSymlinksInPath().path
            let prefix = root.appendingPathComponent(directory).resolvingSymlinksInPath().path + "/"
            guard canonical.hasPrefix(prefix) else { return nil }
            return directory + "/" + canonical.dropFirst(prefix.count)
        }

        for key in ["backgroundImage", "backgroundImageNight"] {
            if case let .string(path)? = preferences[key], let relative = reference(path, directory: "bg") { referenced.insert(relative) }
        }
        for (name, data) in files where ["readConfig.json", "shareReadConfig.json", "readRecord.json", "themeConfig.json"].contains(name) {

            guard let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            func visit(_ value: Any) {
                if let rows = value as? [Any] { rows.forEach(visit) }
                if let row = value as? [String: Any] {
                    if name == "readRecord.json", let path = row["coverUrl"] as? String,
                       let relative = reference(path, directory: "readRecordCovers") { referenced.insert(relative) }
                    for suffix in ["", "Night", "EInk"] where (row["bgType" + suffix] as? Int) == 2 {
                        if let path = row["bgStr" + suffix] as? String {
                            if let relative = reference(path, directory: "bg") { referenced.insert(relative) }
                        }
                    }
                    if let path = row["backgroundImgPath"] as? String, let relative = reference(path, directory: "bg") { referenced.insert(relative) }
                    row.values.forEach(visit)
                }
            }
            visit(json)
        }
        for folder in ["covers", "readRecordCovers", "bg"] {
            let base = root.appendingPathComponent(folder)
            guard let iterator = manager.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            for case let file as URL in iterator {
                let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                      file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { continue }
                let name = String(file.path.dropFirst(root.path.count + 1))
                guard selection.includesFile(name), folder == "covers" || referenced.contains(name) else { continue }
                files.append((name, try Data(contentsOf: file)))
            }
        }
        if selection.includes("backupSettings"), selection.allowsPreference("coverFont"),
           case let .string(path)? = preferences["coverFont"], case let .file(file) = CoverFontReference(path) {
            if manager.fileExists(atPath: file.path) { files.append(("coverFont.ttf", try Data(contentsOf: file))) }
        }
    }

    static func relativePath(_ path: String) -> String? {
        let path = URL(string: path).flatMap { $0.isFileURL ? $0.path : nil } ?? path
        guard !path.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }), !path.contains("\\") else { return nil }
        for directory in ["covers", "readRecordCovers", "bg"] {
            if path.hasPrefix(directory + "/") { return path }
            if path.hasPrefix("/"), let range = path.range(of: "/" + directory + "/", options: .backwards) {
                return String(path[range.lowerBound...].dropFirst())
            }
        }
        return nil
    }

    static func rewrite(_ data: Data, name: String, root: URL?, available: Set<String>, exporting: Bool, selection: BackupSelection) throws -> Data {
        guard ["bookshelf.json", "bookGroup.json", "readRecord.json", "readConfig.json", "shareReadConfig.json", "themeConfig.json"].contains(name) else { return data }
        let json = try JSONSerialization.jsonObject(with: data)
        func visit(_ value: Any) -> Any {
            if let rows = value as? [Any] { return rows.map(visit) }
            guard var row = value as? [String: Any] else { return value }
            for (key, value) in row {
                if let path = value as? String, ["persistedCoverUrl", "customCoverUrl", "coverUrl", "cover", "bgStr", "bgStrNight", "bgStrEInk", "backgroundImgPath"].contains(key) {
                    if exporting, key == "persistedCoverUrl", !selection.includes("backupPersistedCovers") { row[key] = NSNull(); continue }
                    if exporting, name == "readRecord.json", path.lowercased().hasPrefix("data:"), !selection.includesFile("readRecordCovers/a") { row[key] = NSNull(); continue }
                    if let relative = relativePath(path) {
                        if exporting {
                            if name == "readRecord.json", relative.hasPrefix("readRecordCovers/"), !available.contains(relative) { row[key] = NSNull() }
                        } else if let root {
                            let target = root.appendingPathComponent(relative)
                            if available.contains(relative) || FileManager.default.fileExists(atPath: target.path) { row[key] = target.path }
                            else if !relative.hasPrefix("bg/") { row[key] = NSNull() }
                        }
                    }
                } else { row[key] = visit(value) }
            }
            return row
        }
        return try JSONSerialization.data(withJSONObject: visit(json), options: [.sortedKeys])
    }

    static func restore(_ archive: BackupArchive, root: URL, selection: BackupSelection) throws -> [String] {
        let manager = FileManager.default
        var restored: [String] = []
        for directory in ["covers", "readRecordCovers", "bg", "font"] {
            if directory == "bg", selection.values["readConfig"] == true { continue }
            if directory == "font", selection.values["coverConfig"] == true { continue }
            let entries = archive.files.filter { name, _ in
                if selection.values["coverConfig"] == true,
                   ["covers/defaultCover.image", "covers/defaultCoverDark.image"].contains(name) { return false }
                return directory == "font" ? name == "coverFont.ttf" : name.hasPrefix(directory + "/")
            }
            guard !entries.isEmpty else { continue }
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let target = root.appendingPathComponent(directory)
            let stage = root.appendingPathComponent(".restore-" + UUID().uuidString)
            let previous = root.appendingPathComponent(".previous-" + UUID().uuidString)
            defer { try? manager.removeItem(at: stage) }
            if manager.fileExists(atPath: target.path) {
                guard target.resolvingSymlinksInPath().path == target.standardizedFileURL.path else { throw BackupArchiveError.unsafePath(target.path) }
                try manager.copyItem(at: target, to: stage)
            } else { try manager.createDirectory(at: stage, withIntermediateDirectories: true) }
            for (name, data) in entries {
                let relative = directory == "font" ? name : String(name.dropFirst(directory.count + 1))
                let file = stage.appendingPathComponent(relative)
                guard file.resolvingSymlinksInPath().path.hasPrefix(stage.path + "/") else { throw BackupArchiveError.unsafePath(name) }
                try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            }
            let hadTarget = manager.fileExists(atPath: target.path)
            if hadTarget { try manager.moveItem(at: target, to: previous) }
            do { try manager.moveItem(at: stage, to: target) }
            catch { if hadTarget { try? manager.moveItem(at: previous, to: target) }; throw error }
            if hadTarget { try manager.removeItem(at: previous) }
            restored.append(contentsOf: entries.keys)
        }
        return restored.sorted()
    }
}
