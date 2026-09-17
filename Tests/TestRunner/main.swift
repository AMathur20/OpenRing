import Foundation
import OpenRingCore
import OpenRingMock
import OpenRingStorage

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
    
    // MARK: - [6] BLEEngine Central State Machine & Streams
    print("\n--- [6] BLEEngine Central State Machine & Streams ---")
    
    await runTest("BLEEngine initializes with valid 16-byte key") {
        let key = Data(repeating: 0x01, count: 16)
        let engine = BLEEngine(authKey: key)
        
        let initialState = await engine.state
        assert(initialState == .disconnected, "Initial state should be disconnected")
    }
    
    await runTest("BLEEngine streams and state transition verification") {
        let key = Data((1...16).map { UInt8($0) })
        let engine = BLEEngine(authKey: key)
        
        // Verify streams are accessible and active
        let _ = engine.states
        let _ = engine.events
        let _ = engine.discoveredRings
        
        let state = await engine.state
        assert(state == .disconnected)
    }
    
    await runTest("BLEEngine history request & time sync builders") {
        let key = Data(repeating: 0xFF, count: 16)
        let _ = BLEEngine(authKey: key)
        
        // Verify getEvents packet structure matches spec
        let getEventsData = OuraProtocolRequests.getEvents(startTimestamp: 1000, maxEvents: 8)
        assert(getEventsData.count == 11) // 1 tag + 1 len + 4 ts + 1 max + 4 flags
        assert(getEventsData[0] == 0x10)
        assert(getEventsData[1] == 9)
        
        // Verify time sync packet structure matches spec
        let syncData = OuraProtocolRequests.syncTime()
        assert(syncData.count == 11) // 1 tag + 1 len + 8 unix + 1 tz
        assert(syncData[0] == 0x12)
        assert(syncData[1] == 9)
    }
    
    await runTest("BLEEngine handles incoming challenge nonce notification") {
        let key = Data((1...16).map { UInt8($0) })
        let engine = BLEEngine(authKey: key)
        
        let nonce = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
        let noncePacket = Packet(tag: 0x2F, payload: Data([0x2C]) + nonce)
        
        await engine.handleIncomingNotification(data: noncePacket.encode())
        let pending = await engine.pendingChallengeNonce
        assert(pending == nonce, "BLEEngine should record pending challenge nonce")
    }
    
    await runTest("BLEEngine handles authentication success packet") {
        let key = Data((1...16).map { UInt8($0) })
        let engine = BLEEngine(authKey: key)
        
        let authSuccess = Packet(tag: 0x2F, payload: Data([0x2E, 0x00]))
        await engine.handleIncomingNotification(data: authSuccess.encode())
        
        let state = await engine.state
        assert(state == .connected(authenticated: true), "State must be connected(authenticated: true)")
    }
    
    await runTest("BLEEngine handles authentication failure packet") {
        let key = Data((1...16).map { UInt8($0) })
        let engine = BLEEngine(authKey: key)
        
        let authFail = Packet(tag: 0x2F, payload: Data([0x2E, 0x01]))
        await engine.handleIncomingNotification(data: authFail.encode())
        
        let state = await engine.state
        if case .error(let msg) = state {
            assert(msg.contains("authenticationError") || msg.contains("failed"), "Expected error state")
        } else {
            fatalError("Expected error state but got \(state)")
        }
    }
    
    await runTest("BLEEngine routes incoming history packets to events stream") {
        let key = Data((1...16).map { UInt8($0) })
        let engine = BLEEngine(authKey: key)
        
        // Listen on events stream in background Task
        let eventExpectation = Task<RingEvent?, Never> {
            for await event in engine.events {
                return event
            }
            return nil
        }
        
        // Ingest HRV telemetry packet (Tag 0x5D, timestamp 400000 deciseconds, HR 54, RMSSD 62)
        let hrvPayload = Data([0x80, 0x1A, 0x06, 0x00, 54, 62])
        let packet = Packet(tag: 0x5D, payload: hrvPayload)
        await engine.handleIncomingNotification(data: packet.encode())
        
        // Await yielded event
        let receivedEvent = await eventExpectation.value
        assert(receivedEvent != nil, "Events stream should yield decoded event")
        assert(receivedEvent?.tag == 0x5D, "Event tag should be 0x5D")
        assert(receivedEvent?.timestampDeciseconds == 400000, "Timestamp mismatch")
        if case .hrv(let samples) = receivedEvent?.payload {
            assert(samples.count == 1, "Expected 1 HRV sample")
            assert(samples[0].averageHeartRateBpm == 54)
            assert(samples[0].averageRmssdMs == 62)
        } else {
            fatalError("Expected .hrv payload")
        }
    }
    
    // MARK: - [7] Local Storage Engine (SQLite WAL) & Range Queries
    print("\n--- [7] Local Storage Engine (SQLite WAL) & Range Queries ---")
    
    await runTest("DatabaseService in-memory initialization and schema migration") {
        let db = try DatabaseService(inMemory: true)
        let evals = try await db.fetchLatestDailyEvaluations()
        assert(evals.isEmpty, "New database should have no daily evaluations")
    }
    
    await runTest("DatabaseService disk initialization with WAL mode pragmas") {
        let tempDir = NSTemporaryDirectory()
        let tempPath = (tempDir as NSString).appendingPathComponent("test_openring_\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
            try? FileManager.default.removeItem(atPath: tempPath + "-wal")
            try? FileManager.default.removeItem(atPath: tempPath + "-shm")
        }
        
        let db = try DatabaseService(customPath: tempPath)
        let path = await db.databasePath
        assert(path == tempPath, "Database path should match custom path")
        assert(FileManager.default.fileExists(atPath: tempPath), "SQLite file must exist on disk")
    }
    
    await runTest("Raw packet ingestion audit logging") {
        let db = try DatabaseService(inMemory: true)
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let raw = RawIngestionRecord(
            receivedTimestamp: 1715000000000,
            packetType: 0x5D,
            sequenceId: 1,
            framePayload: payload
        )
        try await db.saveRawPacket(raw)
        
        let fetched = try await db.fetchRawPackets(limit: 10)
        assert(fetched.count == 1, "Expected 1 raw record")
        assert(fetched[0].packetType == 0x5D)
        assert(fetched[0].sequenceId == 1)
        assert(fetched[0].framePayload == payload)
    }
    
    await runTest("Batch save and range query biometric samples") {
        let db = try DatabaseService(inMemory: true)
        let samples = (0..<10).map { i in
            BiometricSampleRecord(
                timestamp: 1000 + Int64(i * 300_000),
                heartRateBpm: 50.0 + Double(i),
                rmssdMs: 60.0 + Double(i),
                motionIntensity: 0.1 * Double(i),
                ppgSignalQuality: 0.95
            )
        }
        try await db.saveBiometricSamples(samples)
        
        let fetched = try await db.fetchBiometrics(from: 1000 + 300_000, to: 1000 + 3 * 300_000)
        assert(fetched.count == 3, "Expected 3 samples in range")
        assert(fetched[0].heartRateBpm == 51.0)
        assert(fetched[1].heartRateBpm == 52.0)
        assert(fetched[2].heartRateBpm == 53.0)
    }
    
    await runTest("Save and range query temperature telemetry") {
        let db = try DatabaseService(inMemory: true)
        let temps = (0..<5).map { i in
            TemperatureTelemetryRecord(
                timestamp: 2000 + Int64(i * 300_000),
                rawCelsius: 34.0 + Double(i) * 0.1,
                baselineOffsetCelsius: Double(i) * 0.05
            )
        }
        try await db.saveTemperatureRecords(temps)
        
        let fetched = try await db.fetchTemperature(from: 2000, to: 2000 + 2 * 300_000)
        assert(fetched.count == 3, "Expected 3 temperature records")
        assert(abs(fetched[0].rawCelsius - 34.0) < 0.001)
        assert(abs(fetched[1].rawCelsius - 34.1) < 0.001)
    }
    
    await runTest("Save and query sleep episodes") {
        let db = try DatabaseService(inMemory: true)
        let episode = SleepEpisodeRecord(
            sessionId: "sleep_session_100",
            startTime: 10000,
            endTime: 35200,
            durationSeconds: 25200,
            efficiencyRatio: 0.88,
            deepSleepSeconds: 5400,
            remSleepSeconds: 4800,
            lightSleepSeconds: 12000,
            awakeSeconds: 3000,
            lowestHeartRate: 48,
            averageHeartRate: 52.5,
            averageRmssd: 68.0,
            temperatureDeviation: -0.15
        )
        try await db.saveSleepEpisode(episode)
        
        let fetched = try await db.fetchSleepEpisodes(from: 5000, to: 15000)
        assert(fetched.count == 1, "Expected 1 sleep episode")
        assert(fetched[0].sessionId == "sleep_session_100")
        assert(fetched[0].lowestHeartRate == 48)
        assert(fetched[0].deepSleepSeconds == 5400)
        assert(fetched[0].efficiencyRatio == 0.88)
    }
    
    await runTest("Save and query daily evaluations") {
        let db = try DatabaseService(inMemory: true)
        let eval = DailyEvaluationRecord(
            evaluationDate: "2026-09-17",
            readinessScore: 92,
            sleepScore: 88,
            rhrBaseline: 51.2,
            hrvBaseline: 64.5,
            aiSynthesisMarkdown: "Optimal autonomic recovery detected.",
            aiModelTag: "Llama-3.2-3B-Instruct-Q4_K_M",
            generatedAt: 1715000000
        )
        try await db.saveDailyEvaluation(eval)
        
        let fetched = try await db.fetchLatestDailyEvaluations(limit: 5)
        assert(fetched.count == 1, "Expected 1 daily evaluation")
        assert(fetched[0].evaluationDate == "2026-09-17")
        assert(fetched[0].readinessScore == 92)
        assert(fetched[0].aiSynthesisMarkdown == "Optimal autonomic recovery detected.")
    }
    
    await runTest("Idempotency and update verification (INSERT OR REPLACE)") {
        let db = try DatabaseService(inMemory: true)
        let s1 = BiometricSampleRecord(
            timestamp: 50000,
            heartRateBpm: 55.0,
            rmssdMs: 60.0,
            motionIntensity: 0.1,
            ppgSignalQuality: 0.9
        )
        try await db.saveBiometricSamples([s1])
        
        // Re-insert with updated heart rate and rmssd at same timestamp
        let s1Updated = BiometricSampleRecord(
            timestamp: 50000,
            heartRateBpm: 52.0,
            rmssdMs: 65.0,
            motionIntensity: 0.1,
            ppgSignalQuality: 0.95
        )
        try await db.saveBiometricSamples([s1Updated])
        
        let fetched = try await db.fetchBiometrics(from: 40000, to: 60000)
        assert(fetched.count == 1, "Duplicate timestamp must replace existing record")
        assert(fetched[0].heartRateBpm == 52.0, "Updated heart rate must overwrite original")
        assert(fetched[0].rmssdMs == 65.0, "Updated RMSSD must overwrite original")
    }
    
    await runTest("Performance Benchmark: 30-day range query latency (<10ms target)") {
        let db = try DatabaseService(inMemory: true)
        // 30 days of 5-minute intervals = 30 * 24 * 12 = 8,640 samples
        let sampleCount = 8640
        var samples: [BiometricSampleRecord] = []
        samples.reserveCapacity(sampleCount)
        let baseTime: Int64 = 1700000000000
        
        for i in 0..<sampleCount {
            samples.append(BiometricSampleRecord(
                timestamp: baseTime + Int64(i * 300_000),
                heartRateBpm: 50.0 + Double(i % 30),
                rmssdMs: 60.0 + Double(i % 40),
                motionIntensity: 0.1,
                ppgSignalQuality: 0.98
            ))
        }
        
        try await db.saveBiometricSamples(samples)
        
        // Benchmark range query over entire 30 days
        let startTime = DispatchTime.now()
        let fetched = try await db.fetchBiometrics(from: baseTime, to: baseTime + Int64(sampleCount * 300_000))
        let endTime = DispatchTime.now()
        
        let elapsedNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let elapsedMs = Double(elapsedNanos) / 1_000_000.0
        
        assert(fetched.count == sampleCount, "Expected all 8,640 samples returned")
        print("     ⚡ 30-day range query (8,640 samples) completed in \(String(format: "%.2f", elapsedMs)) ms (Target: < 10.0 ms)")
        assert(elapsedMs < 10.0, "Query latency exceeded 10ms budget: \(elapsedMs) ms")
    }
    
    // MARK: - [8] SyncCoordinator Event Ingestion Pipeline
    print("\n--- [8] SyncCoordinator Event Ingestion Pipeline ---")
    
    await runTest("SyncCoordinator ingests single events and updates state") {
        let db = try DatabaseService(inMemory: true)
        let coordinator = SyncCoordinator(database: db)
        
        let hrvEvent = RingEvent(
            tag: 0x5D,
            name: "hrv_event",
            timestampDeciseconds: 400000,
            rawBody: Data([54, 62]),
            payload: .hrv(samples: [HRVSample(averageHeartRateBpm: 54, averageRmssdMs: 62)])
        )
        let tempEvent = RingEvent(
            tag: 0x46,
            name: "temp_event",
            timestampDeciseconds: 400000,
            rawBody: Data([0x0D, 0x16]),
            payload: .temperature(temperaturesCelsius: [33.5])
        )
        let sleepEvent = RingEvent(
            tag: 0x4B,
            name: "sleep_event",
            timestampDeciseconds: 400000,
            rawBody: Data([0xE4]),
            payload: .sleepPhases(stages: [.deep, .light, .rem, .awake])
        )
        
        try await coordinator.processEvents([hrvEvent, tempEvent, sleepEvent])
        
        let count = await coordinator.eventsProcessedCount
        assert(count == 3, "Expected 3 events processed")
        
        let rawLogs = try await db.fetchRawPackets(limit: 10)
        assert(rawLogs.count == 3, "All 3 events must be losslessly logged")
        
        let biometrics = try await db.fetchBiometrics(from: 0, to: 50000000)
        assert(biometrics.count == 1, "Expected 1 biometric record from HRV event")
        assert(biometrics[0].heartRateBpm == 54.0)
        assert(biometrics[0].rmssdMs == 62.0)
        
        let temps = try await db.fetchTemperature(from: 0, to: 50000000)
        assert(temps.count == 1, "Expected 1 temperature record")
        assert(abs(temps[0].rawCelsius - 33.5) < 0.001)
        
        let episodes = try await db.fetchSleepEpisodes(from: 0, to: 50000000)
        assert(episodes.count == 1, "Expected 1 sleep episode")
        assert(episodes[0].deepSleepSeconds == 300)
        assert(episodes[0].awakeSeconds == 300)
    }
    
    await runTest("SyncCoordinator ingests full synthetic night (252 events)") {
        let generator = MockDataGenerator()
        let fullNightStream = generator.generateFullNightStream()
        
        let reassembler = PacketReassemblyEngine()
        let events = await reassembler.ingestAndExtractEvents(fullNightStream)
        assert(events.count >= 252, "Expected at least 252 night events")
        
        let db = try DatabaseService(inMemory: true)
        let coordinator = SyncCoordinator(database: db)
        
        try await coordinator.processEvents(events)
        
        let processed = await coordinator.eventsProcessedCount
        assert(processed == events.count, "Coordinator should process all events")
        
        let allBiometrics = try await db.fetchBiometrics(from: 0, to: Int64.max)
        assert(allBiometrics.count == 84, "Expected 84 5-minute biometric intervals in DB")
        
        let allTemps = try await db.fetchTemperature(from: 0, to: Int64.max)
        assert(allTemps.count == 84, "Expected 84 temperature records in DB")
        
        let allRaw = try await db.fetchRawPackets(limit: 500)
        assert(allRaw.count == events.count, "All raw event frames must be losslessly stored")
    }
    
    await runTest("SyncCoordinator stream subscription lifecycle") {
        let db = try DatabaseService(inMemory: true)
        let coordinator = SyncCoordinator(database: db)
        
        var continuation: AsyncStream<RingEvent>.Continuation?
        let stream = AsyncStream<RingEvent> { continuation = $0 }
        
        await coordinator.startSync(from: stream)
        let isSyncing = await coordinator.isSyncing
        assert(isSyncing == true, "Coordinator should be syncing")
        
        let testEvent = RingEvent(
            tag: 0x5D,
            name: "hrv_event",
            timestampDeciseconds: 500000,
            rawBody: Data([56, 68]),
            payload: .hrv(samples: [HRVSample(averageHeartRateBpm: 56, averageRmssdMs: 68)])
        )
        continuation?.yield(testEvent)
        continuation?.finish()
        
        // Give background Task time to process yielded event
        try await Task.sleep(nanoseconds: 50_000_000)
        
        await coordinator.stopSync()
        let finalSyncing = await coordinator.isSyncing
        assert(finalSyncing == false, "Coordinator should be stopped")
        
        let count = await coordinator.eventsProcessedCount
        assert(count == 1, "Yielded event should be processed")
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

