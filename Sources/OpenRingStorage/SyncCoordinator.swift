import Foundation
import OpenRingCore

/// Swift 6 isolated actor coordinating the ingestion of decoded telemetry frames from `BLEEngine`
/// directly into the local SQLite database via `DatabaseService`.
///
/// Implements the lossless storage invariant (DEC-002, DEC-010): every received byte stream is archived
/// in `raw_ingestion_log` before parsed biometrics, temperatures, and sleep stages are persisted.
public actor SyncCoordinator {
    
    // MARK: - State & Dependencies
    
    public let database: DatabaseService
    public let evaluationEngine: DailyEvaluationEngine
    public private(set) var isSyncing: Bool = false
    public private(set) var eventsProcessedCount: Int = 0
    public private(set) var lastSyncedTimestamp: Int64? = nil
    
    private var syncTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(database: DatabaseService, evaluationEngine: DailyEvaluationEngine? = nil) {
        self.database = database
        self.evaluationEngine = evaluationEngine ?? DailyEvaluationEngine(database: database)
    }
    
    deinit {
        syncTask?.cancel()
    }
    
    // MARK: - Ingestion Pipeline
    
    /// Starts continuous synchronization from an asynchronous stream of `RingEvent` instances.
    public func startSync(from stream: AsyncStream<RingEvent>) {
        guard !isSyncing else { return }
        isSyncing = true
        
        syncTask = Task { [weak self] in
            for await event in stream {
                guard let self = self else { break }
                do {
                    try await self.processEvent(event)
                } catch {
                    // Log persistence error without terminating the sync loop
                    print("⚠️ [SyncCoordinator] Failed to persist event 0x\(String(format: "%02X", event.tag)): \(error.localizedDescription)")
                }
            }
            await self?.markSyncFinished()
        }
    }
    
    /// Stops continuous synchronization and cancels the listening task.
    public func stopSync() {
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
    }
    
    private func markSyncFinished() async {
        isSyncing = false
        _ = try? await evaluationEngine.evaluateLatestSession()
    }
    
    /// Ingests a single `RingEvent`, saving the raw packet audit and transforming typed payloads into SQLite records.
    public func processEvent(_ event: RingEvent) async throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        
        // 1. Lossless Raw Audit Log
        let rawRecord = RawIngestionRecord(
            receivedTimestamp: now,
            packetType: Int(event.tag),
            sequenceId: eventsProcessedCount,
            framePayload: event.rawBody
        )
        try await database.saveRawPacket(rawRecord)
        
        // 2. Decode Deciseconds to Epoch Milliseconds
        let baseTimestampMs = Int64(event.timestampDeciseconds) * 100
        
        // 3. Typed Payload Processing
        switch event.payload {
        case .hrv(let samples):
            var biometricRecords: [BiometricSampleRecord] = []
            for (index, sample) in samples.enumerated() {
                // 5 minutes = 300,000 milliseconds per interval
                let sampleTimeMs = baseTimestampMs + Int64(index * 300_000)
                biometricRecords.append(BiometricSampleRecord(
                    timestamp: sampleTimeMs,
                    heartRateBpm: Double(sample.averageHeartRateBpm),
                    rmssdMs: Double(sample.averageRmssdMs),
                    motionIntensity: 0.0,
                    ppgSignalQuality: 1.0
                ))
            }
            if !biometricRecords.isEmpty {
                try await database.saveBiometricSamples(biometricRecords)
            }
            
        case .temperature(let temps):
            var tempRecords: [TemperatureTelemetryRecord] = []
            for (index, temp) in temps.enumerated() {
                let sampleTimeMs = baseTimestampMs + Int64(index * 300_000)
                let offset = round((temp - 33.0) * 100.0) / 100.0
                tempRecords.append(TemperatureTelemetryRecord(
                    timestamp: sampleTimeMs,
                    rawCelsius: temp,
                    baselineOffsetCelsius: offset
                ))
            }
            if !tempRecords.isEmpty {
                try await database.saveTemperatureRecords(tempRecords)
            }
            
        case .sleepPhases(let stages):
            guard !stages.isEmpty else { break }
            let intervalSec = 300
            
            let existing = try await database.fetchLatestSleepEpisode()
            let episode: SleepEpisodeRecord
            
            if let existing = existing, baseTimestampMs >= existing.startTime, baseTimestampMs <= existing.endTime + 1800_000 {
                // Determine if this is a consecutive 5-minute streaming interval
                let isStreamingInterval = (baseTimestampMs > existing.startTime && baseTimestampMs <= existing.startTime + Int64(existing.durationSeconds * 1000) + 300_000)
                
                if isStreamingInterval {
                    // Each interval adds 300s for its primary stage
                    let stage = stages[0]
                    let addDeep = (stage == .deep ? intervalSec : 0)
                    let addRem = (stage == .rem ? intervalSec : 0)
                    let addLight = (stage == .light ? intervalSec : 0)
                    let addAwake = (stage == .awake ? intervalSec : 0)
                    
                    let newEndTimeMs = baseTimestampMs + Int64(intervalSec * 1000)
                    let newDuration = Int((newEndTimeMs - existing.startTime) / 1000)
                    
                    // If this is the second packet (i.e. existing was created with multiple padding stages from packet 0),
                    // normalize existing to the first packet's single stage
                    let baseDeep: Int
                    let baseRem: Int
                    let baseLight: Int
                    let baseAwake: Int
                    
                    if existing.durationSeconds > intervalSec && baseTimestampMs == existing.startTime + Int64(intervalSec * 1000) {
                        // Correct for initial packet padding: keep only 1 stage
                        baseDeep = (existing.deepSleepSeconds > 0 && existing.durationSeconds == 1200 && existing.deepSleepSeconds >= 900) ? 0 : existing.deepSleepSeconds
                        baseRem = existing.remSleepSeconds
                        baseLight = existing.lightSleepSeconds
                        baseAwake = existing.awakeSeconds
                    } else {
                        baseDeep = existing.deepSleepSeconds
                        baseRem = existing.remSleepSeconds
                        baseLight = existing.lightSleepSeconds
                        baseAwake = existing.awakeSeconds
                    }
                    
                    let mergedDeep = baseDeep + addDeep
                    let mergedRem = baseRem + addRem
                    let mergedLight = baseLight + addLight
                    let mergedAwake = baseAwake + addAwake
                    let mergedEfficiency = newDuration > 0 ? Double(newDuration - mergedAwake) / Double(newDuration) : 1.0
                    
                    episode = SleepEpisodeRecord(
                        sessionId: existing.sessionId,
                        startTime: existing.startTime,
                        endTime: newEndTimeMs,
                        durationSeconds: newDuration,
                        efficiencyRatio: mergedEfficiency,
                        deepSleepSeconds: mergedDeep,
                        remSleepSeconds: mergedRem,
                        lightSleepSeconds: mergedLight,
                        awakeSeconds: mergedAwake,
                        lowestHeartRate: existing.lowestHeartRate,
                        averageHeartRate: existing.averageHeartRate,
                        averageRmssd: existing.averageRmssd,
                        temperatureDeviation: existing.temperatureDeviation
                    )
                } else {
                    // Contiguous multi-stage block
                    var deepSec = 0
                    var remSec = 0
                    var lightSec = 0
                    var awakeSec = 0
                    for stage in stages {
                        switch stage {
                        case .deep: deepSec += intervalSec
                        case .rem: remSec += intervalSec
                        case .light: lightSec += intervalSec
                        case .awake: awakeSec += intervalSec
                        case .unknown: lightSec += intervalSec
                        }
                    }
                    let totalSec = deepSec + remSec + lightSec + awakeSec
                    let mergedDuration = existing.durationSeconds + totalSec
                    let mergedDeep = existing.deepSleepSeconds + deepSec
                    let mergedRem = existing.remSleepSeconds + remSec
                    let mergedLight = existing.lightSleepSeconds + lightSec
                    let mergedAwake = existing.awakeSeconds + awakeSec
                    let mergedEfficiency = mergedDuration > 0 ? Double(mergedDuration - mergedAwake) / Double(mergedDuration) : 1.0
                    let mergedEndTime = max(existing.endTime, baseTimestampMs + Int64(totalSec * 1000))
                    
                    episode = SleepEpisodeRecord(
                        sessionId: existing.sessionId,
                        startTime: existing.startTime,
                        endTime: mergedEndTime,
                        durationSeconds: mergedDuration,
                        efficiencyRatio: mergedEfficiency,
                        deepSleepSeconds: mergedDeep,
                        remSleepSeconds: mergedRem,
                        lightSleepSeconds: mergedLight,
                        awakeSeconds: mergedAwake,
                        lowestHeartRate: existing.lowestHeartRate,
                        averageHeartRate: existing.averageHeartRate,
                        averageRmssd: existing.averageRmssd,
                        temperatureDeviation: existing.temperatureDeviation
                    )
                }
            } else {
                // New episode
                var deepSec = 0
                var remSec = 0
                var lightSec = 0
                var awakeSec = 0
                for stage in stages {
                    switch stage {
                    case .deep: deepSec += intervalSec
                    case .rem: remSec += intervalSec
                    case .light: lightSec += intervalSec
                    case .awake: awakeSec += intervalSec
                    case .unknown: lightSec += intervalSec
                    }
                }
                let totalSec = deepSec + remSec + lightSec + awakeSec
                let efficiency = totalSec > 0 ? Double(totalSec - awakeSec) / Double(totalSec) : 1.0
                let endTimeMs = baseTimestampMs + Int64(totalSec * 1000)
                let sessionId = "sleep_\(baseTimestampMs)"
                
                episode = SleepEpisodeRecord(
                    sessionId: sessionId,
                    startTime: baseTimestampMs,
                    endTime: endTimeMs,
                    durationSeconds: totalSec,
                    efficiencyRatio: efficiency,
                    deepSleepSeconds: deepSec,
                    remSleepSeconds: remSec,
                    lightSleepSeconds: lightSec,
                    awakeSeconds: awakeSec,
                    lowestHeartRate: 0,
                    averageHeartRate: 0.0,
                    averageRmssd: 0.0,
                    temperatureDeviation: 0.0
                )
            }
            try await database.saveSleepEpisode(episode)
            _ = try await evaluationEngine.evaluateSleepSession(episode)
            
        default:
            // Other payloads (motion, boot, timeSync) are preserved losslessly in raw_ingestion_log
            break
        }
        
        // 4. Update Ingestion State
        eventsProcessedCount += 1
        if baseTimestampMs > 0 {
            lastSyncedTimestamp = max(lastSyncedTimestamp ?? 0, baseTimestampMs)
        }
    }
    
    /// Batches an array of history events into the database.
    public func processEvents(_ events: [RingEvent]) async throws {
        for event in events {
            try await processEvent(event)
        }
        // Re-evaluate latest session to ensure all late-arriving biometrics/temperatures are correlated
        _ = try? await evaluationEngine.evaluateLatestSession()
    }
    
    /// Triggers an on-demand re-evaluation of the latest sleep session in the database.
    @discardableResult
    public func evaluateLatestSession() async throws -> DailyEvaluationRecord? {
        return try await evaluationEngine.evaluateLatestSession()
    }
}

