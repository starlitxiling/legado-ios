import Foundation
import Security

final class JsAsymmetricCrypto: JsCryptoObject {
    let methods: [String]
    private let algorithm: String
    private let signing: Bool
    private var privateKey: SecKey
    private var publicKey: SecKey

    init(algorithm: String, signing: Bool = false) throws {
        self.algorithm = algorithm
        self.signing = signing
        guard signing ? algorithm.uppercased().contains("WITHRSA") : algorithm.uppercased().hasPrefix("RSA") else {
            throw JsEngineError.exception("Unsupported asymmetric algorithm: \(algorithm)")
        }
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 1024]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error), let publicKey = SecKeyCopyPublicKey(key) else {
            throw Self.failure("RSA key generation", error)
        }
        privateKey = key; self.publicKey = publicKey
        methods = ["setPrivateKey", "setPublicKey", "getPrivateKey", "getPublicKey", "getPrivateKeyBase64", "getPublicKeyBase64", "getAlgorithm"]
            + (signing ? ["sign", "signHex", "verify"] : ["encrypt", "encryptHex", "encryptBase64", "decrypt", "decryptStr"])
        if signing { _ = try signatureAlgorithm() }
        else { _ = try encryptionAlgorithm() }
    }

    func call(_ method: String, arguments: [Any]) throws -> Any? {
        let first = arguments.first
        switch method {
        case "getAlgorithm": return algorithm
        case "setPrivateKey": privateKey = try importKey(JavaHostCrypto.bytes(first), privateKey: true); return nil
        case "setPublicKey": publicKey = try importKey(JavaHostCrypto.bytes(first), privateKey: false); return nil
        case "getPrivateKey", "getPublicKey", "getPrivateKeyBase64", "getPublicKeyBase64":
            let isPrivate = method.contains("Private")
            let data = try exportKey(privateKey: isPrivate)
            if method.hasSuffix("Base64") { return data.base64EncodedString() }
            return ["__legadoKeyBytes": Array(data), "algorithm": "RSA", "format": isPrivate ? "PKCS#8" : "X.509"]
        case "sign", "signHex":
            guard signing else { throw JsEngineError.exception("Crypto object does not support signing") }
            let data = try JavaHostCrypto.bytes(first, charset: arguments.dropFirst().first as? String ?? "UTF-8")
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(privateKey, try signatureAlgorithm(), data as CFData, &error) else {
                throw Self.failure("RSA signing", error)
            }
            return method == "signHex" ? JavaHostCrypto.hex(signature as Data) : signature as Data
        case "verify":
            guard signing, arguments.count == 2 else { throw JsEngineError.exception("verify requires data and signature") }
            var error: Unmanaged<CFError>?
            let result = SecKeyVerifySignature(publicKey, try signatureAlgorithm(), try JavaHostCrypto.bytes(first) as CFData,
                try JavaHostCrypto.bytes(arguments[1]) as CFData, &error)
            if let error {
                let detail = error.takeRetainedValue()
                if CFErrorGetCode(detail) != errSecVerifyFailed {
                    throw JsEngineError.exception("RSA verification failed: \(detail)")
                }
            }
            return result
        case "encrypt", "encryptHex", "encryptBase64", "decrypt", "decryptStr":
            guard !signing else { throw JsEngineError.exception("Signing object does not support encryption") }
            let encrypt = method.hasPrefix("encrypt")
            let usePublic = arguments.count < 2 ? true : (arguments[1] as? Bool ?? false)
            let input = try encrypt ? JavaHostCrypto.bytes(first) : JavaHostCrypto.ciphertext(first)
            let result = try process(input, encrypt: encrypt, usePublic: usePublic)
            if method == "encryptHex" { return JavaHostCrypto.hex(result) }
            if method == "encryptBase64" { return result.base64EncodedString() }
            if method == "decryptStr" { return String(decoding: result, as: UTF8.self) }
            return result
        default: throw JsEngineError.exception("Unsupported asymmetric method: \(method)")
        }
    }

    private func signatureAlgorithm() throws -> SecKeyAlgorithm {
        switch algorithm.uppercased().replacingOccurrences(of: "-", with: "") {
        case "SHA1WITHRSA": return .rsaSignatureMessagePKCS1v15SHA1
        case "SHA224WITHRSA": return .rsaSignatureMessagePKCS1v15SHA224
        case "SHA256WITHRSA": return .rsaSignatureMessagePKCS1v15SHA256
        case "SHA384WITHRSA": return .rsaSignatureMessagePKCS1v15SHA384
        case "SHA512WITHRSA": return .rsaSignatureMessagePKCS1v15SHA512
        default: throw JsEngineError.exception("Unsupported signature algorithm: \(algorithm)")
        }
    }

    private func encryptionAlgorithm() throws -> (SecKeyAlgorithm, Int) {
        switch algorithm.uppercased().replacingOccurrences(of: "-", with: "") {
        case "RSA", "RSA/ECB/PKCS1PADDING", "RSA/NONE/PKCS1PADDING": return (.rsaEncryptionPKCS1, 11)
        case "RSA/ECB/NOPADDING", "RSA/NONE/NOPADDING": return (.rsaEncryptionRaw, 0)
        case "RSA/ECB/OAEPPADDING", "RSA/ECB/OAEPWITHSHA1ANDMGF1PADDING": return (.rsaEncryptionOAEPSHA1, 42)
        case "RSA/ECB/OAEPWITHSHA224ANDMGF1PADDING": return (.rsaEncryptionOAEPSHA224, 58)
        case "RSA/ECB/OAEPWITHSHA256ANDMGF1PADDING": return (.rsaEncryptionOAEPSHA256, 66)
        case "RSA/ECB/OAEPWITHSHA384ANDMGF1PADDING": return (.rsaEncryptionOAEPSHA384, 98)
        case "RSA/ECB/OAEPWITHSHA512ANDMGF1PADDING": return (.rsaEncryptionOAEPSHA512, 130)
        default: throw JsEngineError.exception("Unsupported RSA transformation: \(algorithm)")
        }
    }

    private func process(_ data: Data, encrypt: Bool, usePublic: Bool) throws -> Data {
        let key = usePublic ? publicKey : privateKey
        let size = SecKeyGetBlockSize(key)
        let (algorithm, overhead) = try encryptionAlgorithm()
        let count = encrypt ? size - overhead : size
        guard count > 0, encrypt || data.count % size == 0 else { throw JsEngineError.exception("Invalid RSA block length") }
        var result = Data()
        for offset in stride(from: 0, to: max(1, data.count), by: count) {
            let block = Data(data.dropFirst(offset).prefix(count))
            var error: Unmanaged<CFError>?
            let output: CFData?
            if encrypt && usePublic { output = SecKeyCreateEncryptedData(key, algorithm, block as CFData, &error) }
            else if !encrypt && !usePublic { output = SecKeyCreateDecryptedData(key, algorithm, block as CFData, &error) }
            else if encrypt {
                guard overhead <= 11 else { throw JsEngineError.exception("OAEP requires public-key encryption") }
                var padded = block
                if overhead == 11 { padded = Data([0, 1]) + Data(repeating: 0xff, count: size - block.count - 3) + Data([0]) + block }
                else { padded = Data(repeating: 0, count: size - block.count) + block }
                output = SecKeyCreateSignature(key, .rsaSignatureRaw, padded as CFData, &error)
            } else {
                guard overhead <= 11 else { throw JsEngineError.exception("OAEP requires private-key decryption") }
                output = SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, block as CFData, &error)
            }
            guard let output else { throw Self.failure("RSA operation", error) }
            var bytes = output as Data
            if !encrypt && usePublic && overhead == 11 {
                guard bytes.starts(with: [0, 1]), let end = bytes.dropFirst(2).firstIndex(of: 0), end >= 10,
                      bytes[2..<end].allSatisfy({ $0 == 0xff }) else { throw JsEngineError.exception("Invalid RSA signature padding") }
                bytes = Data(bytes.dropFirst(end + 1))
            }
            result.append(bytes)
        }
        return result
    }

    private func importKey(_ data: Data, privateKey: Bool) throws -> SecKey {
        let root = try CryptoDER.children(data)
        var raw = data
        if privateKey, root.count >= 3, root[1].tag == 0x30, root[2].tag == 0x04 { raw = root[2].value }
        else if !privateKey, root.count == 2, root[0].tag == 0x30, root[1].tag == 0x03, root[1].value.first == 0 {
            raw = Data(root[1].value.dropFirst())
        }
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: privateKey ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(raw as CFData, attributes as CFDictionary, &error) else {
            throw Self.failure("RSA key import", error)
        }
        return key
    }

    private func exportKey(privateKey: Bool) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(privateKey ? self.privateKey : publicKey, &error) else {
            throw Self.failure("RSA key export", error)
        }
        let identifier = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
        let body = privateKey ? Data([0x02, 0x01, 0x00]) + identifier + CryptoDER.wrap(0x04, raw as Data)
            : identifier + CryptoDER.wrap(0x03, Data([0]) + (raw as Data))
        return CryptoDER.wrap(0x30, body)
    }

    private static func failure(_ operation: String, _ error: Unmanaged<CFError>?) -> JsEngineError {
        .exception(operation + " failed: " + (error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown Security error"))
    }
}

enum CryptoDER {
    struct Node { let tag: UInt8; let value: Data }

    static func children(_ data: Data) throws -> [Node] {
        let bytes = Array(data)
        var cursor = 0
        func read() throws -> Node {
            guard cursor + 2 <= bytes.count else { throw JsEngineError.exception("Truncated DER key") }
            let tag = bytes[cursor]; cursor += 1
            var count = Int(bytes[cursor]); cursor += 1
            if count & 0x80 != 0 {
                let size = count & 0x7f
                guard (1...4).contains(size), cursor + size <= bytes.count else { throw JsEngineError.exception("Invalid DER key length") }
                count = 0
                for _ in 0..<size { count = count * 256 + Int(bytes[cursor]); cursor += 1 }
            }
            guard count <= bytes.count - cursor else { throw JsEngineError.exception("Truncated DER key value") }
            defer { cursor += count }
            return Node(tag: tag, value: Data(bytes[cursor..<(cursor + count)]))
        }
        let root = try read()
        guard root.tag == 0x30, cursor == bytes.count else { throw JsEngineError.exception("Expected DER key sequence") }
        return try readNodes(root.value)
    }

    private static func readNodes(_ data: Data) throws -> [Node] {
        var remaining = Array(data)
        var nodes: [Node] = []
        while !remaining.isEmpty {
            guard remaining.count >= 2 else { throw JsEngineError.exception("Truncated DER sequence") }
            let tag = remaining[0]
            var length = Int(remaining[1]), header = 2
            if length & 0x80 != 0 {
                let size = length & 0x7f
                guard (1...4).contains(size), remaining.count >= 2 + size else { throw JsEngineError.exception("Invalid DER sequence length") }
                length = remaining[2..<(2 + size)].reduce(0) { $0 * 256 + Int($1) }; header += size
            }
            guard length <= remaining.count - header else { throw JsEngineError.exception("Truncated DER sequence value") }
            nodes.append(Node(tag: tag, value: Data(remaining[header..<(header + length)])))
            remaining.removeFirst(header + length)
        }
        return nodes
    }

    static func wrap(_ tag: UInt8, _ value: Data) -> Data {
        if value.count < 128 { return Data([tag, UInt8(value.count)]) + value }
        var count = value.count, length: [UInt8] = []
        while count > 0 { length.insert(UInt8(count & 0xff), at: 0); count >>= 8 }
        return Data([tag, 0x80 | UInt8(length.count)]) + Data(length) + value
    }
}
