import Testing
import Foundation
@testable import OpenRingCore

@Suite("Protocol & Packet Framing Tests")
struct ProtocolAndFramingTests {
    
    @Test("Packet round-trip encode and decode")
    func testPacketRoundTrip() {
        let originalPayload = Data([0x01, 0x02, 0x03, 0x04])
        let packet = Packet(tag: 0x5D, payload: originalPayload)
        let encoded = packet.encode()
        
        #expect(encoded.count == 6)
        #expect(encoded[0] == 0x5D)
        #expect(encoded[1] == 4)
        
        let parsed = Packet.parse(from: encoded)
        #expect(parsed != nil)
        #expect(parsed?.tag == 0x5D)
        #expect(parsed?.payload == originalPayload)
    }
    
    @Test("Parse multiple concatenated packets in one notification buffer")
    func testParseMany() {
        let p1 = Packet(tag: 0x46, payload: Data([0x01, 0x02]))
        let p2 = Packet(tag: 0x5D, payload: Data([0x03, 0x04]))
        var combined = Data()
        combined.append(p1.encode())
        combined.append(p2.encode())
        
        let parsedList = Packet.parseMany(from: combined)
        #expect(parsedList.count == 2)
        #expect(parsedList[0].tag == 0x46)
        #expect(parsedList[1].tag == 0x5D)
    }
    
    @Test("PacketReassemblyEngine handles fragmented chunks across BLE packets")
    func testReassemblyEngineFragmentation() async {
        let engine = PacketReassemblyEngine()
        let completePayload = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
        let fullPacket = Packet(tag: 0x5D, payload: completePayload)
        let encoded = fullPacket.encode() // [0x5D, 0x05, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        
        // Split across 2 chunks: 3 bytes first, 4 bytes second
        let chunk1 = encoded.prefix(3)
        let chunk2 = encoded.suffix(from: 3)
        
        let packets1 = await engine.ingestChunk(chunk1)
        #expect(packets1.isEmpty)
        
        let packets2 = await engine.ingestChunk(chunk2)
        #expect(packets2.count == 1)
        #expect(packets2[0].tag == 0x5D)
        #expect(packets2[0].payload == completePayload)
    }
    
    @Test("Request builders emit valid protocol byte shapes")
    func testRequestBuilders() {
        #expect(OuraProtocolRequests.firmware() == Data([0x08, 0x03, 0x00, 0x00, 0x00]))
        #expect(OuraProtocolRequests.battery() == Data([0x0C, 0x00]))
        #expect(OuraProtocolRequests.authNonce() == Data([0x2F, 0x01, 0x2B]))
        
        let dummyCiphertext = Data(repeating: 0xAB, count: 16)
        let authReq = OuraProtocolRequests.authenticate(ciphertext: dummyCiphertext)
        #expect(authReq.count == 19)
        #expect(authReq[0] == 0x2F)
        #expect(authReq[1] == 17)
        #expect(authReq[2] == 0x2D)
    }
}

