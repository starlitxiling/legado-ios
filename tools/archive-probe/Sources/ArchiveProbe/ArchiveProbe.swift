import Foundation
import SWCompression
import Unrar

public enum ArchiveProbe {
    public static func readRAR(at url: URL) throws -> [String: Data] {
        let archive = try Archive(fileURL: url)
        var files: [String: Data] = [:]
        for entry in try archive.entries() where !entry.directory {
            files[entry.fileName] = try archive.extract(entry)
        }
        return files
    }

    public static func read7z(at url: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for entry in try SevenZipContainer.open(container: Data(contentsOf: url)) {
            if let data = entry.data {
                files[entry.info.name] = data
            }
        }
        return files
    }
}
