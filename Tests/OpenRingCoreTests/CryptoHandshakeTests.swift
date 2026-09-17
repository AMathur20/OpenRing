import Testing
import Foundation
@testable import OpenRingCore

@Suite("Cryptographic Handshake Tests")
struct CryptoHandshakeTests {
    
    @Test("Random 16-byte key generation")
    func testKeyGeneration() throws {
        let key1 = try OuraAuthCrypto.generateRandomKey()
        let key2 = try OuraAuthCrypto.generateRandomKey()
        
        #expect(key1.count == 16)
        #expect(key2.count == 16)
        #expect(key1 != key2)
    }
    
    @Test("AES-128-ECB PKCS#7 encryption and decryption round-trip")
    func testAesRoundTrip() throws {
        let key = Data((1...16).map { UInt8($0) })
        let nonce = Data([
            0x10, 0x20, 0x30, 0x40, 0x50,
            0x60, 0x70, 0x80, 0x90, 0xA0,
            0xB0, 0xC0, 0xD0, 0xE0, 0xF0
        ]) // 15 bytes
        
        #expect(nonce.count == 15)
        
        let ciphertext = try OuraAuthCrypto.encryptNonce(nonce, key: key)
        #expect(ciphertext.count == 16)
        
        let decrypted = try OuraAuthCrypto.decryptCiphertext(ciphertext, key: key)
        #expect(decrypted == nonce)
    }
    
    @Test("Validation of invalid key and nonce lengths")
    func testCryptoLengthValidation() {
        let invalidKey = Data([0x01, 0x02, 0x03]) // 3 bytes
        let validNonce = Data(repeating: 0x0A, count: 15)
        
        #expect(throws: OuraAuthCrypto.CryptoError.self) {
            _ = try OuraAuthCrypto.encryptNonce(validNonce, key: invalidKey)
        }
        
        let validKey = Data(repeating: 0x01, count: 16)
        let emptyNonce = Data()
        #expect(throws: OuraAuthCrypto.CryptoError.self) {
            _ = try OuraAuthCrypto.encryptNonce(emptyNonce, key: validKey)
        }
    }
    
    @Test("AuthResult decoding")
    func testAuthResultStatus() {
        #expect(AuthResult(byte: 0x00) == .success)
        #expect(AuthResult(byte: 0x00).isSuccess == true)
        #expect(AuthResult(byte: 0x01) == .authenticationError)
        #expect(AuthResult(byte: 0x02) == .inFactoryReset)
        #expect(AuthResult(byte: 0x03) == .notOriginalOnboardedDevice)
        #expect(AuthResult(byte: 0x99) == .unknown)
    }
}

