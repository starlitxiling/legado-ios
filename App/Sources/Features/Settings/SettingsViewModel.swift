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
    private(set) var errorMessage: String?
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
        } catch { errorMessage = error.localizedDescription }
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
        errorMessage = nil
        do {
            let value = try credentials()
            let encoded = try JSONEncoder().encode(value)
            try store.write(String(decoding: encoded, as: UTF8.self), account: Self.credentialsAccount)
            message = "账号已保存到钥匙串"
        } catch { errorMessage = error.localizedDescription }
    }

    func clearCredentials() {
        message = nil
        errorMessage = nil
        do {
            try store.delete(account: Self.credentialsAccount)
            address = ""; username = ""; password = ""
            message = "账号已删除"
        } catch { errorMessage = error.localizedDescription }
    }

    func testConnection() async {
        guard !isTesting else { return }
        isTesting = true
        message = nil
        errorMessage = nil
        defer { isTesting = false }
        do {
            let value = try credentials()
            let client = WebDavClient(baseURL: value.baseURL, username: value.username,
                                      password: value.password, httpClient: httpClient)
            _ = try await client.propfind(client.url(path: ""), depth: 0)
            message = "连接成功"
        } catch { errorMessage = error.localizedDescription }
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
