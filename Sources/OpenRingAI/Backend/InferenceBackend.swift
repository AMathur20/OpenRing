import Foundation

/// Errors that can occur within the Edge AI inference engine and pipeline.
public enum InferenceError: Error, LocalizedError, Equatable {
    /// Thrown when an inference operation is attempted while the application is in the background.
    /// Protects against iOS Jetsam memory eviction (enforcing the 30-60 MB background memory limit).
    case backgroundExecutionBlocked
    
    /// Thrown when an inference request is dispatched while another generation is actively executing.
    case serviceBusy
    
    /// Thrown when inference is attempted before weights have been initialized.
    case modelNotLoaded
    
    /// Thrown when the model file cannot be found or fails to initialize.
    case modelLoadFailed(String)
    
    /// Thrown when memory context allocation fails for the specified context window.
    case contextAllocationFailed
    
    /// Thrown when the autoregressive generation loop encounters an unrecoverable failure.
    case generationFailed(String)
    
    /// Thrown when a daily evaluation record or associated sleep session is missing in SQLite.
    case evaluationRecordNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .backgroundExecutionBlocked:
            return "Inference blocked: Edge AI execution is restricted to foreground to prevent iOS Jetsam memory termination."
        case .serviceBusy:
            return "Inference service is currently busy generating an active synthesis."
        case .modelNotLoaded:
            return "Model weights are not loaded. Call loadModel(at:) prior to generation."
        case .modelLoadFailed(let details):
            return "Failed to load model weights: \(details)"
        case .contextAllocationFailed:
            return "Failed to allocate inference context memory."
        case .generationFailed(let details):
            return "Generation failed: \(details)"
        case .evaluationRecordNotFound(let date):
            return "No daily evaluation record found for date: \(date)"
        }
    }
}

/// Abstract backend interface for local edge LLM inference engines.
/// Implementations must be `Sendable` to safely execute across Swift 6 concurrency domains.
public protocol InferenceBackend: Sendable {
    /// Indicates whether model weights and execution context are currently active in RAM/VRAM.
    var isLoaded: Bool { get async }
    
    /// Human-readable identifier for the active model architecture and quantization tag (e.g. "Llama-3.2-3B-Instruct-Q4_K_M").
    var modelTag: String { get }
    
    /// Loads model weights from the local filesystem into memory / Metal GPU buffers.
    func loadModel(at path: String) async throws
    
    /// Unloads model weights and releases all associated GPU context memory.
    func unloadModel() async
    
    /// Autoregressively streams generated tokens for a formatted prompt string.
    func generate(prompt: String, maxTokens: Int) async throws -> AsyncStream<String>
}

