import Testing
import Foundation
@testable import OpenRingAI
@testable import OpenRingCore
@testable import OpenRingStorage

@Suite("OpenRing Edge AI Suite")
struct OpenRingAITests {
    
    @Test("PromptBuilder formats valid Llama-3.2 instruct template")
    func testPromptBuilderFormatting() {
        let eval = DailyEvaluationRecord(
            evaluationDate: "2026-05-08",
            readinessScore: 78,
            sleepScore: 84,
            rhrBaseline: 52.0,
            hrvBaseline: 60.0,
            generatedAt: 1000
        )
        let prompt = PromptBuilder.buildPrompt(evaluation: eval, episode: nil)
        #expect(PromptBuilder.validatePromptStructure(prompt))
    }
}

