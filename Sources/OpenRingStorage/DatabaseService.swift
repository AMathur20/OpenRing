import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite errors with descriptive failure reasons.
public enum SQLiteStorageError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "SQLite connection error: \(msg)"
        case .executionFailed(let msg): return "SQLite execution error: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare statement error: \(msg)"
        case .stepFailed(let msg): return "SQLite step error: \(msg)"
        }
    }
}

/// Swift 6 isolated actor managing local persistence using native SQLite3 in Write-Ahead Logging (WAL) mode.
/// Zero external package dependencies. Thread-safe write serialization and high-performance range queries.
public actor DatabaseService {
    private var db: OpaquePointer?
    public let databasePath: String
    
    /// Initializes DatabaseService with an in-memory database or persistent file.
    /// - Parameters:
    ///   - inMemory: When true, opens an isolated `:memory:` database (ideal for tests).
    ///   - customPath: Optional custom path. If omitted and `inMemory` is false, stores in Application Support.
    public init(inMemory: Bool = false, customPath: String? = nil) throws {
        if inMemory {
            self.databasePath = ":memory:"
        } else if let customPath = customPath {
            self.databasePath = customPath
        } else {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("openring", isDirectory: true)
            
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            self.databasePath = appSupportURL.appendingPathComponent("openring.sqlite").path
        }
        
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(self.databasePath, &connection, flags, nil) != SQLITE_OK {
            let errMsg = connection != nil ? String(cString: sqlite3_errmsg(connection)) : "Unknown"
            sqlite3_close_v2(connection)
            throw SQLiteStorageError.connectionFailed(errMsg)
        }
        self.db = connection
        
        Self.configurePragmas(db: connection)
        try Self.runMigrations(db: connection)
    }
    
    deinit {
        if let db = db {
            sqlite3_close_v2(db)
        }
    }
    
    // MARK: - Configuration & Migrations
    
    private static func configurePragmas(db: OpaquePointer?) {
        _ = execute(sql: "PRAGMA journal_mode = WAL;", db: db)
        _ = execute(sql: "PRAGMA synchronous = NORMAL;", db: db)
        _ = execute(sql: "PRAGMA foreign_keys = ON;", db: db)
        sqlite3_busy_timeout(db, 5000)
    }
    
    @discardableResult
    private static func execute(sql: String, db: OpaquePointer?) -> Bool {
        guard let db = db else { return false }
        var errorMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            sqlite3_free(errorMsg)
            return false
        }
        return true
    }
    
    private func execute(sql: String) throws {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        var errorMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMsg)
            throw SQLiteStorageError.executionFailed(msg)
        }
    }
    
    private static func runMigrations(db: OpaquePointer?) throws {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version TEXT PRIMARY KEY,
                applied_at INTEGER NOT NULL
            );
        """, db: db)
        
        var stmt: OpaquePointer?
        let checkSql = "SELECT 1 FROM schema_migrations WHERE version = 'v1_initial_schema' LIMIT 1;"
        let hasV1: Bool
        if sqlite3_prepare_v2(db, checkSql, -1, &stmt, nil) == SQLITE_OK {
            hasV1 = (sqlite3_step(stmt) == SQLITE_ROW)
            sqlite3_finalize(stmt)
        } else {
            hasV1 = false
        }
        
        if !hasV1 {
            execute(sql: "BEGIN TRANSACTION;", db: db)
            
            // 1. Raw Ingestion Log
            execute(sql: """
                CREATE TABLE IF NOT EXISTS \(RawIngestionRecord.databaseTableName) (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    receivedTimestamp INTEGER NOT NULL,
                    packetType INTEGER NOT NULL,
                    sequenceId INTEGER NOT NULL,
                    framePayload BLOB NOT NULL
                );
            """, db: db)
            execute(sql: "CREATE INDEX IF NOT EXISTS idx_raw_sequence ON \(RawIngestionRecord.databaseTableName) (sequenceId, receivedTimestamp);", db: db)
            
            // 2. Biometric Samples
            execute(sql: """
                CREATE TABLE IF NOT EXISTS \(BiometricSampleRecord.databaseTableName) (
                    timestamp INTEGER PRIMARY KEY,
                    heartRateBpm REAL NOT NULL,
                    rmssdMs REAL NOT NULL,
                    motionIntensity REAL NOT NULL,
                    ppgSignalQuality REAL NOT NULL
                );
            """, db: db)
            execute(sql: "CREATE INDEX IF NOT EXISTS idx_samples_timestamp ON \(BiometricSampleRecord.databaseTableName) (timestamp);", db: db)
            
            // 3. Temperature Telemetry
            execute(sql: """
                CREATE TABLE IF NOT EXISTS \(TemperatureTelemetryRecord.databaseTableName) (
                    timestamp INTEGER PRIMARY KEY,
                    rawCelsius REAL NOT NULL,
                    baselineOffsetCelsius REAL NOT NULL
                );
            """, db: db)
            execute(sql: "CREATE INDEX IF NOT EXISTS idx_temp_timestamp ON \(TemperatureTelemetryRecord.databaseTableName) (timestamp);", db: db)
            
            // 4. Sleep Episodes
            execute(sql: """
                CREATE TABLE IF NOT EXISTS \(SleepEpisodeRecord.databaseTableName) (
                    sessionId TEXT PRIMARY KEY,
                    startTime INTEGER NOT NULL,
                    endTime INTEGER NOT NULL,
                    durationSeconds INTEGER NOT NULL,
                    efficiencyRatio REAL NOT NULL,
                    deepSleepSeconds INTEGER NOT NULL,
                    remSleepSeconds INTEGER NOT NULL,
                    lightSleepSeconds INTEGER NOT NULL,
                    awakeSeconds INTEGER NOT NULL,
                    lowestHeartRate INTEGER NOT NULL,
                    averageHeartRate REAL NOT NULL,
                    averageRmssd REAL NOT NULL,
                    temperatureDeviation REAL NOT NULL
                );
            """, db: db)
            execute(sql: "CREATE INDEX IF NOT EXISTS idx_sleep_start ON \(SleepEpisodeRecord.databaseTableName) (startTime);", db: db)
            execute(sql: "CREATE INDEX IF NOT EXISTS idx_sleep_end ON \(SleepEpisodeRecord.databaseTableName) (endTime);", db: db)
            
            // 5. Daily Evaluations
            execute(sql: """
                CREATE TABLE IF NOT EXISTS \(DailyEvaluationRecord.databaseTableName) (
                    evaluationDate TEXT PRIMARY KEY,
                    readinessScore INTEGER NOT NULL,
                    sleepScore INTEGER NOT NULL,
                    rhrBaseline REAL NOT NULL,
                    hrvBaseline REAL NOT NULL,
                    aiSynthesisMarkdown TEXT,
                    aiModelTag TEXT,
                    generatedAt INTEGER NOT NULL
                );
            """, db: db)
            
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            execute(sql: "INSERT INTO schema_migrations (version, applied_at) VALUES ('v1_initial_schema', \(now));", db: db)
            execute(sql: "COMMIT;", db: db)
        }
    }
    
    // MARK: - Transaction Management
    
    public func executeInTransaction(_ block: () throws -> Void) throws {
        try execute(sql: "BEGIN TRANSACTION;")
        do {
            try block()
            try execute(sql: "COMMIT;")
        } catch {
            try? execute(sql: "ROLLBACK;")
            throw error
        }
    }
    
    // MARK: - Persistence Operations
    
    /// Persists an incoming raw packet to `raw_ingestion_log`.
    public func saveRawPacket(_ record: RawIngestionRecord) throws {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = "INSERT INTO \(RawIngestionRecord.databaseTableName) (receivedTimestamp, packetType, sequenceId, framePayload) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, record.receivedTimestamp)
        sqlite3_bind_int(stmt, 2, Int32(record.packetType))
        sqlite3_bind_int(stmt, 3, Int32(record.sequenceId))
        _ = record.framePayload.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(record.framePayload.count), SQLITE_TRANSIENT)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteStorageError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
    
    /// Batches biometric samples into `biometric_samples` within a single atomic transaction.
    public func saveBiometricSamples(_ samples: [BiometricSampleRecord]) throws {
        guard !samples.isEmpty else { return }
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        
        let sql = """
            INSERT OR REPLACE INTO \(BiometricSampleRecord.databaseTableName) 
            (timestamp, heartRateBpm, rmssdMs, motionIntensity, ppgSignalQuality) 
            VALUES (?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        try executeInTransaction {
            for sample in samples {
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, sample.timestamp)
                sqlite3_bind_double(stmt, 2, sample.heartRateBpm)
                sqlite3_bind_double(stmt, 3, sample.rmssdMs)
                sqlite3_bind_double(stmt, 4, sample.motionIntensity)
                sqlite3_bind_double(stmt, 5, sample.ppgSignalQuality)
                
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteStorageError.stepFailed(String(cString: sqlite3_errmsg(db)))
                }
            }
        }
    }
    
    /// Persists a single nocturnal temperature telemetry record.
    public func saveTemperatureRecord(_ record: TemperatureTelemetryRecord) throws {
        try saveTemperatureRecords([record])
    }
    
    /// Batches temperature telemetry records into `temperature_telemetry` within a single atomic transaction.
    public func saveTemperatureRecords(_ records: [TemperatureTelemetryRecord]) throws {
        guard !records.isEmpty else { return }
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        
        let sql = "INSERT OR REPLACE INTO \(TemperatureTelemetryRecord.databaseTableName) (timestamp, rawCelsius, baselineOffsetCelsius) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        try executeInTransaction {
            for record in records {
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, record.timestamp)
                sqlite3_bind_double(stmt, 2, record.rawCelsius)
                sqlite3_bind_double(stmt, 3, record.baselineOffsetCelsius)
                
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SQLiteStorageError.stepFailed(String(cString: sqlite3_errmsg(db)))
                }
            }
        }
    }
    
    /// Persists a classified sleep episode record.
    public func saveSleepEpisode(_ episode: SleepEpisodeRecord) throws {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            INSERT OR REPLACE INTO \(SleepEpisodeRecord.databaseTableName) 
            (sessionId, startTime, endTime, durationSeconds, efficiencyRatio, deepSleepSeconds, remSleepSeconds, lightSleepSeconds, awakeSeconds, lowestHeartRate, averageHeartRate, averageRmssd, temperatureDeviation)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (episode.sessionId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, episode.startTime)
        sqlite3_bind_int64(stmt, 3, episode.endTime)
        sqlite3_bind_int(stmt, 4, Int32(episode.durationSeconds))
        sqlite3_bind_double(stmt, 5, episode.efficiencyRatio)
        sqlite3_bind_int(stmt, 6, Int32(episode.deepSleepSeconds))
        sqlite3_bind_int(stmt, 7, Int32(episode.remSleepSeconds))
        sqlite3_bind_int(stmt, 8, Int32(episode.lightSleepSeconds))
        sqlite3_bind_int(stmt, 9, Int32(episode.awakeSeconds))
        sqlite3_bind_int(stmt, 10, Int32(episode.lowestHeartRate))
        sqlite3_bind_double(stmt, 11, episode.averageHeartRate)
        sqlite3_bind_double(stmt, 12, episode.averageRmssd)
        sqlite3_bind_double(stmt, 13, episode.temperatureDeviation)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteStorageError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
    
    /// Persists a daily readiness and sleep score evaluation.
    public func saveDailyEvaluation(_ evaluation: DailyEvaluationRecord) throws {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            INSERT OR REPLACE INTO \(DailyEvaluationRecord.databaseTableName) 
            (evaluationDate, readinessScore, sleepScore, rhrBaseline, hrvBaseline, aiSynthesisMarkdown, aiModelTag, generatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (evaluation.evaluationDate as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(evaluation.readinessScore))
        sqlite3_bind_int(stmt, 3, Int32(evaluation.sleepScore))
        sqlite3_bind_double(stmt, 4, evaluation.rhrBaseline)
        sqlite3_bind_double(stmt, 5, evaluation.hrvBaseline)
        
        if let markdown = evaluation.aiSynthesisMarkdown {
            sqlite3_bind_text(stmt, 6, (markdown as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        
        if let tag = evaluation.aiModelTag {
            sqlite3_bind_text(stmt, 7, (tag as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        
        sqlite3_bind_int64(stmt, 8, evaluation.generatedAt)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteStorageError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
    
    // MARK: - High-Performance Range Queries
    
    /// Queries biometric samples within a time range, ordered chronologically.
    public func fetchBiometrics(from startMs: Int64, to endMs: Int64) throws -> [BiometricSampleRecord] {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            SELECT timestamp, heartRateBpm, rmssdMs, motionIntensity, ppgSignalQuality 
            FROM \(BiometricSampleRecord.databaseTableName) 
            WHERE timestamp >= ? AND timestamp <= ? 
            ORDER BY timestamp ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, startMs)
        sqlite3_bind_int64(stmt, 2, endMs)
        
        var results: [BiometricSampleRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(stmt, 0)
            let hr = sqlite3_column_double(stmt, 1)
            let rmssd = sqlite3_column_double(stmt, 2)
            let motion = sqlite3_column_double(stmt, 3)
            let quality = sqlite3_column_double(stmt, 4)
            
            results.append(BiometricSampleRecord(
                timestamp: timestamp,
                heartRateBpm: hr,
                rmssdMs: rmssd,
                motionIntensity: motion,
                ppgSignalQuality: quality
            ))
        }
        return results
    }
    
    /// Queries temperature telemetry records within a time range.
    public func fetchTemperature(from startMs: Int64, to endMs: Int64) throws -> [TemperatureTelemetryRecord] {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            SELECT timestamp, rawCelsius, baselineOffsetCelsius 
            FROM \(TemperatureTelemetryRecord.databaseTableName) 
            WHERE timestamp >= ? AND timestamp <= ? 
            ORDER BY timestamp ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, startMs)
        sqlite3_bind_int64(stmt, 2, endMs)
        
        var results: [TemperatureTelemetryRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(stmt, 0)
            let raw = sqlite3_column_double(stmt, 1)
            let offset = sqlite3_column_double(stmt, 2)
            results.append(TemperatureTelemetryRecord(timestamp: timestamp, rawCelsius: raw, baselineOffsetCelsius: offset))
        }
        return results
    }
    
    /// Queries sleep episode records within a start time range.
    public func fetchSleepEpisodes(from startMs: Int64, to endMs: Int64) throws -> [SleepEpisodeRecord] {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            SELECT sessionId, startTime, endTime, durationSeconds, efficiencyRatio, 
                   deepSleepSeconds, remSleepSeconds, lightSleepSeconds, awakeSeconds, 
                   lowestHeartRate, averageHeartRate, averageRmssd, temperatureDeviation 
            FROM \(SleepEpisodeRecord.databaseTableName) 
            WHERE startTime >= ? AND startTime <= ? 
            ORDER BY startTime DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, startMs)
        sqlite3_bind_int64(stmt, 2, endMs)
        
        var results: [SleepEpisodeRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sessionId = String(cString: sqlite3_column_text(stmt, 0))
            let startTime = sqlite3_column_int64(stmt, 1)
            let endTime = sqlite3_column_int64(stmt, 2)
            let duration = Int(sqlite3_column_int(stmt, 3))
            let efficiency = sqlite3_column_double(stmt, 4)
            let deep = Int(sqlite3_column_int(stmt, 5))
            let rem = Int(sqlite3_column_int(stmt, 6))
            let light = Int(sqlite3_column_int(stmt, 7))
            let awake = Int(sqlite3_column_int(stmt, 8))
            let lowestHr = Int(sqlite3_column_int(stmt, 9))
            let avgHr = sqlite3_column_double(stmt, 10)
            let avgRmssd = sqlite3_column_double(stmt, 11)
            let tempDev = sqlite3_column_double(stmt, 12)
            
            results.append(SleepEpisodeRecord(
                sessionId: sessionId,
                startTime: startTime,
                endTime: endTime,
                durationSeconds: duration,
                efficiencyRatio: efficiency,
                deepSleepSeconds: deep,
                remSleepSeconds: rem,
                lightSleepSeconds: light,
                awakeSeconds: awake,
                lowestHeartRate: lowestHr,
                averageHeartRate: avgHr,
                averageRmssd: avgRmssd,
                temperatureDeviation: tempDev
            ))
        }
        return results
    }
    
    /// Queries the latest computed daily evaluation records.
    public func fetchLatestDailyEvaluations(limit: Int = 30) throws -> [DailyEvaluationRecord] {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            SELECT evaluationDate, readinessScore, sleepScore, rhrBaseline, hrvBaseline, 
                   aiSynthesisMarkdown, aiModelTag, generatedAt 
            FROM \(DailyEvaluationRecord.databaseTableName) 
            ORDER BY evaluationDate DESC 
            LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        var results: [DailyEvaluationRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let date = String(cString: sqlite3_column_text(stmt, 0))
            let readiness = Int(sqlite3_column_int(stmt, 1))
            let sleep = Int(sqlite3_column_int(stmt, 2))
            let rhr = sqlite3_column_double(stmt, 3)
            let hrv = sqlite3_column_double(stmt, 4)
            
            let markdown: String? = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            let modelTag: String? = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            let generatedAt = sqlite3_column_int64(stmt, 7)
            
            results.append(DailyEvaluationRecord(
                evaluationDate: date,
                readinessScore: readiness,
                sleepScore: sleep,
                rhrBaseline: rhr,
                hrvBaseline: hrv,
                aiSynthesisMarkdown: markdown,
                aiModelTag: modelTag,
                generatedAt: generatedAt
            ))
        }
        return results
    }
    
    /// Queries a daily evaluation record for a specific calendar date ('YYYY-MM-DD').
    public func fetchDailyEvaluation(for date: String) throws -> DailyEvaluationRecord? {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            SELECT evaluationDate, readinessScore, sleepScore, rhrBaseline, hrvBaseline, 
                   aiSynthesisMarkdown, aiModelTag, generatedAt 
            FROM \(DailyEvaluationRecord.databaseTableName) 
            WHERE evaluationDate = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        let evalDate = String(cString: sqlite3_column_text(stmt, 0))
        let readiness = Int(sqlite3_column_int(stmt, 1))
        let sleep = Int(sqlite3_column_int(stmt, 2))
        let rhr = sqlite3_column_double(stmt, 3)
        let hrv = sqlite3_column_double(stmt, 4)
        let markdown: String? = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let modelTag: String? = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let generatedAt = sqlite3_column_int64(stmt, 7)
        
        return DailyEvaluationRecord(
            evaluationDate: evalDate,
            readinessScore: readiness,
            sleepScore: sleep,
            rhrBaseline: rhr,
            hrvBaseline: hrv,
            aiSynthesisMarkdown: markdown,
            aiModelTag: modelTag,
            generatedAt: generatedAt
        )
    }
    
    /// Queries the most recent daily evaluation record strictly before a given date (or latest overall if date is nil).
    public func fetchLatestDailyEvaluation(before date: String? = nil) throws -> DailyEvaluationRecord? {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql: String
        if date != nil {
            sql = """
                SELECT evaluationDate, readinessScore, sleepScore, rhrBaseline, hrvBaseline, 
                       aiSynthesisMarkdown, aiModelTag, generatedAt 
                FROM \(DailyEvaluationRecord.databaseTableName) 
                WHERE evaluationDate < ? 
                ORDER BY evaluationDate DESC 
                LIMIT 1;
            """
        } else {
            sql = """
                SELECT evaluationDate, readinessScore, sleepScore, rhrBaseline, hrvBaseline, 
                       aiSynthesisMarkdown, aiModelTag, generatedAt 
                FROM \(DailyEvaluationRecord.databaseTableName) 
                ORDER BY evaluationDate DESC 
                LIMIT 1;
            """
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        if let date = date {
            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT)
        }
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        let evalDate = String(cString: sqlite3_column_text(stmt, 0))
        let readiness = Int(sqlite3_column_int(stmt, 1))
        let sleep = Int(sqlite3_column_int(stmt, 2))
        let rhr = sqlite3_column_double(stmt, 3)
        let hrv = sqlite3_column_double(stmt, 4)
        let markdown: String? = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let modelTag: String? = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let generatedAt = sqlite3_column_int64(stmt, 7)
        
        return DailyEvaluationRecord(
            evaluationDate: evalDate,
            readinessScore: readiness,
            sleepScore: sleep,
            rhrBaseline: rhr,
            hrvBaseline: hrv,
            aiSynthesisMarkdown: markdown,
            aiModelTag: modelTag,
            generatedAt: generatedAt
        )
    }
    
    /// Queries a single sleep episode record by session ID.
    public func fetchSleepEpisode(sessionId: String) throws -> SleepEpisodeRecord? {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            SELECT sessionId, startTime, endTime, durationSeconds, efficiencyRatio, 
                   deepSleepSeconds, remSleepSeconds, lightSleepSeconds, awakeSeconds, 
                   lowestHeartRate, averageHeartRate, averageRmssd, temperatureDeviation 
            FROM \(SleepEpisodeRecord.databaseTableName) 
            WHERE sessionId = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        return SleepEpisodeRecord(
            sessionId: String(cString: sqlite3_column_text(stmt, 0)),
            startTime: sqlite3_column_int64(stmt, 1),
            endTime: sqlite3_column_int64(stmt, 2),
            durationSeconds: Int(sqlite3_column_int(stmt, 3)),
            efficiencyRatio: sqlite3_column_double(stmt, 4),
            deepSleepSeconds: Int(sqlite3_column_int(stmt, 5)),
            remSleepSeconds: Int(sqlite3_column_int(stmt, 6)),
            lightSleepSeconds: Int(sqlite3_column_int(stmt, 7)),
            awakeSeconds: Int(sqlite3_column_int(stmt, 8)),
            lowestHeartRate: Int(sqlite3_column_int(stmt, 9)),
            averageHeartRate: sqlite3_column_double(stmt, 10),
            averageRmssd: sqlite3_column_double(stmt, 11),
            temperatureDeviation: sqlite3_column_double(stmt, 12)
        )
    }
    
    /// Queries the most recent sleep episode record by endTime.
    public func fetchLatestSleepEpisode() throws -> SleepEpisodeRecord? {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            SELECT sessionId, startTime, endTime, durationSeconds, efficiencyRatio, 
                   deepSleepSeconds, remSleepSeconds, lightSleepSeconds, awakeSeconds, 
                   lowestHeartRate, averageHeartRate, averageRmssd, temperatureDeviation 
            FROM \(SleepEpisodeRecord.databaseTableName) 
            ORDER BY endTime DESC 
            LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        return SleepEpisodeRecord(
            sessionId: String(cString: sqlite3_column_text(stmt, 0)),
            startTime: sqlite3_column_int64(stmt, 1),
            endTime: sqlite3_column_int64(stmt, 2),
            durationSeconds: Int(sqlite3_column_int(stmt, 3)),
            efficiencyRatio: sqlite3_column_double(stmt, 4),
            deepSleepSeconds: Int(sqlite3_column_int(stmt, 5)),
            remSleepSeconds: Int(sqlite3_column_int(stmt, 6)),
            lightSleepSeconds: Int(sqlite3_column_int(stmt, 7)),
            awakeSeconds: Int(sqlite3_column_int(stmt, 8)),
            lowestHeartRate: Int(sqlite3_column_int(stmt, 9)),
            averageHeartRate: sqlite3_column_double(stmt, 10),
            averageRmssd: sqlite3_column_double(stmt, 11),
            temperatureDeviation: sqlite3_column_double(stmt, 12)
        )
    }
    
    /// Queries the latest raw ingestion packets.
    public func fetchRawPackets(limit: Int = 100) throws -> [RawIngestionRecord] {
        guard let db = db else { throw SQLiteStorageError.connectionFailed("Database closed") }
        let sql = """
            SELECT id, receivedTimestamp, packetType, sequenceId, framePayload 
            FROM \(RawIngestionRecord.databaseTableName) 
            ORDER BY id DESC 
            LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteStorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        
        var results: [RawIngestionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let ts = sqlite3_column_int64(stmt, 1)
            let type = Int(sqlite3_column_int(stmt, 2))
            let seq = Int(sqlite3_column_int(stmt, 3))
            
            var payload = Data()
            if let blobBytes = sqlite3_column_blob(stmt, 4) {
                let byteCount = sqlite3_column_bytes(stmt, 4)
                payload = Data(bytes: blobBytes, count: Int(byteCount))
            }
            
            results.append(RawIngestionRecord(
                id: id,
                receivedTimestamp: ts,
                packetType: type,
                sequenceId: seq,
                framePayload: payload
            ))
        }
        return results
    }
}

