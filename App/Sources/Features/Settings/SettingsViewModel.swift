import Foundation
import Observation
import LegadoCore

struct WebDavCredentials: Codable {
    let baseURL: URL
    let username: String
    let password: String
}

@Observable
@MainActor
final class SettingsViewModel {
    private static let credentialsAccount = "webdav.credentials"
    var address = ""
    var username = ""
    var password = ""
    private(set) var isTesting = false
    private(set) var message: String?
    var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
    private let store: any KeychainStoring
    private let httpClient: any HttpClient

    init(store: any KeychainStoring, httpClient: any HttpClient) {
        self.store = store
        self.httpClient = httpClient
        do {
            if let encoded = try store.read(account: Self.credentialsAccount) {
                let value = try JSONDecoder().decode(WebDavCredentials.self, from: Data(encoded.utf8))
                address = value.baseURL.absoluteString
                username = value.username
                password = value.password
            }
        } catch { userError = error.presentation(operation: "读取 WebDAV 账号", subject: nil) }
    }

    func credentials() throws -> WebDavCredentials {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https", "dav", "davs"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw WebDavError.invalidURL }
        return WebDavCredentials(baseURL: url, username: username, password: password)
    }

    func save() {
        message = nil
        userError = nil
        do {
            let value = try credentials()
            let encoded = try JSONEncoder().encode(value)
            try store.write(String(decoding: encoded, as: UTF8.self), account: Self.credentialsAccount)
            message = "账号已保存到钥匙串"
        } catch { userError = error.presentation(operation: "保存 WebDAV 账号", subject: address) }
    }

    func clearCredentials() {
        message = nil
        userError = nil
        do {
            try store.delete(account: Self.credentialsAccount)
            address = ""; username = ""; password = ""
            message = "账号已删除"
        } catch { userError = error.presentation(operation: "删除 WebDAV 账号", subject: nil) }
    }

    func testConnection() async {
        guard !isTesting else { return }
        isTesting = true
        message = nil
        userError = nil
        defer { isTesting = false }
        do {
            let value = try credentials()
            let client = WebDavClient(baseURL: value.baseURL, username: value.username,
                                      password: value.password, httpClient: httpClient)
            _ = try await client.propfind(client.url(path: ""), depth: 0)
            message = "连接成功"
        } catch { userError = error.presentation(operation: "测试 WebDAV 连接", subject: address) }
    }

    static func localDeviceID(store: any KeychainStoring) throws -> String {
        if let value = try store.read(account: "device.id"), !value.isEmpty { return value }
        let value = UUID().uuidString
        try store.write(value, account: "device.id")
        return value
    }

    static func version(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "\(version)（\(build)）"
    }
}
