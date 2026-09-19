Public test-only RSA key pair and vectors generated with OpenSSL 3.6.4.

The private key is an intentionally published fixture and must never be used outside tests. The message for both signature and ciphertext is the UTF-8 string `hello`. Private key: PKCS#8 DER. Public key: SubjectPublicKeyInfo DER. Signature: SHA-256 with RSA PKCS#1 v1.5. Ciphertext: RSA PKCS#1 v1.5.
