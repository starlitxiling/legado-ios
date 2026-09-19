import XCTest
@testable import LegadoCore

final class JavaHostCryptoTests: XCTestCase {
    func testDigestAndHMACVectors() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("java.md5Encode16('abc')") as? String, "3cd24fb0d6963f7d")
        XCTAssertEqual(try engine.evaluateScript("java.digestBase64Str('abc','SHA-256')") as? String, "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
        XCTAssertEqual(try engine.evaluateScript("java.HMacHex('The quick brown fox jumps over the lazy dog','HmacSHA256','key')") as? String,
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
        XCTAssertEqual(try engine.evaluateScript("java.HMacBase64('The quick brown fox jumps over the lazy dog','HmacSHA256','key')") as? String,
            "97yD9DBThCSxMpjmqm+xQ+9NWaFJRhdZl0edvC0aPNg=")
    }

    func testAESKnownVectorWithByteKeysAndChainedIV() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("""
        var cipher=java.createSymmetricCrypto('AES/ECB/NoPadding',java.hexDecodeToByteArray('000102030405060708090a0b0c0d0e0f'));
        cipher.encryptHex(java.hexDecodeToByteArray('00112233445566778899aabbccddeeff'))
        """) as? String, "69c4e0d86a7b0430d8cdb78070b4c55a")
        XCTAssertEqual(try engine.evaluateScript("""
        var cipher=java.createSymmetricCrypto('AES/CBC/PKCS5Padding','1234567890123456').setIv(java.strToBytes('1234567890123456'));
        cipher.decryptStr(cipher.encryptBase64('hello'))
        """) as? String, "hello")
    }

    func testSymmetricConstructorOverloadsAndPadding() throws {
        let engine = JsEngine()
        for key in ["'1234567890123456'", "java.strToBytes('1234567890123456')"] {
            for iv in ["'1234567890123456'", "java.strToBytes('1234567890123456')"] {
                XCTAssertEqual(try engine.evaluateScript("java.createSymmetricCrypto('AES/CBC/PKCS5Padding',\(key),\(iv)).encryptBase64('hello')") as? String, "ObBxtb9plyPvM6ZEdBv6MQ==")
            }
        }
        XCTAssertEqual(try engine.evaluateScript("""
        var cipher=java.createSymmetricCrypto('AES/ECB/ZeroPadding','1234567890123456').setKey(java.strToBytes('6543210987654321'));
        java.bytesToStr(cipher.decrypt(cipher.encrypt('hello')))
        """) as? String, "hello")
        XCTAssertThrowsError(try engine.evaluateScript("java.createSymmetricCrypto('AES/CBC/PKCS5Padding','1234567890123456').decrypt('ObBxtb9plyPvM6ZEdBv6MQ==')"))
    }

    func testCryptoJSIsAvailableBeforeLibraryInitialization() throws {
        let engine = JsEngine()
        engine.libraryInitializer = { context in context.evaluateScript("var hash=CryptoJS.SHA256('abc').toString();") }
        XCTAssertEqual(try engine.evaluateScript("hash") as? String, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try engine.evaluateScript("CryptoJS.lib.WordArray.random(16).sigBytes") as? Double, 16)
        XCTAssertEqual(try engine.evaluateScript("CryptoJS.AES.decrypt(CryptoJS.AES.encrypt('hello','password').toString(),'password').toString(CryptoJS.enc.Utf8)") as? String, "hello")
        XCTAssertThrowsError(try engine.evaluateScript("crypto.getRandomValues(new Uint8Array(65537))"))
    }

    func testLegacyAESMethodsMatchFixedCiphertextAndKotlinQuirks() throws {
        let engine = JsEngine(bindings: ["key": "1234567890123456", "iv": "1234567890123456",
            "ciphertext": "ObBxtb9plyPvM6ZEdBv6MQ==", "transformation": "AES/CBC/PKCS5Padding"])
        for method in ["aesDecodeToString", "aesBase64DecodeToString", "aesEncodeToString"] {
            XCTAssertEqual(try engine.evaluateScript("java.\(method)(ciphertext,key,transformation,iv)") as? String, "hello", method)
        }
        for method in ["aesDecodeToByteArray", "aesBase64DecodeToByteArray"] {
            XCTAssertEqual(try engine.evaluateScript("java.bytesToStr(java.\(method)(ciphertext,key,transformation,iv))") as? String, "hello", method)
        }
        XCTAssertEqual(try engine.evaluateScript("java.aesEncodeToBase64String('hello',key,transformation,iv)") as? String, "ObBxtb9plyPvM6ZEdBv6MQ==")
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr(java.aesEncodeToBase64ByteArray('hello',key,transformation,iv))") as? String, "ObBxtb9plyPvM6ZEdBv6MQ==")
        XCTAssertEqual(try engine.evaluateScript("Array.from(java.aesEncodeToByteArray('hello',key,transformation,iv)).map(x=>x.toString(16).padStart(2,'0')).join('')") as? String,
            "39b071b5bf699723ef33a644741bfa31")
        XCTAssertEqual(try engine.evaluateScript("java.aesDecodeArgsBase64Str(ciphertext,java.base64Encode(key),'CBC','PKCS5Padding',java.base64Encode(iv))") as? String, "hello")
        XCTAssertEqual(try engine.evaluateScript("java.aesEncodeArgsBase64Str('hello',key,'CBC','PKCS5Padding',iv)") as? String, "ObBxtb9plyPvM6ZEdBv6MQ==")
    }

    func testDESAndTripleDESLegacyMethods() throws {
        let engine = JsEngine(bindings: ["key": "12345678", "iv": "12345678", "ciphertext": "sxqYZRqwq+Q="])
        for method in ["desDecodeToString", "desBase64DecodeToString"] {
            XCTAssertEqual(try engine.evaluateScript("java.\(method)(ciphertext,key,'DES/CBC/PKCS5Padding',iv)") as? String, "hello")
        }
        XCTAssertEqual(try engine.evaluateScript("java.desEncodeToBase64String('hello',key,'DES/CBC/PKCS5Padding',iv)") as? String, "sxqYZRqwq+Q=")
        XCTAssertEqual(try engine.evaluateScript("java.desEncodeToString('hello',key,'DES/CBC/PKCS5Padding',iv)") as? String,
            String(decoding: Data(base64Encoded: "sxqYZRqwq+Q=")!, as: UTF8.self))
        engine.bindings["key"] = "123456789012345678901234"
        engine.bindings["ciphertext"] = "602EILBy8Hg="
        XCTAssertEqual(try engine.evaluateScript("java.tripleDESDecodeStr(ciphertext,key,'CBC','PKCS5Padding',iv)") as? String, "hello")
        XCTAssertEqual(try engine.evaluateScript("java.tripleDESDecodeArgsBase64Str(ciphertext,java.base64Encode(key),'CBC','PKCS5Padding',iv)") as? String, "hello")
        XCTAssertEqual(try engine.evaluateScript("java.tripleDESEncodeBase64Str('hello',key,'CBC','PKCS5Padding',iv)") as? String, "602EILBy8Hg=")
        XCTAssertEqual(try engine.evaluateScript("java.tripleDESEncodeArgsBase64Str('hello',java.base64Encode(key),'CBC','PKCS5Padding',iv)") as? String, "602EILBy8Hg=")
    }

    func testRSAImportsOpenSSLKeysAndDecryptsExternalCiphertext() throws {
        let engine = try rsaEngine()
        XCTAssertEqual(try engine.evaluateScript("""
        var rsa=java.createAsymmetricCrypto('RSA/ECB/PKCS1Padding').setPrivateKey(privateKey).setPublicKey(publicKey);
        rsa.decryptStr(ciphertext,false)
        """) as? String, "hello")
        XCTAssertEqual(try engine.evaluateScript("""
        var rsa=java.createAsymmetricCrypto('RSA').setPrivateKey(privateKey).setPublicKey(publicKey);
        rsa.decryptStr(rsa.encryptBase64('hello',false))
        """) as? String, "hello")
        XCTAssertEqual(try engine.evaluateScript("""
        var rsa=java.createAsymmetricCrypto('RSA').setPrivateKey(privateKey).setPublicKey(publicKey);
        rsa.decryptStr(rsa.encrypt('long'.repeat(100)),false)
        """) as? String, String(repeating: "long", count: 100))
    }

    func testRSASignatureMatchesOpenSSLAndRejectsChangedMessage() throws {
        let engine = try rsaEngine()
        let signature = try fixture("rsa-sha256-signature.bin")
        XCTAssertEqual(try engine.evaluateScript("java.createSign('SHA256withRSA').setPrivateKey(privateKey).signHex('hello')") as? String,
            signature.map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(try engine.evaluateScript("java.createSign('SHA256withRSA').setPublicKey(publicKey).verify(java.strToBytes('hello'),signature)") as? Bool, true)
        XCTAssertEqual(try engine.evaluateScript("java.createSign('SHA256withRSA').setPublicKey(publicKey).verify(java.strToBytes('changed'),signature)") as? Bool, false)
        XCTAssertEqual(try engine.evaluateScript("""
        var sign=java.createSign('SHA256withRSA');
        sign.verify(java.strToBytes('hello'),sign.sign('hello'))
        """) as? Bool, true)
    }

    func testGeneratedKeysAreExportableAndInvalidCryptoInputsThrow() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("""
        var first=java.createAsymmetricCrypto('RSA'), second=java.createAsymmetricCrypto('RSA');
        second.setPrivateKey(first.getPrivateKey().getEncoded()).setPublicKey(java.base64DecodeToByteArray(first.getPublicKeyBase64()));
        second.decryptStr(first.encryptHex('hello'),false)
        """) as? String, "hello")
        XCTAssertEqual(try engine.evaluateScript("java.createSymmetricCrypto('AES',null).getSecretKey().getEncoded().length") as? Double, 16)
        XCTAssertThrowsError(try engine.evaluateScript("java.createSymmetricCrypto('AES','bad')"))
        XCTAssertThrowsError(try engine.evaluateScript("java.createSymmetricCrypto('AES/ECB/NoPadding','1234567890123456').encrypt('short')"))
        XCTAssertThrowsError(try engine.evaluateScript("java.createAsymmetricCrypto('RSA').setPrivateKey([48,255])"))
    }

    private func rsaEngine() throws -> JsEngine {
        try JsEngine(bindings: ["privateKey": Array(fixture("rsa-private.pk8")), "publicKey": Array(fixture("rsa-public.der")),
            "signature": Array(fixture("rsa-sha256-signature.bin")), "ciphertext": Array(fixture("rsa-ciphertext.bin"))])
    }

    private func fixture(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/crypto")
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }
}
