import Foundation

public enum AndroidPreferenceValue: Equatable, Sendable {
    case string(String), boolean(Bool), int(Int32), long(Int64), float(Float), stringSet(Set<String>)
}

public enum AndroidPreferencesXML {
    public static func encode(_ values: [String: AndroidPreferenceValue]) -> Data {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "\r", with: "&#13;").replacingOccurrences(of: "\n", with: "&#10;")
                .replacingOccurrences(of: "\t", with: "&#9;")
        }
        let rows = values.keys.sorted().map { key -> String in
            let name = escape(key)
            switch values[key]! {
            case .string(let value): return "<string name=\"\(name)\">\(escape(value))</string>"
            case .boolean(let value): return "<boolean name=\"\(name)\" value=\"\(value)\" />"
            case .int(let value): return "<int name=\"\(name)\" value=\"\(value)\" />"
            case .long(let value): return "<long name=\"\(name)\" value=\"\(value)\" />"
            case .float(let value): return "<float name=\"\(name)\" value=\"\(value)\" />"
            case .stringSet(let value): return "<set name=\"\(name)\">" + value.sorted().map { "<string>\(escape($0))</string>" }.joined() + "</set>"
            }
        }
        return Data(("<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?>\n<map>\n" + rows.joined(separator: "\n") + "\n</map>").utf8)
    }

    public static func decode(_ data: Data) throws -> [String: AndroidPreferenceValue] {
        let delegate = PreferenceParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.invalid, delegate.sawMap else { throw BackupArchiveError.invalidArchive }
        return delegate.values
    }
}

private final class PreferenceParser: NSObject, XMLParserDelegate {
    var values: [String: AndroidPreferenceValue] = [:]
    var invalid = false
    var sawMap = false
    private var stack: [String] = []
    private var key = ""
    private var text = ""
    private var strings = Set<String>()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if stack.isEmpty {
            guard elementName == "map", !sawMap else { invalid = true; return }
            sawMap = true
        } else if stack == ["map"] {
            guard let name = attributes["name"], values[name] == nil else { invalid = true; return }
            key = name; text = ""; strings = []
            let raw = attributes["value"] ?? ""
            switch elementName {
            case "string", "set": break
            case "boolean": if raw == "true" || raw == "false" { values[key] = .boolean(raw == "true") } else { invalid = true }
            case "int": if let value = Int32(raw) { values[key] = .int(value) } else { invalid = true }
            case "long": if let value = Int64(raw) { values[key] = .long(value) } else { invalid = true }
            case "float": if let value = Float(raw), value.isFinite { values[key] = .float(value) } else { invalid = true }
            default: invalid = true
            }
        } else if stack == ["map", "set"], elementName == "string" { text = "" }
        else { invalid = true }
        stack.append(elementName)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if stack == ["map", "string"] { values[key] = .string(text) }
        if stack == ["map", "set", "string"] { strings.insert(text) }
        if stack == ["map", "set"] { values[key] = .stringSet(strings) }
        if !stack.isEmpty { stack.removeLast() }
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { invalid = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { invalid = true; parser.abortParsing() }
}

public enum AndroidBackupPreferences {
    public static let defaults: [String: AndroidPreferenceValue] = [
        "themeMode": .string("0"), "language": .string("auto"), "preDownloadNum": .int(2),
        "threadCount": .int(32), "bookshelfSort": .int(0), "autoBackup": .boolean(true),
        "autoBackupWebDav": .boolean(true), "autoBackupIntervalDays": .int(1),
        "syncBookProgress": .boolean(true), "syncBookProgressPlus": .boolean(false),
        "onlyLatestBackup": .boolean(true), "autoCheckNewBackup": .boolean(true),
        "webDavDir": .string("legado"), "showDiscovery": .boolean(true), "showRss": .boolean(true),
        "auto_refresh": .boolean(false), "onlyUpdateRead": .boolean(false), "defaultToRead": .boolean(false),
        "defaultHomePage": .string("bookshelf"), "loadCoverOnlyWifi": .boolean(false)
    ]

    public static let ignoredKeys: Set<String> = [
        "defaultCover", "defaultCoverDark", "backupUri", "defaultBookTreeUri", "webDavDeviceName",
        "webDavBookAutoRestore", "jsSourceApiToken", "launcherIcon", "bitmapCacheSize", "webServiceWakeLock",
        "readAloudWakeLock", "audioPlayWakeLock"
    ]
}
