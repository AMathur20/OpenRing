import SwiftUI
import OpenRingCore
import OpenRingStorage
import OpenRingAI

@MainActor
public final class TabNavigationModel: ObservableObject {
    @Published public var selectedTab: Int = 0
    public init(selectedTab: Int = 0) {
        self.selectedTab = selectedTab
    }
}

/// Root 4-tab navigation shell for OpenRing (DEC-018).
public struct MainTabView: View {
    @StateObject private var dashboardVM: DashboardViewModel
    @StateObject private var sleepVM: SleepViewModel
    @StateObject private var coachVM: CoachViewModel
    @StateObject private var settingsVM: SettingsViewModel
    @StateObject private var nav = TabNavigationModel()
    
    public init(
        database: DatabaseService,
        bleEngine: BLEEngine? = nil,
        inferenceService: LLMInferenceService
    ) {
        _dashboardVM = StateObject(wrappedValue: DashboardViewModel(database: database, bleEngine: bleEngine))
        _sleepVM = StateObject(wrappedValue: SleepViewModel(database: database))
        _coachVM = StateObject(wrappedValue: CoachViewModel(database: database, inferenceService: inferenceService))
        _settingsVM = StateObject(wrappedValue: SettingsViewModel(database: database, bleEngine: bleEngine))
    }
    
    public var body: some View {
        TabView(selection: $nav.selectedTab) {
            ReadinessDashboardView(viewModel: dashboardVM)
                .tabItem {
                    Label("Readiness", systemImage: "heart.fill")
                }
                .tag(0)
            
            SleepArchitectureView(viewModel: sleepVM)
                .tabItem {
                    Label("Sleep", systemImage: "bed.double.fill")
                }
                .tag(1)
            
            RecoveryCoachView(viewModel: coachVM)
                .tabItem {
                    Label("Recovery", systemImage: "sparkles")
                }
                .tag(2)
            
            SettingsView(viewModel: settingsVM)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(Theme.nominal)
    }
}
