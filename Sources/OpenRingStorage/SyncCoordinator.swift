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
    public private(set) var isSyncing: Bool = false
    public private(set) var eventsProcessedCount: Int = 0
    public private(set) var lastSyncedTimestamp: Int64? = nil
    
    private var syncTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(database: DatabaseService) {
        self.database = database
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
    
    private func markSyncFinished() {
        isSyncing = false
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
                tempRecords.append(TemperatureTelemetryRecord(
                    timestamp: sampleTimeMs,
                    rawCelsius: temp,
                    baselineOffsetCelsius: 0.0
                ))
            }
            if !tempRecords.isEmpty {
                try await database.saveTemperatureRecords(tempRecords)
            }
            
        case .sleepPhases(let stages):
            // 5 minutes per stage epoch
            let intervalSec = 300
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
            
            let episode = SleepEpisodeRecord(
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
            try await database.saveSleepEpisode(episode)
            
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
    }
}

