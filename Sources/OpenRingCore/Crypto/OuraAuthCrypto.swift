import Foundation
import CommonCrypto
import Security

/// Authentication status codes returned by the ring after an authentication attempt.
public enum AuthResult: UInt8, Sendable, Equatable {
    case success = 0x00
    case authenticationError = 0x01
    case inFactoryReset = 0x02
    case notOriginalOnboardedDevice = 0x03
    case unknown = 0xFF
    
    public init(byte: UInt8) {
        switch byte {
        case 0x00: self = .success
        case 0x01: self = .authenticationError
        case 0x02: self = .inFactoryReset
        case 0x03: self = .notOriginalOnboardedDevice
        default: self = .unknown
        }
    }
    
    public var isSuccess: Bool {
        return self == .success
    }
}

/// Cryptographic engine implementing the Oura Ring App-Level Authentication challenge-response handshake.
/// The ring challenges with a 15-byte nonce; the client encrypts it with AES-128/ECB/PKCS7
/// using a shared 16-byte key, producing a 16-byte response ciphertext block.
public enum OuraAuthCrypto {
    
    public enum CryptoError: Error, LocalizedError {
        case invalidKeyLength(expected: Int, actual: Int)
        case invalidNonceLength(actual: Int)
        case encryptionFailed(status: CCCryptorStatus)
        case decryptionFailed(status: CCCryptorStatus)
        case randomGenerationFailed
        
        public var errorDescription: String? {
            switch self {
            case .invalidKeyLength(let expected, let actual):
                return "Invalid AES key length: expected \(expected) bytes, received \(actual)"
            case .invalidNonceLength(let actual):
                return "Invalid nonce length: received \(actual) bytes, expected 1-15 bytes for PKCS#7 block"
            case .encryptionFailed(let status):
                return "AES encryption failed with CCCryptorStatus \(status)"
            case .decryptionFailed(let status):
                return "AES decryption failed with CCCryptorStatus \(status)"
            case .randomGenerationFailed:
                return "Failed to generate cryptographically secure random bytes"
            }
        }
    }
    
    /// Generates a cryptographically secure 16-byte random key for pairing with a factory-reset ring.
    public static func generateRandomKey() throws -> Data {
        var key = Data(count: 16)
        let status = key.withUnsafeMutableBytes { ptr -> Int32 in
            guard let baseAddress = ptr.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 16, baseAddress)
        }
        guard status == errSecSuccess else {
            throw CryptoError.randomGenerationFailed
        }
        return key
    }
    
    /// Encrypts a challenge nonce (typically 15 bytes) under the 16-byte shared key using AES-128/ECB/PKCS#7.
    /// Returns the 16-byte ciphertext to be sent back to the ring in Opcode 0x2D.
    public static func encryptNonce(_ nonce: Data, key: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw CryptoError.invalidKeyLength(expected: kCCKeySizeAES128, actual: key.count)
        }
        guard nonce.count > 0 && nonce.count < kCCBlockSizeAES128 else {
            throw CryptoError.invalidNonceLength(actual: nonce.count)
        }
        
        var outBuffer = Data(count: kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0
        
        let status = outBuffer.withUnsafeMutableBytes { outPtr in
            nonce.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyPtr.baseAddress,
                        kCCKeySizeAES128,
                        nil, // No IV in ECB mode
                        inPtr.baseAddress,
                        nonce.count,
                        outPtr.baseAddress,
                        kCCBlockSizeAES128,
                        &numBytesEncrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoError.encryptionFailed(status: status)
        }
        
        return outBuffer.prefix(numBytesEncrypted)
    }
    
    /// Decrypts a 16-byte ciphertext response block under the 16-byte key using AES-128/ECB/PKCS#7.
    /// Used by mock peripheral and testing harnesses to verify the central's authentication payload.
    public static func decryptCiphertext(_ ciphertext: Data, key: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw CryptoError.invalidKeyLength(expected: kCCKeySizeAES128, actual: key.count)
        }
        guard ciphertext.count == kCCBlockSizeAES128 else {
            throw CryptoError.invalidNonceLength(actual: ciphertext.count)
        }
        
        var outBuffer = Data(count: kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = 0
        
        let status = outBuffer.withUnsafeMutableBytes { outPtr in
            ciphertext.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyPtr.baseAddress,
                        kCCKeySizeAES128,
                        nil, // No IV in ECB mode
                        inPtr.baseAddress,
                        ciphertext.count,
                        outPtr.baseAddress,
                        kCCBlockSizeAES128,
                        &numBytesDecrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoError.decryptionFailed(status: status)
        }
        
        return outBuffer.prefix(numBytesDecrypted)
    }
}

