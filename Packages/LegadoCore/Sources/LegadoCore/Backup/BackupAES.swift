import Foundation
import CommonCrypto

public struct BackupAES {
    private let key: Data

    public init(password: String? = nil) {
        let input = Data((password ?? "").utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        input.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(input.count), &digest)
        }
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        key = Data(hex.prefix(16).utf8)
    }

    public func encrypt(_ data: Data) throws -> Data {
        Data(try crypt(data, operation: CCOperation(kCCEncrypt)).base64EncodedString().utf8)
    }

    public func decrypt(_ data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8),
              let encrypted = Data(base64Encoded: text.components(separatedBy: .whitespacesAndNewlines).joined()),
              !encrypted.isEmpty, encrypted.count % kCCBlockSizeAES128 == 0 else {
            throw BackupAESError.invalidCiphertext
        }
        return try crypt(encrypted, operation: CCOperation(kCCDecrypt))
    }

    static func requirePassword(_ password: String?, file: String) throws {
        guard let password, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackupError.passwordRequired(file: file)
        }
    }

    static func isJSONArray(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [Any]
    }

    private func crypt(_ input: Data, operation: CCOperation) throws -> Data {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, nil, source.baseAddress, input.count,
                            destination.baseAddress, capacity, &written)
                }
            }
        }
        guard status == kCCSuccess else { throw BackupAESError.cryptFailed(status) }
        output.count = written
        return output
    }
}

public enum BackupAESError: Error, CustomStringConvertible {
    case invalidCiphertext, invalidUTF8, cryptFailed(Int32)

    public var description: String {
        switch self {
        case .invalidCiphertext: return "BackupAES: expected Base64 AES ciphertext with complete 16-byte blocks"
        case .invalidUTF8: return "BackupAES: decrypted preference is not UTF-8"
        case .cryptFailed(let status): return "BackupAES: CommonCrypto status \(status); check localPassword and ciphertext"
        }
    }
}

public enum BackupError: Error, Equatable, CustomStringConvertible {
    case passwordRequired(file: String)

    public var description: String {
        switch self {
        case .passwordRequired(let file): return "Backup: nonblank localPassword required for \(file)"
        }
    }
}
