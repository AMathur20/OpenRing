import Testing
import Foundation
@testable import OpenRingStorage

@Suite("SQLite GRDB WAL Storage Tests")
struct DatabaseServiceTests {
    
    @Test("Database initialization in memory and migration execution")
    func testDatabaseInit() async throws {
        let dbService = try DatabaseService(inMemory: true)
        
        let evaluations = try await dbService.fetchLatestDailyEvaluations(limit: 10)
        #expect(evaluations.isEmpty)
    }
    
    @Test("Save and range query biometric samples")
    func testBiometricSamplePersistence() async throws {
        let dbService = try DatabaseService(inMemory: true)
        
        let sample1 = BiometricSampleRecord(
            timestamp: 1715000000000,
            heartRateBpm: 54.0,
            rmssdMs: 65.0,
            motionIntensity: 0.2,
            ppgSignalQuality: 0.95
        )
        let sample2 = BiometricSampleRecord(
            timestamp: 1715000300000,
            heartRateBpm: 52.0,
            rmssdMs: 70.0,
            motionIntensity: 0.1,
            ppgSignalQuality: 0.98
        )
        
        try await dbService.saveBiometricSamples([sample1, sample2])
        
        let fetched = try await dbService.fetchBiometrics(from: 1715000000000, to: 1715000500000)
        #expect(fetched.count == 2)
        #expect(fetched[0].heartRateBpm == 54.0)
        #expect(fetched[1].heartRateBpm == 52.0)
    }
    
    @Test("Save and query daily evaluation record")
    func testDailyEvaluationPersistence() async throws {
        let dbService = try DatabaseService(inMemory: true)
        
        let eval = DailyEvaluationRecord(
            evaluationDate: "2026-09-16",
            readinessScore: 84,
            sleepScore: 88,
            rhrBaseline: 52.0,
            hrvBaseline: 64.0,
            aiSynthesisMarkdown: "Your autonomic recovery is optimal today.",
            aiModelTag: "Llama-3.2-3B-Instruct-Q4_K_M",
            generatedAt: 1715010000000
        )
        
        try await dbService.saveDailyEvaluation(eval)
        
        let records = try await dbService.fetchLatestDailyEvaluations(limit: 1)
        #expect(records.count == 1)
        #expect(records[0].evaluationDate == "2026-09-16")
        #expect(records[0].readinessScore == 84)
        #expect(records[0].aiModelTag == "Llama-3.2-3B-Instruct-Q4_K_M")
    }
}

