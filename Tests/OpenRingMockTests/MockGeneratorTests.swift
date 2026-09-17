import Testing
import Foundation
@testable import OpenRingCore
@testable import OpenRingMock

@Suite("Mock Peripheral & Generator Tests")
struct MockGeneratorTests {
    
    @Test("Synthetic challenge nonce is 15 bytes")
    func testMockNonce() {
        let generator = MockDataGenerator()
        let nonce = generator.generateAuthChallengeNonce()
        #expect(nonce.count == 15)
    }
    
    @Test("Synthetic full night stream parses through reassembly engine")
    func testMockFullNightStreamParsing() async {
        let generator = MockDataGenerator()
        let stream = generator.generateFullNightStream()
        #expect(!stream.isEmpty)
        
        let engine = PacketReassemblyEngine()
        let events = await engine.ingestAndExtractEvents(stream)
        
        // 84 intervals of (HRV + Temp + Sleep) = 252 events (plus any time sync)
        #expect(events.count >= 200)
        
        let hrvEvents = events.filter { $0.tag == 0x5D }
        let tempEvents = events.filter { $0.tag == 0x46 }
        let sleepEvents = events.filter { $0.tag == 0x4B }
        
        #expect(hrvEvents.count == 84)
        #expect(tempEvents.count == 84)
        #expect(sleepEvents.count == 84)
    }
    
    @Test("Challenge-response simulation round-trip")
    func testMockAuthChallengeResponse() throws {
        let key = Data((1...16).map { UInt8($0) })
        let generator = MockDataGenerator()
        let challengeNonce = generator.generateAuthChallengeNonce()
        
        // Client encrypts
        let ciphertext = try OuraAuthCrypto.encryptNonce(challengeNonce, key: key)
        #expect(ciphertext.count == 16)
        
        // Mock ring peripheral decrypts & checks
        let decrypted = try OuraAuthCrypto.decryptCiphertext(ciphertext, key: key)
        #expect(decrypted == challengeNonce)
    }
}

