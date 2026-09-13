import Foundation

actor HttpTTSCache {
    static let shared = HttpTTSCache()
    private var protected: [URL: Int] = [:]
    func pin(_ url: URL) { protected[url, default: 0] += 1 }
    func prepare(_ url: URL, directory: URL, maximumBytes: Int, maximumAge: TimeInterval, now: Date) throws {
        try trim(directory: directory, maximumBytes: maximumBytes, maximumAge: maximumAge, now: now)
        pin(url)
    }
    func unpin(_ url: URL) {
        let count = (protected[url] ?? 1) - 1
        if count > 0 { protected[url] = count } else { protected[url] = nil }
    }
    func touch(_ url: URL, now: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }
    func remove(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func trim(directory: URL, maximumBytes: Int, maximumAge: TimeInterval, now: Date) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            .filter { $0.pathExtension == "audio" }
            .compactMap { url -> (URL, Int, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
            }.sorted { $0.2 == $1.2 ? $0.0.path < $1.0.path : $0.2 < $1.2 }
        var total = files.reduce(0) { $0 + $1.1 }
        for (url, size, date) in files where protected[url] == nil {
            if now.timeIntervalSince(date) >= maximumAge || total > maximumBytes {
                try remove(url); total -= size
            }
        }
    }
}
