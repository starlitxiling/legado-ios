import Foundation

struct WebBookUpload {
    let fileName: String
    let bytes: Data

    private struct Invalid: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func parse(_ request: WebHttpRequest) throws -> WebBookUpload {
        var fields: [String: Data] = [:]
        if let type = request.headers["content-type"], type.lowercased().hasPrefix("multipart/form-data") {
            guard let boundaryParameter = type.components(separatedBy: ";").dropFirst().first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("boundary=") }) else { throw Invalid("fileData 不能为空") }
            let boundary = boundaryParameter.trimmingCharacters(in: .whitespaces).dropFirst(9).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !boundary.isEmpty, boundary.utf8.count <= 70, !boundary.contains("\r"), !boundary.contains("\n") else { throw WebHttpError.malformed }
            let marker = Data(("--" + boundary).utf8), separator = Data(("\r\n--" + boundary).utf8)
            guard request.body.starts(with: marker) else { throw WebHttpError.malformed }
            var offset = marker.count
            while offset < request.body.count {
                if request.body[offset...].starts(with: Data("--".utf8)) { break }
                guard request.body[offset...].starts(with: Data("\r\n".utf8)) else { throw WebHttpError.malformed }
                offset += 2
                guard let end = request.body.range(of: Data("\r\n\r\n".utf8), in: offset..<request.body.count),
                      end.lowerBound - offset <= WebHttpRequest.maximumHeaderSize,
                      let header = String(data: request.body[offset..<end.lowerBound], encoding: .utf8),
                      let next = request.body.range(of: separator, in: end.upperBound..<request.body.count) else { throw WebHttpError.malformed }
                let disposition = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-disposition:") } ?? ""
                if let name = disposition.components(separatedBy: ";").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("name=") }) {
                    let key = name.trimmingCharacters(in: .whitespaces).dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    guard fields[key] == nil else { throw WebHttpError.malformed }
                    fields[key] = request.body.subdata(in: end.upperBound..<next.lowerBound)
                }
                offset = next.upperBound
            }
        }
        guard let name = request.query["fileName"]?.first ?? fields["fileName"].flatMap({ String(data: $0, encoding: .utf8) }) else { throw Invalid("fileName 不能为空") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), name.range(of: "^[A-Za-z]:", options: .regularExpression) == nil,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Invalid("fileName 格式不正确") }
        guard let bytes = fields["fileData"] else { throw Invalid("fileData 不能为空") }
        return WebBookUpload(fileName: name, bytes: bytes)
    }

    static func save(_ upload: WebBookUpload, directory: URL, database: AppDatabase) async throws {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(upload.fileName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var saved = false
        defer {
            EpubParserCache.shared.invalidate(file); MobiParserCache.shared.invalidate(file)
            if !saved { try? FileManager.default.removeItem(at: folder) }
        }
        do {
            try upload.bytes.write(to: file, options: .atomic)
            let rules = try await TxtTocRuleRepository(database: database).list(enabledOnly: true)
            let parsed = try LocalBook.parse(url: file, rules: rules)
            var book = parsed.book
            if let cover = parsed.cover {
                let coverURL = folder.appendingPathComponent("cover")
                try cover.write(to: coverURL, options: .atomic); book.coverUrl = coverURL.absoluteString
            }
            try Task.checkCancellation()
            try await LocalBook.save(book: book, chapters: parsed.chapters, database: database)
            saved = true
        } catch { throw Invalid("保存书籍错误\n" + error.localizedDescription) }
    }
}
