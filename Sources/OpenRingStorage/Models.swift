import Foundation

/// Lossless raw immutable packet record stored in `raw_ingestion_log`.
public struct RawIngestionRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "raw_ingestion_log"
    
    public var id: Int64?
    public let receivedTimestamp: Int64 // Unix Epoch ms
    public let packetType: Int
    public let sequenceId: Int
    public let framePayload: Data
    
    public init(id: Int64? = nil, receivedTimestamp: Int64, packetType: Int, sequenceId: Int, framePayload: Data) {
        self.id = id
        self.receivedTimestamp = receivedTimestamp
        self.packetType = packetType
        self.sequenceId = sequenceId
        self.framePayload = framePayload
    }
}

/// 5-minute interval biometric sample stored in `biometric_samples`.
public struct BiometricSampleRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "biometric_samples"
    
    public var id: Int64 { timestamp }
    public let timestamp: Int64 // Unix Epoch ms
    public let heartRateBpm: Double
    public let rmssdMs: Double
    public let motionIntensity: Double
    public let ppgSignalQuality: Double
    
    public init(timestamp: Int64, heartRateBpm: Double, rmssdMs: Double, motionIntensity: Double, ppgSignalQuality: Double) {
        self.timestamp = timestamp
        self.heartRateBpm = heartRateBpm
        self.rmssdMs = rmssdMs
        self.motionIntensity = motionIntensity
        self.ppgSignalQuality = ppgSignalQuality
    }
}

/// Nocturnal skin temperature sample stored in `temperature_telemetry`.
public struct TemperatureTelemetryRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "temperature_telemetry"
    
    public var id: Int64 { timestamp }
    public let timestamp: Int64 // Unix Epoch ms
    public let rawCelsius: Double
    public let baselineOffsetCelsius: Double
    
    public init(timestamp: Int64, rawCelsius: Double, baselineOffsetCelsius: Double) {
        self.timestamp = timestamp
        self.rawCelsius = rawCelsius
        self.baselineOffsetCelsius = baselineOffsetCelsius
    }
}

/// Classified sleep episode record stored in `sleep_episodes`.
public struct SleepEpisodeRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "sleep_episodes"
    
    public var id: String { sessionId }
    public let sessionId: String
    public let startTime: Int64
    public let endTime: Int64
    public let durationSeconds: Int
    public let efficiencyRatio: Double
    public let deepSleepSeconds: Int
    public let remSleepSeconds: Int
    public let lightSleepSeconds: Int
    public let awakeSeconds: Int
    public let lowestHeartRate: Int
    public let averageHeartRate: Double
    public let averageRmssd: Double
    public let temperatureDeviation: Double
    
    public init(
        sessionId: String,
        startTime: Int64,
        endTime: Int64,
        durationSeconds: Int,
        efficiencyRatio: Double,
        deepSleepSeconds: Int,
        remSleepSeconds: Int,
        lightSleepSeconds: Int,
        awakeSeconds: Int,
        lowestHeartRate: Int,
        averageHeartRate: Double,
        averageRmssd: Double,
        temperatureDeviation: Double
    ) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.efficiencyRatio = efficiencyRatio
        self.deepSleepSeconds = deepSleepSeconds
        self.remSleepSeconds = remSleepSeconds
        self.lightSleepSeconds = lightSleepSeconds
        self.awakeSeconds = awakeSeconds
        self.lowestHeartRate = lowestHeartRate
        self.averageHeartRate = averageHeartRate
        self.averageRmssd = averageRmssd
        self.temperatureDeviation = temperatureDeviation
    }
}

/// Daily computed readiness and sleep score aggregate stored in `daily_evaluations`.
public struct DailyEvaluationRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "daily_evaluations"
    
    public var id: String { evaluationDate }
    public let evaluationDate: String // 'YYYY-MM-DD'
    public let readinessScore: Int
    public let sleepScore: Int
    public let rhrBaseline: Double
    public let hrvBaseline: Double
    public let aiSynthesisMarkdown: String?
    public let aiModelTag: String?
    public let generatedAt: Int64
    
    public init(
        evaluationDate: String,
        readinessScore: Int,
        sleepScore: Int,
        rhrBaseline: Double,
        hrvBaseline: Double,
        aiSynthesisMarkdown: String? = nil,
        aiModelTag: String? = nil,
        generatedAt: Int64
    ) {
        self.evaluationDate = evaluationDate
        self.readinessScore = readinessScore
        self.sleepScore = sleepScore
        self.rhrBaseline = rhrBaseline
        self.hrvBaseline = hrvBaseline
        self.aiSynthesisMarkdown = aiSynthesisMarkdown
        self.aiModelTag = aiModelTag
        self.generatedAt = generatedAt
    }
}
