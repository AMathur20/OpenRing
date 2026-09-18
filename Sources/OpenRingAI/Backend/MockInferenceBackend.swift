import Foundation

/// Swift 6 isolated actor simulating local LLM inference for hermetic offline testing and CI workflows.
/// Emits streaming token chunks matching the 3-paragraph sports physiology output standard.
public actor MockInferenceBackend: InferenceBackend {
    
    // MARK: - State
    
    public private(set) var isLoaded: Bool
    public nonisolated let modelTag: String
    public var tokenDelayNanos: UInt64
    
    // MARK: - Initialization
    
    public init(
        modelTag: String = "mock-llama-3.2-3b-q4",
        isLoadedInitially: Bool = false,
        tokenDelayNanos: UInt64 = 0
    ) {
        self.modelTag = modelTag
        self.isLoaded = isLoadedInitially
        self.tokenDelayNanos = tokenDelayNanos
    }
    
    // MARK: - InferenceBackend Implementation
    
    public func loadModel(at path: String) async throws {
        guard !path.isEmpty else {
            throw InferenceError.modelLoadFailed("Empty model path provided")
        }
        isLoaded = true
    }
    
    public func unloadModel() async {
        isLoaded = false
    }
    
    public func setTokenDelay(nanoseconds: UInt64) {
        self.tokenDelayNanos = nanoseconds
    }
    
    public func generate(prompt: String, maxTokens: Int = 256) async throws -> AsyncStream<String> {
        guard isLoaded else {
            throw InferenceError.modelNotLoaded
        }
        
        let tokens = generateSimulatedTokens(for: prompt)
        let delay = self.tokenDelayNanos
        
        return AsyncStream { continuation in
            Task {
                for token in tokens {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }
    
    // MARK: - Simulated Output Token Generator
    
    private func generateSimulatedTokens(for prompt: String) -> [String] {
        // Detect if the prompt indicates strain or optimal recovery
        let isStrained = prompt.contains("Critical Recovery") || prompt.contains("Suppressed") || prompt.contains("Elevated (Strain)")
        
        if isStrained {
            return [
                "Your ", "resting ", "heart ", "rate ", "elevation ", "alongside ", "marked ", "rMSSD ", "suppression ",
                "reflects ", "acute ", "sympathetic ", "dominance, ", "compounded ", "by ", "nocturnal ",
                "thermal ", "elevation.\n\n",
                "Sleep ", "architecture ", "demonstrated ", "truncated ", "deep ", "and ", "REM ", "cycles, ",
                "limiting ", "physical ", "restoration, ", "cellular ", "repair, ", "and ", "optimal ",
                "neurological ", "recovery.\n\n",
                "Protocol: ", "Avoid ", "high-intensity ", "training ", "today. ", "Prioritize ", "hydration, ",
                "parasympathetic ", "breathwork, ", "and ", "target ", "an ", "earlier ", "bedtime ", "window."
            ]
        } else {
            return [
                "Your ", "resting ", "heart ", "rate ", "remains ", "nominal ", "relative ", "to ", "baseline, ",
                "while ", "HRV ", "rMSSD ", "indicates ", "robust ", "parasympathetic ", "tone ", "and ",
                "cardiovascular ", "readiness.\n\n",
                "Sleep ", "architecture ", "showed ", "balanced ", "deep ", "and ", "REM ", "stages, ",
                "providing ", "complete ", "neurological ", "consolidation ", "and ", "musculoskeletal ",
                "tissue ", "recovery.\n\n",
                "Protocol: ", "Primed ", "for ", "full ", "training ", "capacity ", "today. ", "Maintain ",
                "regular ", "nutrition, ", "hydration ", "pacing, ", "and ", "consistent ", "sleep ", "schedule."
            ]
        }
    }
}
