import Foundation
import LegadoCore

struct SourceLoginKeychainStore: SourceSecretStore {
    func read(account: String) throws -> String? { try KeychainStore().read(account: account) }
    func write(_ value: String, account: String) throws { try KeychainStore().write(value, account: account) }
    func delete(account: String) throws { try KeychainStore().delete(account: account) }
}
