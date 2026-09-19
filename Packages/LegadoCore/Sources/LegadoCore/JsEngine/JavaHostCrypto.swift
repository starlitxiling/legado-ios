import Foundation
import CryptoKit
import CommonCrypto
import Security

protocol JsCryptoObject: AnyObject {
    var methods: [String] { get }
    func call(_ method: String, arguments: [Any]) throws -> Any?
}

final class JavaHostCrypto {
    static let methods = ["md5Encode", "md5Encode16", "digestHex", "digestBase64Str", "HMacHex", "HMacBase64",
        "createSymmetricCrypto", "createAsymmetricCrypto", "createSign", "aesDecodeToByteArray", "aesDecodeToString",
        "aesDecodeArgsBase64Str", "aesBase64DecodeToByteArray", "aesBase64DecodeToString", "aesEncodeToByteArray",
        "aesEncodeToString", "aesEncodeToBase64ByteArray", "aesEncodeToBase64String", "aesEncodeArgsBase64Str",
        "desDecodeToString", "desBase64DecodeToString", "desEncodeToString", "desEncodeToBase64String",
        "tripleDESDecodeStr", "tripleDESDecodeArgsBase64Str", "tripleDESEncodeBase64Str", "tripleDESEncodeArgsBase64Str"]
    private var objects: [Int: any JsCryptoObject] = [:]

    func call(_ method: String, arguments: [Any]) throws -> Any? {
        func value(_ index: Int) -> Any? { arguments.indices.contains(index) ? arguments[index] : nil }
        func text(_ index: Int) -> String { ruleText(value(index)) }
        if method.hasPrefix("crypto.") {
            guard let id = value(0) as? Int, let object = objects[id] else { throw JsEngineError.exception("Unknown crypto object") }
            return try object.call(String(method.dropFirst(7)), arguments: Array(arguments.dropFirst()))
        }
        switch method {
        case "md5Encode", "md5Encode16":
            let hex = Self.hex(Data(Insecure.MD5.hash(data: Data(text(0).utf8))))
            return method == "md5Encode16" ? String(hex.dropFirst(8).prefix(16)) : hex
        case "digestHex", "digestBase64Str":
            let result = try Self.digest(Data(text(0).utf8), algorithm: text(1))
            return method == "digestHex" ? Self.hex(result) : result.base64EncodedString()
        case "HMacHex", "HMacBase64":
            let result = try Self.hmac(Data(text(0).utf8), algorithm: text(1), key: Data(text(2).utf8))
            return method == "HMacHex" ? Self.hex(result) : result.base64EncodedString()
        case "createSymmetricCrypto":
            return register(try JsSymmetricCrypto(transformation: text(0), key: Self.optionalBytes(value(1)), iv: Self.optionalBytes(value(2))))
        case "createAsymmetricCrypto": return register(try JsAsymmetricCrypto(algorithm: text(0)))
        case "createSign": return register(try JsAsymmetricCrypto(algorithm: text(0), signing: true))
        default:
            let transformation: String
            var key = Data(text(1).utf8)
            var iv: Data
            if method.hasPrefix("tripleDES") || method.contains("ArgsBase64") {
                transformation = (method.hasPrefix("tripleDES") ? "DESede/" : "AES/") + text(2) + "/" + text(3)
                iv = Data(text(4).utf8)
                if method.hasPrefix("tripleDES") && method.contains("ArgsBase64") || method == "aesDecodeArgsBase64Str" {
                    key = try JavaHostEncoding.base64(text(1), flags: 2)
                }
                if method == "aesDecodeArgsBase64Str" { iv = try JavaHostEncoding.base64(text(4), flags: 2) }
            } else { transformation = text(2); iv = Data(text(3).utf8) }
            let cipher = try JsSymmetricCrypto(transformation: transformation, key: key, iv: iv)
            let decrypt = method.contains("Decode") || method == "aesEncodeToString"
            let data = try decrypt ? Self.ciphertext(value(0)) : Self.bytes(value(0))
            let result = try cipher.process(data, encrypt: !decrypt)
            if method.contains("ToBase64") || method.contains("EncodeBase64") || method == "aesEncodeArgsBase64Str" || method == "tripleDESEncodeArgsBase64Str" {
                let encoded = result.base64EncodedString()
                return method.hasSuffix("ByteArray") ? Data(encoded.utf8) : encoded
            }
            return method.hasSuffix("ByteArray") ? result : String(decoding: result, as: UTF8.self)
        }
    }

    private func register(_ object: any JsCryptoObject) -> [String: Any] {
        let id = objects.count
        objects[id] = object
        return ["__legadoCrypto": id, "methods": object.methods]
    }

    static func bytes(_ value: Any?, charset: String = "UTF-8") throws -> Data {
        if let string = value as? String { return try JavaHostEncoding.encode(string, charset: charset) }
        return try JavaHostEncoding.bytes(value)
    }

    static func optionalBytes(_ value: Any?) throws -> Data? {
        guard let value, !(value is NSNull) else { return nil }
        return try bytes(value)
    }

    static func ciphertext(_ value: Any?) throws -> Data {
        guard let string = value as? String else { return try bytes(value) }
        if !string.isEmpty, string.count % 2 == 0,
           string.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil { return try JavaHostEncoding.hex(string) }
        return try JavaHostEncoding.base64(string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"), flags: 0)
    }

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    static func random(_ count: Int) throws -> Data {
        guard count >= 0, count <= 65_536 else { throw JsEngineError.exception("Invalid random byte count") }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw JsEngineError.exception("Secure random generation failed: \(status)") }
        return Data(bytes)
    }

    static func digest(_ data: Data, algorithm: String) throws -> Data {
        switch algorithm.uppercased().replacingOccurrences(of: "-", with: "") {
        case "MD5": return Data(Insecure.MD5.hash(data: data))
        case "SHA1": return Data(Insecure.SHA1.hash(data: data))
        case "SHA256": return Data(SHA256.hash(data: data))
        case "SHA384": return Data(SHA384.hash(data: data))
        case "SHA512": return Data(SHA512.hash(data: data))
        case "SHA224":
            var bytes = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
            data.withUnsafeBytes { _ = CC_SHA224($0.baseAddress, CC_LONG(data.count), &bytes) }
            return Data(bytes)
        default: throw JsEngineError.exception("Unsupported digest algorithm: \(algorithm)")
        }
    }

    private static func hmac(_ data: Data, algorithm: String, key: Data) throws -> Data {
        let kind: CCHmacAlgorithm
        let count: Int
        switch algorithm.uppercased().replacingOccurrences(of: "-", with: "") {
        case "HMACMD5": kind = CCHmacAlgorithm(kCCHmacAlgMD5); count = 16
        case "HMACSHA1": kind = CCHmacAlgorithm(kCCHmacAlgSHA1); count = 20
        case "HMACSHA224": kind = CCHmacAlgorithm(kCCHmacAlgSHA224); count = 28
        case "HMACSHA256": kind = CCHmacAlgorithm(kCCHmacAlgSHA256); count = 32
        case "HMACSHA384": kind = CCHmacAlgorithm(kCCHmacAlgSHA384); count = 48
        case "HMACSHA512": kind = CCHmacAlgorithm(kCCHmacAlgSHA512); count = 64
        default: throw JsEngineError.exception("Unsupported HMAC algorithm: \(algorithm)")
        }
        var output = [UInt8](repeating: 0, count: count)
        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { CCHmac(kind, keyBytes.baseAddress, key.count, $0.baseAddress, data.count, &output) }
        }
        return Data(output)
    }
}

final class JsSymmetricCrypto: JsCryptoObject {
    let methods = ["encrypt", "encryptHex", "encryptBase64", "decrypt", "decryptStr", "setIv", "setKey", "getSecretKey", "getAlgorithm"]
    private let transformation: String
    private let algorithm: CCAlgorithm
    private let blockSize: Int
    private let mode: CCMode
    private let padding: CCPadding
    private let zeroPadding: Bool
    private var key: Data
    private var iv: Data?

    init(transformation: String, key: Data?, iv: Data?) throws {
        self.transformation = transformation
        let parts = transformation.uppercased().split(separator: "/").map(String.init)
        guard parts.count == 1 || parts.count == 3 else { throw JsEngineError.exception("Invalid cipher transformation: \(transformation)") }
        let lengths: [Int]
        switch parts.first {
        case "AES": algorithm = CCAlgorithm(kCCAlgorithmAES); blockSize = 16; lengths = [16, 24, 32]
        case "DES": algorithm = CCAlgorithm(kCCAlgorithmDES); blockSize = 8; lengths = [8]
        case "DESEDE", "TRIPLEDES": algorithm = CCAlgorithm(kCCAlgorithm3DES); blockSize = 8; lengths = [24]
        default: throw JsEngineError.exception("Unsupported cipher: \(transformation)")
        }
        self.key = try key ?? JavaHostCrypto.random(lengths[0])
        guard lengths.contains(self.key.count) else { throw JsEngineError.exception("Invalid key length for \(parts[0]): \(self.key.count)") }
        let modes = ["ECB": kCCModeECB, "CBC": kCCModeCBC, "CTR": kCCModeCTR, "CFB": kCCModeCFB, "CFB8": kCCModeCFB8, "OFB": kCCModeOFB]
        guard let mode = modes[parts.count == 1 ? "ECB" : parts[1]] else { throw JsEngineError.exception("Unsupported cipher mode: \(transformation)") }
        self.mode = CCMode(mode)
        let pad = parts.count == 1 ? "PKCS5PADDING" : parts[2]
        guard ["PKCS5PADDING", "PKCS7PADDING", "NOPADDING", "ZEROPADDING"].contains(pad) else {
            throw JsEngineError.exception("Unsupported cipher padding: \(transformation)")
        }
        padding = CCPadding(pad.hasPrefix("PKCS") ? ccPKCS7Padding : ccNoPadding)
        zeroPadding = pad == "ZEROPADDING"
        self.iv = iv?.isEmpty == false ? iv : nil
        if self.mode != CCMode(kCCModeECB), let iv = self.iv, iv.count != blockSize { throw JsEngineError.exception("Invalid cipher IV length") }
    }

    func call(_ method: String, arguments: [Any]) throws -> Any? {
        let value = arguments.first
        let charset = arguments.dropFirst().first as? String ?? "UTF-8"
        switch method {
        case "setIv":
            let value = try JavaHostCrypto.bytes(value)
            guard value.count == blockSize else { throw JsEngineError.exception("Invalid cipher IV length") }
            iv = value; return nil
        case "setKey":
            let updated = try JsSymmetricCrypto(transformation: transformation, key: JavaHostCrypto.bytes(value), iv: iv)
            key = updated.key; return nil
        case "getAlgorithm": return transformation
        case "getSecretKey": return ["__legadoKeyBytes": Array(key), "algorithm": transformation.components(separatedBy: "/")[0], "format": "RAW"]
        case "encrypt", "encryptHex", "encryptBase64":
            let result = try process(JavaHostCrypto.bytes(value, charset: charset), encrypt: true)
            if method == "encryptHex" { return JavaHostCrypto.hex(result) }
            if method == "encryptBase64" { return result.base64EncodedString() }
            return result
        case "decrypt", "decryptStr":
            let result = try process(JavaHostCrypto.ciphertext(value), encrypt: false)
            return method == "decryptStr" ? try JavaHostEncoding.decode(result, charset: charset) : result
        default: throw JsEngineError.exception("Unsupported symmetric crypto method: \(method)")
        }
    }

    func process(_ data: Data, encrypt: Bool) throws -> Data {
        let effectiveIV: Data?
        if mode != CCMode(kCCModeECB), iv == nil {
            guard encrypt else { throw JsEngineError.exception("Cipher decryption requires an IV") }
            effectiveIV = try JavaHostCrypto.random(blockSize)
        } else { effectiveIV = iv }
        var input = data
        if encrypt && zeroPadding && input.count % blockSize != 0 { input.append(Data(repeating: 0, count: blockSize - input.count % blockSize)) }
        var cryptor: CCCryptorRef?
        let initialization = key.withUnsafeBytes { keyBytes in
            (effectiveIV ?? Data()).withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), mode, algorithm, padding,
                    mode == CCMode(kCCModeECB) ? nil : ivBytes.baseAddress, keyBytes.baseAddress, key.count,
                    nil, 0, 0, CCModeOptions(mode == CCMode(kCCModeCTR) ? kCCModeOptionCTR_BE : 0), &cryptor)
            }
        }
        guard initialization == kCCSuccess, let cryptor else { throw JsEngineError.exception("Cipher initialization failed: \(initialization)") }
        defer { CCCryptorRelease(cryptor) }
        var output = [UInt8](repeating: 0, count: CCCryptorGetOutputLength(cryptor, input.count, true) + blockSize)
        let capacity = output.count
        var written = 0
        let update = input.withUnsafeBytes { CCCryptorUpdate(cryptor, $0.baseAddress, input.count, &output, capacity, &written) }
        guard update == kCCSuccess else { throw JsEngineError.exception("Cipher operation failed: \(update)") }
        var finalCount = 0
        let final = output.withUnsafeMutableBytes { CCCryptorFinal(cryptor, $0.baseAddress?.advanced(by: written), capacity - written, &finalCount) }
        guard final == kCCSuccess else { throw JsEngineError.exception("Cipher finalization failed: \(final)") }
        var result = Data(output.prefix(written + finalCount))
        if !encrypt && zeroPadding { while result.last == 0 { result.removeLast() } }
        return result
    }
}
