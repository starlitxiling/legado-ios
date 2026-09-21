import Foundation
import CryptoKit

extension JavaHostNetwork {
    static let fileMethods = ["getFile", "readFile", "readTxtFile", "deleteFile", "unzipFile", "un7zFile", "unrarFile",
        "unArchiveFile", "getTxtInFolder", "getZipStringContent", "getRarStringContent", "get7zStringContent",
        "getZipByteArrayContent", "getRarByteArrayContent", "get7zByteArrayContent", "importScript"]

    func callFile(_ method: String, _ arguments: [Any]) throws -> Any? {
        let path = ruleText(arguments.first)
        let store = engine.downloadStore
        let charset = arguments.count > 1 ? arguments[1] as? String : nil
        func decode(_ data: Data, charset: String?) throws -> String {
            if let charset { return try JavaHostEncoding.decode(data, charset: charset) }
            let result = TextEncodingDetector.detect(Data(data.prefix(512_000)), truncated: data.count > 512_000)
            return try JavaHostEncoding.decode(data.dropFirst(result.bomSize), charset: result.name)
        }
        guard !arguments.isEmpty else { throw JsEngineError.exception(method + " requires a path") }
        switch method {
        case "importScript":
            let text: String
            if path.hasPrefix("http://") || path.hasPrefix("https://") { text = try call("cacheFile", [path]) as? String ?? "" }
            else { text = try callFile("readTxtFile", [path]) as? String ?? "" }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw JsEngineError.exception(path + " content is empty or unavailable")
            }
            return text
        case "getFile":
            return ["__legadoFile": try HostFilePath.normalize(path)]
        case "file.info":
            let info = try HostAsyncBridge.wait { try await store.info(path) }
            return ["path": info.path, "exists": info.exists, "isDirectory": info.isDirectory, "size": info.size]
        case "readFile":
            return try HostAsyncBridge.wait { try await store.read(path) }
        case "readTxtFile":
            guard let data = try HostAsyncBridge.wait({ try await store.read(path) }) else { return "" }
            return try decode(data, charset: charset)
        case "deleteFile":
            return try HostAsyncBridge.wait { try await store.delete(path) }
        case "getTxtInFolder":
            guard !path.isEmpty else { return "" }
            let files = try HostAsyncBridge.wait { try await store.list(path) }
            let result = try files.map { file -> String in
                guard let bytes = try HostAsyncBridge.wait({ try await store.read(file) }) else { return "" }
                return try decode(bytes, charset: nil)
            }.joined(separator: "\n")
            _ = try HostAsyncBridge.wait { try await store.delete(path) }
            return result
        case "unzipFile", "un7zFile", "unrarFile", "unArchiveFile":
            guard !path.isEmpty else { return "" }
            guard let data = try HostAsyncBridge.wait({ try await store.read(path) }) else { throw BookArchiveError.missing(path) }
            let format = archiveFormat(data, fallback: (path as NSString).pathExtension)
            let archive = try BookArchive(data: data, format: format)
            let digest = Insecure.MD5.hash(data: Data((path as NSString).lastPathComponent.utf8)).map { String(format: "%02x", $0) }.joined()
            let destination = "ArchiveTemp/" + String(digest.dropFirst(8).prefix(16))
            _ = try HostAsyncBridge.wait { try await store.delete(destination) }
            do {
                for entry in archive.entries {
                    try Task.checkCancellation()
                    let bytes = try archive.read(entry.name), output = destination + "/" + entry.name
                    _ = try HostAsyncBridge.wait { try await store.save(bytes, path: output) }
                }
                return destination
            } catch {
                _ = try? HostAsyncBridge.wait { try await store.delete(destination) }
                throw error
            }
        default:
            guard arguments.count >= 2 else { throw JsEngineError.exception(method + " requires archive and entry") }
            let data: Data
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                let executor = try AnalyzeUrlExecutor(path, engine: engine)
                data = try HostAsyncBridge.wait { try await executor.getByteArray() }
            } else { data = try JavaHostEncoding.hex(path) }
            let format = method.contains("Zip") ? "zip" : method.contains("Rar") ? "rar" : "7z"
            let archive = try BookArchive(data: data, format: format)
            let entry = ruleText(arguments[1])
            guard archive.entries.contains(where: { $0.name == entry }) else {
                engine.logger(method + " entry not found: " + entry)
                return method.contains("String") ? "" : nil
            }
            let bytes = try archive.read(entry)
            if method.contains("ByteArray") { return bytes }
            return try decode(bytes, charset: arguments.count > 2 ? arguments[2] as? String : nil)
        }
    }

    private func archiveFormat(_ data: Data, fallback: String) -> String {
        if data.starts(with: [0x50, 0x4b]) { return "zip" }
        if data.starts(with: [0x52, 0x61, 0x72, 0x21]) { return "rar" }
        if data.starts(with: [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) { return "7z" }
        return fallback.lowercased()
    }
}
