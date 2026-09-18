import Foundation
import OpenRingStorage

/// Deterministic prompt builder formatting physiological biometric tables into Llama-3.2 instruct templates.
/// Strictly enforces FDA SaMD and App Store Guideline 1.4.1 non-diagnostic functional wellness boundaries.
public enum PromptBuilder {
    
    // MARK: - Special Tokens (Llama-3.2 Instruct Format)
    
    public static let bosToken = "<|begin_of_text|>"
    public static let startHeaderToken = "<|start_header_id|>"
    public static let endHeaderToken = "<|end_header_id|>"
    public static let eotToken = "<|eot_id|>"
    
    // MARK: - System Prompt
    
    public static let systemPrompt: String = """
    You are the OpenRing Local Engine, an offline physiological analysis system.
    You specialize in sports science, autonomic nervous system balance, and sleep hygiene.
    Synthesize the user's daily metrics objectively without diagnostic claims or clinical hedging.
    Structure your analysis into three concise paragraphs:
    1. Autonomic Load: Interpret resting heart rate and HRV relative to baseline.
    2. Sleep Architecture: Assess deep, REM, and total duration against recovery needs.
    3. Actionable Recovery Protocol: Provide recommendations for training pacing and rest.
    Keep the total output under 140 words.
    """
    
    // MARK: - Prompt Assembly
    
    /// Constructs the full Llama-3.2 prompt template with special tokens and biometric markdown status table.
    public static func buildPrompt(
        evaluation: DailyEvaluationRecord,
        episode: SleepEpisodeRecord?
    ) -> String {
        let table = buildBiometricStatusTable(evaluation: evaluation, episode: episode)
        
        return """
        \(bosToken)\(startHeaderToken)system\(endHeaderToken)
        \(systemPrompt)\(eotToken)
        \(startHeaderToken)user\(endHeaderToken)
        Computed Biometric Status:
        \(table)
        
        Generate recovery synthesis.\(eotToken)
        \(startHeaderToken)assistant\(endHeaderToken)
        
        """
    }
    
    /// Builds the structured biometric status markdown table comparing nightly vitals against 14-day baselines.
    public static func buildBiometricStatusTable(
        evaluation: DailyEvaluationRecord,
        episode: SleepEpisodeRecord?
    ) -> String {
        let rhrNight = episode?.lowestHeartRate ?? Int(round(evaluation.rhrBaseline))
        let rhrBase = Int(round(evaluation.rhrBaseline))
        let rhrDelta = rhrNight - rhrBase
        let rhrDeltaStr = rhrDelta > 0 ? "Elevated (+\(rhrDelta) bpm)" : (rhrDelta < 0 ? "Favorable (\(rhrDelta) bpm)" : "Nominal (0 bpm)")
        
        let hrvNight = episode?.averageRmssd ?? evaluation.hrvBaseline
        let hrvBase = max(1.0, evaluation.hrvBaseline)
        let hrvPctDelta = ((hrvNight - hrvBase) / hrvBase) * 100.0
        let hrvDeltaStr: String
        if hrvPctDelta <= -15.0 {
            hrvDeltaStr = String(format: "Suppressed (%.1f%%)", hrvPctDelta)
        } else if hrvPctDelta >= 15.0 {
            hrvDeltaStr = String(format: "Elevated (+%.1f%%)", hrvPctDelta)
        } else {
            hrvDeltaStr = String(format: "Balanced (%.1f%%)", hrvPctDelta)
        }
        
        let durationSec = episode?.durationSeconds ?? 0
        let durHours = durationSec / 3600
        let durMins = (durationSec % 3600) / 60
        let targetDurSec = 25200 // 7 hours
        let durDeltaMin = (durationSec - targetDurSec) / 60
        let durDeltaStr = durDeltaMin >= 0 ? "Optimal (+\(durDeltaMin)m)" : "Deficit (\(durDeltaMin)m)"
        
        let deepMin = (episode?.deepSleepSeconds ?? 0) / 60
        let deepDeltaMin = deepMin - 90
        let deepDeltaStr = deepDeltaMin >= 0 ? "Optimal (+\(deepDeltaMin) min)" : "Low (\(deepDeltaMin) min)"
        
        let remMin = (episode?.remSleepSeconds ?? 0) / 60
        let remDeltaMin = remMin - 90
        let remDeltaStr = remDeltaMin >= 0 ? "Optimal (+\(remDeltaMin) min)" : "Low (\(remDeltaMin) min)"
        
        let tempDev = episode?.temperatureDeviation ?? 0.0
        let tempDevStr = tempDev > 0 ? String(format: "+%.2f C", tempDev) : String(format: "%.2f C", tempDev)
        let tempStatusStr = tempDev >= 0.50 ? "Elevated (Strain)" : (tempDev <= -0.50 ? "Suppressed" : "Optimal (Nominal)")
        
        let readinessTier: String
        switch evaluation.readinessScore {
        case 85...100: readinessTier = "Optimal Recovery"
        case 70...84: readinessTier = "Good Recovery"
        case 55...69: readinessTier = "Moderate Recovery"
        default: readinessTier = "Critical Recovery"
        }
        
        let sleepTier: String
        switch evaluation.sleepScore {
        case 85...100: sleepTier = "Optimal Rest"
        case 70...84: sleepTier = "Good Rest"
        default: sleepTier = "Fragmented Rest"
        }
        
        return """
        | Metric | Last Night | 14-Day Baseline | Status Delta |
        |---|---|---|---|
        | Resting Heart Rate (RHR) | \(rhrNight) bpm | \(rhrBase) bpm | \(rhrDeltaStr) |
        | HRV (rMSSD) | \(Int(round(hrvNight))) ms | \(Int(round(hrvBase))) ms | \(hrvDeltaStr) |
        | Total Sleep Duration | \(durHours)h \(durMins)m | 7h 00m (Target) | \(durDeltaStr) |
        | Deep Sleep Duration | \(deepMin) min | 90 min (Target) | \(deepDeltaStr) |
        | REM Sleep Duration | \(remMin) min | 90 min (Target) | \(remDeltaStr) |
        | Thermal Deviation | \(tempDevStr) | 0.00 C | \(tempStatusStr) |
        | Readiness Index | \(evaluation.readinessScore) / 100 | 85 / 100 | \(readinessTier) |
        | Sleep Score | \(evaluation.sleepScore) / 100 | 85 / 100 | \(sleepTier) |
        """
    }
    
    // MARK: - Validation
    
    /// Validates that a generated prompt conforms to Llama-3.2 special token rules and includes structured biometric tables.
    public static func validatePromptStructure(_ prompt: String) -> Bool {
        guard prompt.contains(bosToken),
              prompt.contains("\(startHeaderToken)system\(endHeaderToken)"),
              prompt.contains("\(startHeaderToken)user\(endHeaderToken)"),
              prompt.contains("\(startHeaderToken)assistant\(endHeaderToken)"),
              prompt.contains(eotToken),
              prompt.contains("Computed Biometric Status:"),
              prompt.contains("Resting Heart Rate (RHR)"),
              prompt.contains("HRV (rMSSD)"),
              prompt.contains("without diagnostic claims") else {
            return false
        }
        return true
    }
}

