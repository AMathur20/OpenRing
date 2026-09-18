import Foundation
import OpenRingCore
import OpenRingStorage

/// Swift 6 isolated actor coordinating edge LLM inference, lifecycle memory management,
/// and automated database persistence of AI recovery coaching summaries.
///
/// Enforces critical safety constraints:
/// 1. Foreground-only execution gate (blocking execution during background sync to prevent iOS Jetsam SIGKILL eviction).
/// 2. Non-clinical functional recovery framing (<140 words, 3 paragraphs) strictly adhering to FDA SaMD boundaries.
/// 3. Automatic SQLite WAL persistence of generated markdown advice to `daily_evaluations`.
public actor LLMInferenceService {
    
    // MARK: - Dependencies & State
    
    public let database: DatabaseService?
    public let backend: InferenceBackend
    public private(set) var isForeground: Bool
    public private(set) var isBusy: Bool = false
    public private(set) var modelPath: String?
    
    // MARK: - Initialization
    
    public init(
        backend: InferenceBackend,
        database: DatabaseService? = nil,
        isForeground: Bool = true
    ) {
        self.backend = backend
        self.database = database
        self.isForeground = isForeground
    }
    
    // MARK: - Lifecycle & Memory Management
    
    /// Loads the quantized GGUF model into memory and prepares GPU buffers.
    public func loadModel(at path: String) async throws {
        try await backend.loadModel(at: path)
        self.modelPath = path
    }
    
    /// Unloads the model from RAM/VRAM to release memory under system pressure (e.g. `didReceiveMemoryWarning`).
    public func unloadModel() async {
        await backend.unloadModel()
        self.modelPath = nil
    }
    
    /// Updates the application lifecycle state.
    /// When `isForeground` is false, all inference requests are immediately rejected to prevent background Jetsam termination.
    public func setForeground(_ foreground: Bool) {
        self.isForeground = foreground
    }
    
    // MARK: - Recovery Synthesis Pipeline
    
    /// Generates a streaming physiological recovery coaching synthesis for a specific date ('YYYY-MM-DD').
    /// Automatically updates the `DailyEvaluationRecord` in SQLite upon completion.
    public func synthesizeDailyRecovery(
        for date: String,
        maxTokens: Int = 256
    ) async throws -> AsyncStream<String> {
        // 1. Jetsam Protection Gate
        guard isForeground else {
            throw InferenceError.backgroundExecutionBlocked
        }
        
        // 2. Concurrency Gate
        guard !isBusy else {
            throw InferenceError.serviceBusy
        }
        
        // 3. Retrieve Records from Storage
        guard let database = database else {
            throw InferenceError.evaluationRecordNotFound("DatabaseService dependency not provided")
        }
        
        guard let evaluation = try await database.fetchDailyEvaluation(for: date) else {
            throw InferenceError.evaluationRecordNotFound(date)
        }
        
        let episode = try await database.fetchLatestSleepEpisode()
        
        // 4. Construct Formatted Llama-3.2 Prompt
        let prompt = PromptBuilder.buildPrompt(evaluation: evaluation, episode: episode)
        
        // 5. Execute Inference via Backend
        isBusy = true
        let rawStream = try await backend.generate(prompt: prompt, maxTokens: maxTokens)
        let backendTag = backend.modelTag
        
        return AsyncStream { continuation in
            Task { [weak self] in
                var accumulatedText = ""
                
                for await token in rawStream {
                    accumulatedText.append(token)
                    continuation.yield(token)
                }
                continuation.finish()
                
                guard let self = self else { return }
                
                // 6. Update SQLite Daily Evaluation Record with AI Markdown
                let updatedEvaluation = DailyEvaluationRecord(
                    evaluationDate: evaluation.evaluationDate,
                    readinessScore: evaluation.readinessScore,
                    sleepScore: evaluation.sleepScore,
                    rhrBaseline: evaluation.rhrBaseline,
                    hrvBaseline: evaluation.hrvBaseline,
                    aiSynthesisMarkdown: accumulatedText,
                    aiModelTag: backendTag,
                    generatedAt: evaluation.generatedAt
                )
                
                do {
                    try await database.saveDailyEvaluation(updatedEvaluation)
                } catch {
                    print("⚠️ [LLMInferenceService] Failed to persist AI synthesis to SQLite: \(error.localizedDescription)")
                }
                
                await self.setBusy(false)
            }
        }
    }
    
    /// Directly streams generated tokens for an arbitrary prompt, respecting the Jetsam foreground gate.
    public func streamCustomPrompt(
        _ prompt: String,
        maxTokens: Int = 256
    ) async throws -> AsyncStream<String> {
        guard isForeground else {
            throw InferenceError.backgroundExecutionBlocked
        }
        guard !isBusy else {
            throw InferenceError.serviceBusy
        }
        
        isBusy = true
        let stream = try await backend.generate(prompt: prompt, maxTokens: maxTokens)
        
        return AsyncStream { continuation in
            Task { [weak self] in
                for await token in stream {
                    continuation.yield(token)
                }
                continuation.finish()
                await self?.setBusy(false)
            }
        }
    }
    
    private func setBusy(_ busy: Bool) {
        self.isBusy = busy
    }
}
