import Foundation

public struct ReaderStyleArchive {
    public var configuration: ReadBookConfig
    public let files: [String: Data]

    public static func encode(_ input: ReadBookConfig, background: (String) throws -> Data?,
                              font: (String) throws -> (String, Data)? = { _ in nil }) throws -> Data {
        var config = input
        config.underlineConfigVersion = 1
        var files: [String: Data] = [:]
        func append(_ raw: String, _ data: Data?) throws -> String {
            let name = URL(fileURLWithPath: raw).lastPathComponent
            guard !name.isEmpty, name != "readConfig.json", let data else {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: raw])
            }
            if let existing = files[name], existing != data { throw BackupArchiveError.duplicatePath(name) }
            files[name] = data
            return name
        }
        for (type, path) in [(config.bgType, \ReadBookConfig.bgStr), (config.bgTypeNight, \.bgStrNight), (config.bgTypeEInk, \.bgStrEInk)] where type == 2 {
            config[keyPath: path] = try append(config[keyPath: path], background(config[keyPath: path]))
        }
        for path in [\ReadBookConfig.textFont, \.titleFont] where !config[keyPath: path].isEmpty {
            if let (name, data) = try font(config[keyPath: path]) { config[keyPath: path] = try append(name, data) }
            else { config[keyPath: path] = "" }
        }
        files["readConfig.json"] = try JSONEncoder().encode(config)
        return try BackupExporter.zip(files.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }

    public static func decode(_ data: Data) throws -> Self {
        let files = try BackupArchive(data: data, maximumExpandedSize: 64 * 1024 * 1024).files
        guard let json = files["readConfig.json"] else { throw BackupArchiveError.invalidArchive }
        var config = try JSONDecoder().decode(ReadBookConfig.self, from: json)
        for (type, path) in [(config.bgType, \ReadBookConfig.bgStr), (config.bgTypeNight, \.bgStrNight), (config.bgTypeEInk, \.bgStrEInk)] where type == 2 {
            let name = URL(fileURLWithPath: config[keyPath: path]).lastPathComponent
            guard files[name] != nil else { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: name]) }
            config[keyPath: path] = name
        }
        for path in [\ReadBookConfig.textFont, \.titleFont] {
            let name = URL(fileURLWithPath: config[keyPath: path]).lastPathComponent
            config[keyPath: path] = files[name] == nil ? "" : name
        }
        return Self(configuration: config, files: files)
    }
}
