import Foundation

struct MultipartBody {
    enum EncodingError: Error, Equatable, LocalizedError {
        case invalidForm, invalidFilePart(String), invalidContentType, invalidBoundary
        var errorDescription: String? {
            switch self {
            case .invalidForm: return "Multipart upload body must be a nonempty JSON object."
            case let .invalidFilePart(name): return "Invalid multipart file part: " + name
            case .invalidContentType: return "Invalid multipart content type."
            case .invalidBoundary: return "Invalid multipart boundary."
            }
        }
    }
    let data: Data
    let contentType: String

    init(json: String?, fileName: String, file: Any, contentType: String,
         type: String?, boundary: String = UUID().uuidString) throws {
        guard let json, case let .object(fields) = try? GsonValue.parse(Data(json.utf8)), !fields.isEmpty else {
            throw EncodingError.invalidForm
        }
        guard !boundary.isEmpty, boundary.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
            throw EncodingError.invalidBoundary
        }
        let type = type ?? "multipart/mixed"
        guard validMediaType(type), type.lowercased().hasPrefix("multipart/") else { throw EncodingError.invalidContentType }
        self.contentType = type + "; boundary=" + boundary
        var data = Data()
        func append(_ value: String) { data.append(contentsOf: value.utf8) }
        for (name, value) in fields {
            try Task.checkCancellation()
            append("--" + boundary + "\r\n")
            var disposition = "Content-Disposition: form-data; name=\"" + Self.quoted(name) + "\""
            let bytes: Data
            var mediaType: String?
            if case .string("fileRequest") = value {
                disposition += "; filename=\"" + Self.quoted(fileName) + "\""
                (bytes, mediaType) = try Self.fileBytes(file, mediaType: contentType)
            } else if case .object = value {
                guard case let .string(name)? = value["fileName"] else { throw EncodingError.invalidFilePart(name) }
                disposition += "; filename=\"" + Self.quoted(name) + "\""
                let fileValue = value["file"] ?? .null
                let fileObject: Any
                if case let .string(text) = fileValue { fileObject = text }
                else { fileObject = fileValue.json }
                (bytes, mediaType) = try Self.fileBytes(fileObject, mediaType: value["contentType"]?.stringValue)
            } else {
                bytes = Data(Self.formText(value).utf8)
            }
            append(disposition + "\r\n")
            if let mediaType { append("Content-Type: " + mediaType + "\r\n") }
            append("Content-Length: " + String(bytes.count) + "\r\n\r\n")
            data.append(bytes)
            append("\r\n")
        }
        append("--" + boundary + "--\r\n")
        self.data = data
    }

    private static func quoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "%0A").replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\"", with: "%22")
    }

    private static func fileBytes(_ file: Any, mediaType: String?) throws -> (Data, String?) {
        if let mediaType, !validMediaType(mediaType) { throw EncodingError.invalidContentType }
        if let data = file as? Data { return (data, mediaType) }
        if let url = file as? URL {
            guard url.isFileURL else { throw EncodingError.invalidFilePart("file URL must be local") }
            return (try Data(contentsOf: url), mediaType)
        }
        let text: String
        if let string = file as? String { text = string }
        else { text = String(decoding: try JSONSerialization.data(withJSONObject: file, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self) }
        let charset = mediaType.flatMap(ResponseDecoder.contentTypeCharset)
        let encoding = try ResponseDecoder.encoding(for: charset ?? "UTF-8")
        guard let data = text.data(using: encoding) else { throw EncodingError.invalidFilePart("file text cannot use requested charset") }
        return (data, mediaType.map { charset == nil ? $0 + "; charset=utf-8" : $0 })
    }

    private static func formText(_ value: GsonValue) -> String {
        switch value {
        case .null: return "null"
        case let .bool(value): return value ? "true" : "false"
        case let .string(value): return value
        case let .number(raw): return Double(raw).map { String($0) } ?? raw
        case let .array(values): return "[" + values.map(formText).joined(separator: ", ") + "]"
        case let .object(values): return "{" + values.map { $0.0 + "=" + formText($0.1) }.joined(separator: ", ") + "}"
        }
    }
}

private func validMediaType(_ value: String) -> Bool {
    !value.contains("\r") && !value.contains("\n") && value.range(
        of: "^[A-Za-z0-9!#$%&'*+.^_`|~-]+/[A-Za-z0-9!#$%&'*+.^_`|~-]+(?:[ \t]*;[^\r\n]*)?$",
        options: .regularExpression) != nil
}
