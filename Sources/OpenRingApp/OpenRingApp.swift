import SwiftUI
import OpenRingCore
import OpenRingStorage
import OpenRingAI
import OpenRingUI

/// OpenRing iOS & macOS Application Entry Point (DEC-001, DEC-018).
@main
struct OpenRingApp: App {
    
    // Core Actors
    private let database: DatabaseService
    private let bleEngine: BLEEngine
    private let syncCoordinator: SyncCoordinator
    private let evaluationEngine: DailyEvaluationEngine
    private let inferenceService: LLMInferenceService
    
    init() {
        do {
            // 1. Initialize SQLite Database in WAL mode
            let db = try DatabaseService(inMemory: false)
            self.database = db
            
            // 2. Initialize BLE Engine with saved or newly generated key
            let authKey = (try? OuraAuthCrypto.generateRandomKey()) ?? Data(repeating: 0x01, count: 16)
            let ble = BLEEngine(authKey: authKey)
            self.bleEngine = ble
            
            // 3. Initialize Daily Evaluation Engine & Sync Coordinator
            let evalEngine = DailyEvaluationEngine(database: db)
            self.evaluationEngine = evalEngine
            
            let coordinator = SyncCoordinator(database: db, evaluationEngine: evalEngine)
            self.syncCoordinator = coordinator
            
            // 4. Initialize Edge AI Engine (Metal GPU backend with model path)
            let backend = LlamaCppBackend(modelTag: "Llama-3.2-3B-Instruct-Q4_K_M")
            self.inferenceService = LLMInferenceService(
                backend: backend,
                database: db,
                isForeground: true
            )
            
            // 5. Connect BLE event stream to SyncCoordinator in background task
            Task {
                await coordinator.startSync(from: ble.events)
            }
        } catch {
            fatalError("Failed to initialize OpenRing core subsystem: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView(
                database: database,
                bleEngine: bleEngine,
                inferenceService: inferenceService
            )
            #if os(macOS)
            .frame(minWidth: 700, minHeight: 600)
            #endif
        }
    }
}
