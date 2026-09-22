import Foundation
import GRDB

extension Error {
    var isCancellation: Bool {
        var current: Error = self
        var visited = Set<ObjectIdentifier>()
        let cancellation = CancellationError() as NSError
        for _ in 0..<16 {
            if current is CancellationError { return true }
            if let database = current as? DatabaseError, database.resultCode == .SQLITE_INTERRUPT { return true }
            let error = current as NSError
            if error.domain == NSURLErrorDomain && error.code == URLError.cancelled.rawValue { return true }
            if error.domain == cancellation.domain && error.code == cancellation.code { return true }
            guard visited.insert(ObjectIdentifier(error)).inserted,
                  let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error else { return false }
            current = underlying
        }
        return false
    }

    var presentableMessage: String? {
        guard !isCancellation else { return nil }
        var message = presentationReason
        if let suggestion = (self as? LocalizedError)?.recoverySuggestion, !suggestion.isEmpty {
            message += "\n" + suggestion
        }
        return message
    }
}


struct UserFacingError: Equatable, Identifiable {
    enum Action: String, CaseIterable {
        case retry, changeSource, manageSources, openSettings, back
        var title: String {
            switch self {
            case .retry: return "重试"
            case .changeSource: return "换源"
            case .manageSources: return "书源管理"
            case .openSettings: return "设置"
            case .back: return "返回"
            }
        }
    }
    let title: String
    let message: String
    var actions: [Action] = []
    var id: String { displayText }
    var displayText: String { title + "\n" + message }
}

extension Error {
    func presentation(operation: String, subject: String? = nil, sourceFile: String? = nil,
                      actions: [UserFacingError.Action] = []) -> UserFacingError? {
        guard let message = presentableMessage else { return nil }
        let context = [subject, sourceFile].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return UserFacingError(title: operation + "失败", message: context.isEmpty ? message : context + "\n" + message,
                               actions: actions)
    }

    private var presentationReason: String {
        if let error = self as? DecodingError {
            let context: DecodingError.Context
            var missingKey: CodingKey?
            switch error {
            case .dataCorrupted(let value), .typeMismatch(_, let value), .valueNotFound(_, let value): context = value
            case .keyNotFound(let key, let value): context = value; missingKey = key
            @unknown default: return "数据格式不正确，请检查文件内容。"
            }
            let path = (context.codingPath + (missingKey.map { [$0] } ?? [])).reduce("") { result, key in
                if let index = key.intValue { return result + "[\(index)]" }
                return result + (result.isEmpty ? "" : ".") + key.stringValue
            }
            return "数据格式不正确" + (path.isEmpty ? "。" : "，字段：\(path)。") + "请检查数据类型，或重新导出后导入。"
        }
        if let error = self as? DatabaseError {
            return "本地数据库错误（代码 \(error.resultCode.rawValue)）。请重试；若仍失败，请保留备份并检查应用日志。"
        }
        let error = self as NSError
        if error.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: error.code) {
            case .notConnectedToInternet, .networkConnectionLost: return "网络连接不可用，请连接网络后重试。"
            case .timedOut: return "网络请求超时，请稍后重试或切换书源。"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "无法连接服务器，请检查地址和网络后重试。"
            case .secureConnectionFailed: return "无法建立安全连接，请检查服务器的 HTTPS 配置。"
            case .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
                return "服务器证书验证失败，请检查设备时间或联系服务提供方。"
            case .badURL, .unsupportedURL: return "网络地址无效或不受支持，请检查地址。"
            case .userAuthenticationRequired, .userCancelledAuthentication: return "服务器认证失败，请检查账号和密码。"
            case .dataNotAllowed: return "此应用不允许使用当前网络，请检查系统网络权限。"
            default: return "网络请求失败（代码 \(error.code)）。请检查网络与服务器状态后重试。"
            }
        }
        if error.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: error.code) {
            case .fileReadNoPermission, .fileWriteNoPermission: return "没有访问此文件的权限，请重新选择文件并授权访问。"
            case .fileReadNoSuchFile, .fileNoSuchFile: return "找不到文件，请确认文件存在后重新选择。"
            case .propertyListReadCorrupt: return "数据格式不正确，请重新导出 JSON 文件后导入。"
            case .fileWriteInvalidFileName: return "文件或目录名称无效，请在设置中使用单个有效的文件夹名称。"
            case .fileReadCorruptFile: return "文件已损坏或格式不正确，请重新获取完整文件。"
            case .fileWriteOutOfSpace: return "设备剩余空间不足，请释放空间后重试。"
            default: break
            }
        }
        if let description = (self as? LocalizedError)?.errorDescription, !description.isEmpty { return description }
        return "操作失败：" + localizedDescription
    }
}
