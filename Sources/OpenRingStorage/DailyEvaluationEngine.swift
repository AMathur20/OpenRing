import Foundation
import OpenRingCore

/// Swift 6 isolated actor responsible for deterministic post-sleep physiological evaluation.
///
/// Orchestrates the end-to-end evaluation pipeline:
/// 1. Correlates nocturnal biometric samples (heart rate, rMSSD) and temperature telemetry with sleep episodes.
/// 2. Calculates Sleep Score (0-100) based on duration, efficiency, deep, and REM sleep (DEC-016).
/// 3. Computes 14-day rolling Exponential Moving Average (EMA) baselines for Resting Heart Rate and HRV.
/// 4. Evaluates daily Readiness Score (0-100) using multi-factor physiological penalty models.
/// 5. Assigns scores to the morning wake-up date (DEC-016) and persists `DailyEvaluationRecord`.
public actor DailyEvaluationEngine {
    
    // MARK: - Dependencies
    
    public let database: DatabaseService
    
    // MARK: - Initialization
    
    public init(database: DatabaseService) {
        self.database = database
    }
    
    // MARK: - Evaluation Pipeline
    
    /// Evaluates a specific sleep episode, updating its biometrics and persisting a `DailyEvaluationRecord`.
    @discardableResult
    public func evaluateSleepSession(
        _ episode: SleepEpisodeRecord,
        timeZone: TimeZone = .current
    ) async throws -> (evaluation: DailyEvaluationRecord, updatedEpisode: SleepEpisodeRecord) {
        // 1. Fetch biometrics and temperatures during the sleep episode window
        let biometrics = try await database.fetchBiometrics(from: episode.startTime, to: episode.endTime)
        let temps = try await database.fetchTemperature(from: episode.startTime, to: episode.endTime)
        
        // 2. Aggregate nocturnal physiological markers
        var lowestHr = episode.lowestHeartRate
        var avgHr = episode.averageHeartRate
        var avgRmssd = episode.averageRmssd
        
        if !biometrics.isEmpty {
            let validHr = biometrics.map(\.heartRateBpm).filter { $0 > 0 }
            if !validHr.isEmpty {
                lowestHr = Int(validHr.min() ?? Double(lowestHr))
                avgHr = validHr.reduce(0.0, +) / Double(validHr.count)
            }
            let validRmssd = biometrics.map(\.rmssdMs).filter { $0 > 0 }
            if !validRmssd.isEmpty {
                avgRmssd = validRmssd.reduce(0.0, +) / Double(validRmssd.count)
            }
        }
        
        var tempDev = episode.temperatureDeviation
        if !temps.isEmpty {
            let validOffsets = temps.map { record in
                record.baselineOffsetCelsius != 0.0 ? record.baselineOffsetCelsius : (record.rawCelsius > 0 ? (record.rawCelsius - 33.0) : 0.0)
            }
            tempDev = validOffsets.reduce(0.0, +) / Double(validOffsets.count)
        }
        
        // 3. Update the sleep episode with correlated biometrics
        let updatedEpisode = SleepEpisodeRecord(
            sessionId: episode.sessionId,
            startTime: episode.startTime,
            endTime: episode.endTime,
            durationSeconds: episode.durationSeconds,
            efficiencyRatio: episode.efficiencyRatio,
            deepSleepSeconds: episode.deepSleepSeconds,
            remSleepSeconds: episode.remSleepSeconds,
            lightSleepSeconds: episode.lightSleepSeconds,
            awakeSeconds: episode.awakeSeconds,
            lowestHeartRate: lowestHr,
            averageHeartRate: avgHr,
            averageRmssd: avgRmssd,
            temperatureDeviation: tempDev
        )
        try await database.saveSleepEpisode(updatedEpisode)
        
        // 4. Determine wake-up evaluation date (DEC-016)
        let evalDate = Self.calculateWakeDate(forEndTimeMs: episode.endTime, timeZone: timeZone)
        
        // 5. Compute Sleep Score (0 - 100)
        let sleepScore = SignalProcessor.computeSleepScore(
            durationSeconds: updatedEpisode.durationSeconds,
            efficiencyRatio: updatedEpisode.efficiencyRatio,
            deepSleepSeconds: updatedEpisode.deepSleepSeconds,
            remSleepSeconds: updatedEpisode.remSleepSeconds
        )
        
        // 6. Retrieve prior daily evaluation to update 14-day EMA baselines
        let priorEvaluation = try await database.fetchLatestDailyEvaluation(before: evalDate)
        
        let nightlyRhr = (lowestHr > 0) ? Double(lowestHr) : (avgHr > 0 ? avgHr : 60.0)
        let nightlyHrv = (avgRmssd > 0) ? avgRmssd : 45.0
        
        let updatedRhrBaseline = SignalProcessor.updateExponentialMovingAverage(
            currentBaseline: priorEvaluation?.rhrBaseline,
            newDailyValue: nightlyRhr,
            windowDays: 14.0
        )
        let updatedHrvBaseline = SignalProcessor.updateExponentialMovingAverage(
            currentBaseline: priorEvaluation?.hrvBaseline,
            newDailyValue: nightlyHrv,
            windowDays: 14.0
        )
        
        // 7. Compute Readiness Score (0 - 100)
        let baselineRhr = priorEvaluation?.rhrBaseline ?? nightlyRhr
        let baselineHrv = priorEvaluation?.hrvBaseline ?? nightlyHrv
        
        let readinessScore = SignalProcessor.computeReadinessScore(
            nightlyRhr: nightlyRhr,
            baselineRhr: baselineRhr,
            nightlyHrv: nightlyHrv,
            baselineHrv: baselineHrv,
            temperatureDeviationCelsius: tempDev,
            sleepEfficiencyPercent: updatedEpisode.efficiencyRatio * 100.0
        )
        
        // 8. Persist Daily Evaluation Record
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let evaluation = DailyEvaluationRecord(
            evaluationDate: evalDate,
            readinessScore: readinessScore,
            sleepScore: sleepScore,
            rhrBaseline: updatedRhrBaseline,
            hrvBaseline: updatedHrvBaseline,
            aiSynthesisMarkdown: priorEvaluation?.aiSynthesisMarkdown,
            aiModelTag: priorEvaluation?.aiModelTag,
            generatedAt: nowMs
        )
        try await database.saveDailyEvaluation(evaluation)
        
        return (evaluation, updatedEpisode)
    }
    
    /// Evaluates the most recent sleep episode in the database.
    @discardableResult
    public func evaluateLatestSession(timeZone: TimeZone = .current) async throws -> DailyEvaluationRecord? {
        guard let latestEpisode = try await database.fetchLatestSleepEpisode() else {
            return nil
        }
        let (eval, _) = try await evaluateSleepSession(latestEpisode, timeZone: timeZone)
        return eval
    }
    
    /// Derives the evaluation calendar date ('YYYY-MM-DD') for a sleep session's end time (DEC-016).
    public static func calculateWakeDate(forEndTimeMs endTimeMs: Int64, timeZone: TimeZone = .current) -> String {
        let date = Date(timeIntervalSince1970: Double(endTimeMs) / 1000.0)
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
