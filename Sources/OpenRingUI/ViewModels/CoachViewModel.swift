import SwiftUI
import OpenRingCore
import OpenRingStorage
import OpenRingAI

/// MainActor-isolated ViewModel coordinating the Edge AI Recovery Coach (Tab 3).
@MainActor
public final class CoachViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var synthesisText: String = ""
    @Published public private(set) var isGenerating: Bool = false
    @Published public private(set) var modelTag: String = "Llama-3.2-3B INT4"
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var hasEvaluation: Bool = false
    @Published public private(set) var evaluationDate: String = ""
    
    // MARK: - Dependencies
    
    private let database: DatabaseService
    private let inferenceService: LLMInferenceService
    
    // MARK: - Initialization
    
    public init(database: DatabaseService, inferenceService: LLMInferenceService) {
        self.database = database
        self.inferenceService = inferenceService
    }
    
    // MARK: - Actions
    
    public func loadTodaySynthesis(date: String? = nil) async {
        let targetDate = date ?? defaultEvaluationDate()
        self.evaluationDate = targetDate
        
        do {
            if let eval = try await database.fetchDailyEvaluation(for: targetDate) {
                hasEvaluation = true
                if let cachedMarkdown = eval.aiSynthesisMarkdown, !cachedMarkdown.isEmpty {
                    self.synthesisText = cachedMarkdown
                }
                if let tag = eval.aiModelTag, !tag.isEmpty {
                    self.modelTag = tag
                }
            } else if let latest = try await database.fetchLatestDailyEvaluation(before: nil) {
                hasEvaluation = true
                self.evaluationDate = latest.evaluationDate
                if let cachedMarkdown = latest.aiSynthesisMarkdown, !cachedMarkdown.isEmpty {
                    self.synthesisText = cachedMarkdown
                }
                if let tag = latest.aiModelTag, !tag.isEmpty {
                    self.modelTag = tag
                }
            } else {
                hasEvaluation = false
            }
        } catch {
            self.errorMessage = "Failed to load evaluation: \(error.localizedDescription)"
        }
    }
    
    public func generateSynthesis() async {
        guard !isGenerating else { return }
        guard !evaluationDate.isEmpty else {
            self.errorMessage = "No daily evaluation available to synthesize."
            return
        }
        
        self.isGenerating = true
        self.errorMessage = nil
        self.synthesisText = ""
        
        do {
            let stream = try await inferenceService.synthesizeDailyRecovery(for: evaluationDate)
            
            for await token in stream {
                self.synthesisText.append(token)
            }
            
            self.isGenerating = false
        } catch {
            self.isGenerating = false
            self.errorMessage = error.localizedDescription
        }
    }
    
    public func setDirectSynthesis(text: String, modelTag: String = "Llama-3.2-3B INT4") {
        self.synthesisText = text
        self.modelTag = modelTag
        self.hasEvaluation = true
    }
    
    private func defaultEvaluationDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}

