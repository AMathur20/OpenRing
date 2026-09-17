import Testing
import Foundation
@testable import OpenRingCore

@Suite("History Event Decoder Tests")
struct EventDecoderTests {
    
    @Test("Decode HRV Event (Tag 0x5D)")
    func testDecodeHrv() {
        // [Timestamp: 4 bytes] + [HR: 54, RMSSD: 62], [HR: 52, RMSSD: 68]
        var payload = Data([0x80, 0x1A, 0x06, 0x00]) // timestamp: 400000 deciseconds
        payload.append(contentsOf: [54, 62, 52, 68])
        
        let packet = Packet(tag: 0x5D, payload: payload)
        let event = RingEvent.from(packet: packet)
        
        #expect(event.tag == 0x5D)
        #expect(event.name == "hrv_event")
        #expect(event.timestampDeciseconds == 400000)
        
        if case .hrv(let samples) = event.payload {
            #expect(samples.count == 2)
            #expect(samples[0].averageHeartRateBpm == 54)
            #expect(samples[0].averageRmssdMs == 62)
            #expect(samples[1].averageHeartRateBpm == 52)
            #expect(samples[1].averageRmssdMs == 68)
        } else {
            Issue.record("Expected .hrv payload")
        }
    }
    
    @Test("Decode Temperature Event (Tag 0x46)")
    func testDecodeTemperature() {
        // [Timestamp: 4 bytes] + 2 samples: 3350 centi-C (33.50 C), 3412 centi-C (34.12 C)
        var payload = Data([0x00, 0x00, 0x00, 0x00])
        var t1: Int16 = 3350
        var t2: Int16 = 3412
        withUnsafeBytes(of: &t1) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: &t2) { payload.append(contentsOf: $0) }
        
        let packet = Packet(tag: 0x46, payload: payload)
        let event = RingEvent.from(packet: packet)
        
        #expect(event.name == "temp_event")
        if case .temperature(let temps) = event.payload {
            #expect(temps.count == 2)
            #expect(temps[0] == 33.5)
            #expect(temps[1] == 34.12)
        } else {
            Issue.record("Expected .temperature payload")
        }
    }
    
    @Test("Decode Sleep Phase Hypnogram (Tag 0x4B)")
    func testDecodeSleepPhases() {
        // Byte with stages: [Deep (0), Light (1), REM (2), Awake (3)] -> 0b11_10_01_00 = 0xE4
        let payload = Data([0x00, 0x00, 0x00, 0x00, 0xE4])
        let packet = Packet(tag: 0x4B, payload: payload)
        let event = RingEvent.from(packet: packet)
        
        #expect(event.name == "sleep_phase_info")
        if case .sleepPhases(let stages) = event.payload {
            #expect(stages.count == 4)
            #expect(stages[0] == .deep)
            #expect(stages[1] == .light)
            #expect(stages[2] == .rem)
            #expect(stages[3] == .awake)
        } else {
            Issue.record("Expected .sleepPhases payload")
        }
    }
}

