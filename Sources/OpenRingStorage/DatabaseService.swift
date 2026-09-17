import Foundation
import GRDB

/// Isolated Swift 6 actor managing persistent storage via SQLite in Write-Ahead Logging (WAL) mode.
public actor DatabaseService {
    private let dbQueue: DatabaseQueue
    
    /// Initializes DatabaseService with an in-memory database (default for tests).
    public init(inMemory: Bool = false) throws {
        if inMemory {
            self.dbQueue = try DatabaseQueue()
        } else {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let databaseURL = appSupportURL.appendingPathComponent("openring.sqlite")
            
            var config = Configuration()
            config.qos = .userInitiated
            self.dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        }
        
        try setupDatabase()
    }
    
    /// Initializes DatabaseService with a custom file path.
    public init(path: String) throws {
        var config = Configuration()
        config.qos = .userInitiated
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
        try setupDatabase()
    }
    
    private func setupDatabase() throws {
        try dbQueue.write { db in
            // Enable WAL mode and performance pragmas
            try db.execute(sql: "PRAGMA journal_mode = WAL;")
            try db.execute(sql: "PRAGMA synchronous = NORMAL;")
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1_initial_schema") { db in
            // 1. Raw Ingestion Log
            try db.create(table: RawIngestionRecord.databaseTableName, ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("receivedTimestamp", .integer).notNull()
                t.column("packetType", .integer).notNull()
                t.column("sequenceId", .integer).notNull()
                t.column("framePayload", .blob).notNull()
            }
            try db.create(index: "idx_raw_sequence", on: RawIngestionRecord.databaseTableName, columns: ["sequenceId", "receivedTimestamp"], ifNotExists: true)
            
            // 2. Biometric Samples
            try db.create(table: BiometricSampleRecord.databaseTableName, ifNotExists: true) { t in
                t.column("timestamp", .integer).primaryKey()
                t.column("heartRateBpm", .double).notNull()
                t.column("rmssdMs", .double).notNull()
                t.column("motionIntensity", .double).notNull()
                t.column("ppgSignalQuality", .double).notNull()
            }
            try db.create(index: "idx_samples_time_range", on: BiometricSampleRecord.databaseTableName, columns: ["timestamp"], ifNotExists: true)
            
            // 3. Temperature Telemetry
            try db.create(table: TemperatureTelemetryRecord.databaseTableName, ifNotExists: true) { t in
                t.column("timestamp", .integer).primaryKey()
                t.column("rawCelsius", .double).notNull()
                t.column("baselineOffsetCelsius", .double).notNull()
            }
            
            // 4. Sleep Episodes
            try db.create(table: SleepEpisodeRecord.databaseTableName, ifNotExists: true) { t in
                t.column("sessionId", .text).primaryKey()
                t.column("startTime", .integer).notNull()
                t.column("endTime", .integer).notNull()
                t.column("durationSeconds", .integer).notNull()
                t.column("efficiencyRatio", .double).notNull()
                t.column("deepSleepSeconds", .integer).notNull()
                t.column("remSleepSeconds", .integer).notNull()
                t.column("lightSleepSeconds", .integer).notNull()
                t.column("awakeSeconds", .integer).notNull()
                t.column("lowestHeartRate", .integer).notNull()
                t.column("averageHeartRate", .double).notNull()
                t.column("averageRmssd", .double).notNull()
                t.column("temperatureDeviation", .double).notNull()
            }
            try db.create(index: "idx_sleep_start", on: SleepEpisodeRecord.databaseTableName, columns: ["startTime"], ifNotExists: true)
            
            // 5. Daily Evaluations
            try db.create(table: DailyEvaluationRecord.databaseTableName, ifNotExists: true) { t in
                t.column("evaluationDate", .text).primaryKey()
                t.column("readinessScore", .integer).notNull()
                t.column("sleepScore", .integer).notNull()
                t.column("rhrBaseline", .double).notNull()
                t.column("hrvBaseline", .double).notNull()
                t.column("aiSynthesisMarkdown", .text)
                t.column("aiModelTag", .text)
                t.column("generatedAt", .integer).notNull()
            }
        }
        
        try migrator.migrate(dbQueue)
    }
    
    // MARK: - CRUD Operations
    
    public func saveRawPacket(_ record: RawIngestionRecord) throws {
        try dbQueue.write { db in
            try record.insert(db)
        }
    }
    
    public func saveBiometricSamples(_ samples: [BiometricSampleRecord]) throws {
        try dbQueue.write { db in
            for sample in samples {
                try sample.save(db)
            }
        }
    }
    
    public func saveTemperatureRecord(_ record: TemperatureTelemetryRecord) throws {
        try dbQueue.write { db in
            try record.save(db)
        }
    }
    
    public func saveSleepEpisode(_ episode: SleepEpisodeRecord) throws {
        try dbQueue.write { db in
            try episode.save(db)
        }
    }
    
    public func saveDailyEvaluation(_ evaluation: DailyEvaluationRecord) throws {
        try dbQueue.write { db in
            try evaluation.save(db)
        }
    }
    
    public func fetchBiometrics(from startMs: Int64, to endMs: Int64) throws -> [BiometricSampleRecord] {
        try dbQueue.read { db in
            try BiometricSampleRecord
                .filter(Column("timestamp") >= startMs && Column("timestamp") <= endMs)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }
    
    public func fetchLatestDailyEvaluations(limit: Int = 30) throws -> [DailyEvaluationRecord] {
        try dbQueue.read { db in
            try DailyEvaluationRecord
                .order(Column("evaluationDate").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}

