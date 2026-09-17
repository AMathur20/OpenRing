import Foundation
import OpenRingCore
import OpenRingMock

@MainActor
func runAllTests() async {
    print("==================================================")
    print("      OpenRing Swift 6 Core & Mock Test Suite     ")
    print("==================================================")
    
    var passedCount = 0
    var failedCount = 0
    
    func runTest(_ name: String, block: () async throws -> Void) async {
        do {
            try await block()
            print("  ✅ [PASS] \(name)")
            passedCount += 1
        } catch {
            print("  ❌ [FAIL] \(name): \(error.localizedDescription)")
            failedCount += 1
        }
    }
    
    // MARK: - Protocol & Framing Tests
    print("\n--- [1] Protocol & Packet Framing ---")
    
    await runTest("Packet round-trip encode and decode") {
        let originalPayload = Data([0x01, 0x02, 0x03, 0x04])
        let packet = Packet(tag: 0x5D, payload: originalPayload)
        let encoded = packet.encode()
        
        assert(encoded.count == 6, "Expected encoded count to be 6")
        assert(encoded[0] == 0x5D, "Expected tag 0x5D")
        assert(encoded[1] == 4, "Expected length 4")
        
        guard let parsed = Packet.parse(from: encoded) else {
            fatalError("Failed to parse packet")
        }
        assert(parsed.tag == 0x5D, "Parsed tag mismatch")
        assert(parsed.payload == originalPayload, "Payload mismatch")
    }
    
    await runTest("Parse multiple concatenated packets in one notification buffer") {
        let p1 = Packet(tag: 0x46, payload: Data([0x01, 0x02]))
        let p2 = Packet(tag: 0x5D, payload: Data([0x03, 0x04]))
        var combined = Data()
        combined.append(p1.encode())
        combined.append(p2.encode())
        
        let parsedList = Packet.parseMany(from: combined)
        assert(parsedList.count == 2, "Expected 2 packets")
        assert(parsedList[0].tag == 0x46, "Packet 1 tag mismatch")
        assert(parsedList[1].tag == 0x5D, "Packet 2 tag mismatch")
    }
    
    await runTest("PacketReassemblyEngine handles fragmented chunks across BLE packets") {
        let engine = PacketReassemblyEngine()
        let completePayload = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
        let fullPacket = Packet(tag: 0x5D, payload: completePayload)
        let encoded = fullPacket.encode()
        
        let chunk1 = encoded.prefix(3)
        let chunk2 = encoded.suffix(from: 3)
        
        let packets1 = await engine.ingestChunk(chunk1)
        assert(packets1.isEmpty, "Chunk 1 should yield 0 packets")
        
        let packets2 = await engine.ingestChunk(chunk2)
        assert(packets2.count == 1, "Chunk 2 should complete 1 packet")
        assert(packets2[0].tag == 0x5D, "Tag should be 0x5D")
        assert(packets2[0].payload == completePayload, "Payload should match")
    }
    
    await runTest("Request builders emit valid protocol byte shapes") {
        assert(OuraProtocolRequests.firmware() == Data([0x08, 0x03, 0x00, 0x00, 0x00]))
        assert(OuraProtocolRequests.battery() == Data([0x0C, 0x00]))
        assert(OuraProtocolRequests.authNonce() == Data([0x2F, 0x01, 0x2B]))
        
        let dummyCiphertext = Data(repeating: 0xAB, count: 16)
        let authReq = OuraProtocolRequests.authenticate(ciphertext: dummyCiphertext)
        assert(authReq.count == 19)
        assert(authReq[0] == 0x2F)
        assert(authReq[1] == 17)
        assert(authReq[2] == 0x2D)
    }
    
    // MARK: - Cryptographic Handshake Tests
    print("\n--- [2] Cryptographic Handshake (AES-128-ECB PKCS#7) ---")
    
    await runTest("Random 16-byte key generation") {
        let key1 = try OuraAuthCrypto.generateRandomKey()
        let key2 = try OuraAuthCrypto.generateRandomKey()
        assert(key1.count == 16, "Key 1 must be 16 bytes")
        assert(key2.count == 16, "Key 2 must be 16 bytes")
        assert(key1 != key2, "Generated keys must be distinct")
    }
    
    await runTest("AES-128-ECB PKCS#7 encryption and decryption round-trip") {
        let key = Data((1...16).map { UInt8($0) })
        let nonce = Data([
            0x10, 0x20, 0x30, 0x40, 0x50,
            0x60, 0x70, 0x80, 0x90, 0xA0,
            0xB0, 0xC0, 0xD0, 0xE0, 0xF0
        ]) // 15 bytes
        assert(nonce.count == 15)
        
        let ciphertext = try OuraAuthCrypto.encryptNonce(nonce, key: key)
        assert(ciphertext.count == 16, "Ciphertext must be 16 bytes")
        
        let decrypted = try OuraAuthCrypto.decryptCiphertext(ciphertext, key: key)
        assert(decrypted == nonce, "Decrypted nonce must match original")
    }
    
    await runTest("Validation of invalid key and nonce lengths") {
        let invalidKey = Data([0x01, 0x02, 0x03])
        let validNonce = Data(repeating: 0x0A, count: 15)
        var caughtError = false
        do {
            _ = try OuraAuthCrypto.encryptNonce(validNonce, key: invalidKey)
        } catch {
            caughtError = true
        }
        assert(caughtError, "Should throw on invalid key length")
    }
    
    await runTest("AuthResult status decoding") {
        assert(AuthResult(byte: 0x00) == .success)
        assert(AuthResult(byte: 0x00).isSuccess == true)
        assert(AuthResult(byte: 0x01) == .authenticationError)
        assert(AuthResult(byte: 0x02) == .inFactoryReset)
        assert(AuthResult(byte: 0x03) == .notOriginalOnboardedDevice)
        assert(AuthResult(byte: 0x99) == .unknown)
    }
    
    // MARK: - Event Decoder Tests
    print("\n--- [3] History Event Decoders ---")
    
    await runTest("Decode HRV Event (Tag 0x5D)") {
        var payload = Data([0x80, 0x1A, 0x06, 0x00]) // timestamp: 400000 deciseconds
        payload.append(contentsOf: [54, 62, 52, 68])
        
        let packet = Packet(tag: 0x5D, payload: payload)
        let event = RingEvent.from(packet: packet)
        
        assert(event.tag == 0x5D)
        assert(event.name == "hrv_event")
        assert(event.timestampDeciseconds == 400000)
        
        if case .hrv(let samples) = event.payload {
            assert(samples.count == 2)
            assert(samples[0].averageHeartRateBpm == 54)
            assert(samples[0].averageRmssdMs == 62)
            assert(samples[1].averageHeartRateBpm == 52)
            assert(samples[1].averageRmssdMs == 68)
        } else {
            fatalError("Expected .hrv payload")
        }
    }
    
    await runTest("Decode Temperature Event (Tag 0x46)") {
        var payload = Data([0x00, 0x00, 0x00, 0x00])
        var t1: Int16 = 3350
        var t2: Int16 = 3412
        withUnsafeBytes(of: &t1) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: &t2) { payload.append(contentsOf: $0) }
        
        let packet = Packet(tag: 0x46, payload: payload)
        let event = RingEvent.from(packet: packet)
        
        assert(event.name == "temp_event")
        if case .temperature(let temps) = event.payload {
            assert(temps.count == 2)
            assert(temps[0] == 33.5)
            assert(temps[1] == 34.12)
        } else {
            fatalError("Expected .temperature payload")
        }
    }
    
    await runTest("Decode Sleep Phase Hypnogram (Tag 0x4B)") {
        let payload = Data([0x00, 0x00, 0x00, 0x00, 0xE4])
        let packet = Packet(tag: 0x4B, payload: payload)
        let event = RingEvent.from(packet: packet)
        
        assert(event.name == "sleep_phase_info")
        if case .sleepPhases(let stages) = event.payload {
            assert(stages.count == 4)
            assert(stages[0] == .deep)
            assert(stages[1] == .light)
            assert(stages[2] == .rem)
            assert(stages[3] == .awake)
        } else {
            fatalError("Expected .sleepPhases payload")
        }
    }
    
    // MARK: - DSP Math Tests
    print("\n--- [4] Deterministic DSP & Readiness Algorithm ---")
    
    await runTest("rMSSD computation on synthetic IBI series") {
        let ibiSeries: [Double] = [
            1000.0, 1020.0, 990.0, 1015.0, 980.0, 1030.0, 995.0, 1010.0
        ]
        let rmssd = SignalProcessor.computeRmssd(ibiSeries: ibiSeries)
        assert(rmssd != nil)
        if let val = rmssd {
            assert(val > 20.0 && val < 50.0, "rMSSD should be in reasonable resting range")
        }
    }
    
    await runTest("Artifact filtering in rMSSD computation") {
        let dirtySeries: [Double] = [
            1000.0, 1020.0, 150.0, 2500.0, 1010.0, 990.0
        ]
        let rmssd = SignalProcessor.computeRmssd(ibiSeries: dirtySeries)
        assert(rmssd != nil, "Artifacts should be filtered without crashing")
    }
    
    await runTest("Exponential Moving Average 14-day update") {
        let day1 = SignalProcessor.updateExponentialMovingAverage(currentBaseline: nil, newDailyValue: 50.0)
        assert(day1 == 50.0)
        
        let day2 = SignalProcessor.updateExponentialMovingAverage(currentBaseline: day1, newDailyValue: 60.0)
        assert(day2 > 50.0 && day2 < 52.0)
    }
    
    await runTest("Readiness score bounds and penalty calculation") {
        let optimalScore = SignalProcessor.computeReadinessScore(
            nightlyRhr: 50.0,
            baselineRhr: 52.0,
            nightlyHrv: 65.0,
            baselineHrv: 60.0,
            temperatureDeviationCelsius: 0.0,
            sleepEfficiencyPercent: 100.0
        )
        assert(optimalScore == 100, "Optimal readiness should be 100")
        
        let strainedScore = SignalProcessor.computeReadinessScore(
            nightlyRhr: 60.0,
            baselineRhr: 52.0,
            nightlyHrv: 36.0,
            baselineHrv: 60.0,
            temperatureDeviationCelsius: 0.65,
            sleepEfficiencyPercent: 70.0
        )
        assert(strainedScore < 75 && strainedScore >= 0, "Strained readiness should reflect penalties")
    }
    
    // MARK: - Mock Peripheral & Generator Tests
    print("\n--- [5] Virtual BLE Mock & Synthetic Stream Generator ---")
    
    await runTest("Synthetic challenge nonce is 15 bytes") {
        let generator = MockDataGenerator()
        let nonce = generator.generateAuthChallengeNonce()
        assert(nonce.count == 15)
    }
    
    await runTest("Synthetic full night stream parses through reassembly engine") {
        let generator = MockDataGenerator()
        let stream = generator.generateFullNightStream()
        assert(!stream.isEmpty)
        
        let engine = PacketReassemblyEngine()
        let events = await engine.ingestAndExtractEvents(stream)
        
        assert(events.count >= 200, "Should extract all night intervals")
        let hrvEvents = events.filter { $0.tag == 0x5D }
        let tempEvents = events.filter { $0.tag == 0x46 }
        let sleepEvents = events.filter { $0.tag == 0x4B }
        
        assert(hrvEvents.count == 84, "Expected 84 HRV 5-min intervals")
        assert(tempEvents.count == 84, "Expected 84 Temperature intervals")
        assert(sleepEvents.count == 84, "Expected 84 Sleep hypnogram intervals")
    }
    
    await runTest("Challenge-response simulation round-trip") {
        let key = Data((1...16).map { UInt8($0) })
        let generator = MockDataGenerator()
        let challengeNonce = generator.generateAuthChallengeNonce()
        
        let ciphertext = try OuraAuthCrypto.encryptNonce(challengeNonce, key: key)
        assert(ciphertext.count == 16)
        
        let decrypted = try OuraAuthCrypto.decryptCiphertext(ciphertext, key: key)
        assert(decrypted == challengeNonce)
    }
    
    print("\n==================================================")
    print(" Test Results: \(passedCount) Passed, \(failedCount) Failed")
    print("==================================================")
    if failedCount > 0 {
        exit(1)
    }
}

Task {
    await runAllTests()
    exit(0)
}

RunLoop.main.run()

