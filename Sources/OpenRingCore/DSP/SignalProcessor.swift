import Foundation
import Accelerate

/// Deterministic Digital Signal Processing (DSP) and physiological scoring algorithms.
public enum SignalProcessor {
    
    // MARK: - HRV (rMSSD) Calculation
    
    /// Computes Root Mean Square of Successive Differences (rMSSD) in milliseconds from an IBI series.
    /// Applies physiological artifact filtering: rejecting beats < 350ms or > 1800ms, and inter-beat jumps > 300ms.
    public static func computeRmssd(ibiSeries: [Double]) -> Double? {
        // Step 1: Physiological sanity filter (350ms to 1800ms corresponds to ~33 bpm to ~171 bpm)
        var validIBIs: [Double] = []
        for ibi in ibiSeries {
            if ibi >= 350.0 && ibi <= 1800.0 {
                validIBIs.append(ibi)
            }
        }
        
        guard validIBIs.count >= 3 else { return nil }
        
        // Step 2: Compute successive differences with artifact rejection (|diff| <= 300ms)
        var diffSquared: [Double] = []
        for i in 0..<(validIBIs.count - 1) {
            let diff = validIBIs[i + 1] - validIBIs[i]
            if abs(diff) <= 300.0 {
                diffSquared.append(diff * diff)
            }
        }
        
        guard !diffSquared.isEmpty else { return nil }
        
        // Step 3: Mean of squared differences
        var meanSquare: Double = 0.0
        vDSP_meanvD(diffSquared, 1, &meanSquare, vDSP_Length(diffSquared.count))
        
        return sqrt(meanSquare)
    }
    
    // MARK: - Exponential Moving Average (14-Day Baseline)
    
    /// Computes or updates an Exponential Moving Average (EMA) baseline over an N-day window.
    /// alpha = 2.0 / (windowDays + 1.0)
    public static func updateExponentialMovingAverage(currentBaseline: Double?, newDailyValue: Double, windowDays: Double = 14.0) -> Double {
        guard let baseline = currentBaseline else {
            return newDailyValue
        }
        let alpha = 2.0 / (windowDays + 1.0)
        return (newDailyValue * alpha) + (baseline * (1.0 - alpha))
    }
    
    // MARK: - Readiness Score Formula
    
    /// Computes the daily Readiness Index (0 - 100) using the multi-factor penalty model against 14-day rolling baselines:
    /// S_readiness = 100 - (0.35 * Delta_RHR + 0.35 * Delta_HRV + 0.15 * Delta_Temp + 0.15 * (100 - Sleep_Efficiency))
    public static func computeReadinessScore(
        nightlyRhr: Double,
        baselineRhr: Double,
        nightlyHrv: Double,
        baselineHrv: Double,
        temperatureDeviationCelsius: Double,
        sleepEfficiencyPercent: Double
    ) -> Int {
        // Delta RHR penalty: percentage elevation above baseline
        let deltaRhr = max(0.0, ((nightlyRhr - baselineRhr) / max(1.0, baselineRhr)) * 100.0)
        
        // Delta HRV penalty: percentage suppression below baseline
        let deltaHrv = max(0.0, ((baselineHrv - nightlyHrv) / max(1.0, baselineHrv)) * 100.0)
        
        // Temperature penalty: starts when deviation exceeds +0.50 C, scaling by 10 points per 0.10 C
        let deltaTemp = max(0.0, ((temperatureDeviationCelsius - 0.50) / 0.10) * 10.0)
        
        // Sleep efficiency deficit penalty
        let clampedEfficiency = min(100.0, max(0.0, sleepEfficiencyPercent))
        let sleepDeficit = 100.0 - clampedEfficiency
        
        let totalPenalty = (0.35 * deltaRhr) +
                           (0.35 * deltaHrv) +
                           (0.15 * deltaTemp) +
                           (0.15 * sleepDeficit)
        
        let rawScore = 100.0 - totalPenalty
        let clampedScore = min(100.0, max(0.0, rawScore))
        return Int(round(clampedScore))
    }
    
    // MARK: - Sleep Score Formula
    
    /// Computes the nightly Sleep Score (0 - 100) using polysomnography and sleep hygiene standards (DEC-016):
    /// S_sleep = P_duration (35 pts) + P_efficiency (30 pts) + P_deep (20 pts) + P_rem (15 pts)
    public static func computeSleepScore(
        durationSeconds: Int,
        efficiencyRatio: Double,
        deepSleepSeconds: Int,
        remSleepSeconds: Int
    ) -> Int {
        // 1. Duration Points (0 - 35): Target 7 - 9 hours (25,200 - 32,400 seconds)
        let durationHours = Double(durationSeconds) / 3600.0
        let pDuration = min(35.0, max(0.0, (durationHours / 7.0) * 35.0))
        
        // 2. Efficiency Points (0 - 30): Target >= 85% (0.85)
        let clampedEfficiency = min(1.0, max(0.0, efficiencyRatio))
        let pEfficiency: Double
        if clampedEfficiency >= 0.85 {
            pEfficiency = 30.0
        } else {
            pEfficiency = (clampedEfficiency / 0.85) * 30.0
        }
        
        // 3. Deep Sleep Points (0 - 20): Target >= 90 minutes (5,400 seconds)
        let deepMinutes = Double(deepSleepSeconds) / 60.0
        let pDeep = min(20.0, max(0.0, (deepMinutes / 90.0) * 20.0))
        
        // 4. REM Sleep Points (0 - 15): Target >= 90 minutes (5,400 seconds)
        let remMinutes = Double(remSleepSeconds) / 60.0
        let pRem = min(15.0, max(0.0, (remMinutes / 90.0) * 15.0))
        
        let total = pDuration + pEfficiency + pDeep + pRem
        return Int(round(min(100.0, max(0.0, total))))
    }
    
    // MARK: - Sleep Stage Heuristic Fallback
    
    /// Open heuristic fallback classifier for gaps in hardware hypnogram reports (DEC-011).
    public static func classifySleepStageHeuristic(
        heartRateBpm: Double,
        baselineRhr: Double,
        motionIntensity: Double
    ) -> SleepStage {
        if motionIntensity > 0.30 {
            return .awake
        } else if heartRateBpm <= baselineRhr * 0.95 && motionIntensity < 0.05 {
            return .deep
        } else if heartRateBpm > baselineRhr * 1.05 && motionIntensity < 0.15 {
            return .rem
        } else {
            return .light
        }
    }
    
    /// Reconstructs or estimates sleep stages from a sequence of biometric samples when hardware hypnograms are unavailable (DEC-011).
    public static func classifySleepStagesHeuristic(
        samples: [(heartRateBpm: Double, motionIntensity: Double)],
        baselineRhr: Double
    ) -> [SleepStage] {
        return samples.map { sample in
            classifySleepStageHeuristic(
                heartRateBpm: sample.heartRateBpm,
                baselineRhr: baselineRhr,
                motionIntensity: sample.motionIntensity
            )
        }
    }
}

