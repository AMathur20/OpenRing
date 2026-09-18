import SwiftUI
import OpenRingCore
import OpenRingStorage

/// Tab 1: Daily Readiness Dashboard View (DEC-018).
public struct ReadinessDashboardView: View {
    @ObservedObject public var viewModel: DashboardViewModel
    
    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Top BLE Ring Status Banner
                    bleStatusBar
                    
                    if !viewModel.hasEvaluation {
                        emptyStateCard
                    } else {
                        // Central Radial Readiness Gauge
                        ScoreGaugeView(
                            score: viewModel.readinessScore,
                            title: "Readiness",
                            subtitle: viewModel.readinessTitle,
                            size: 190,
                            lineWidth: 16
                        )
                        .padding(.vertical, 8)
                        
                        // 2x2 Grid of Physiological Metric Cards
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                            MetricDeltaCard(
                                title: "Resting HR",
                                iconName: "heart.fill",
                                valueString: "\(viewModel.rhrValue) bpm",
                                baselineString: "14d Base: \(viewModel.rhrBaseline) bpm",
                                deltaString: viewModel.rhrDeltaString,
                                status: viewModel.rhrStatus
                            )
                            
                            MetricDeltaCard(
                                title: "HRV (rMSSD)",
                                iconName: "waveform.path.ecg",
                                valueString: "\(viewModel.hrvValue) ms",
                                baselineString: "14d Base: \(viewModel.hrvBaseline) ms",
                                deltaString: viewModel.hrvDeltaString,
                                status: viewModel.hrvStatus
                            )
                            
                            MetricDeltaCard(
                                title: "Temperature",
                                iconName: "thermometer.medium",
                                valueString: String(format: "%+.2f °C", viewModel.tempDeviation),
                                baselineString: "Baseline: 0.00 °C",
                                deltaString: viewModel.tempDeltaString,
                                status: viewModel.tempStatus
                            )
                            
                            MetricDeltaCard(
                                title: "Sleep Efficiency",
                                iconName: "bed.double.fill",
                                valueString: "\(viewModel.sleepEfficiencyPct)%",
                                baselineString: "Target: >= 85%",
                                deltaString: "\(viewModel.sleepEfficiencyPct)%",
                                status: viewModel.sleepEfficiencyStatus
                            )
                        }
                        
                        // Autonomic Load Summary Card
                        autonomicSummaryCard
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Readiness")
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.refresh()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var bleStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bleStatusColor)
                .frame(width: 8, height: 8)
            
            Text(bleStatusTitle)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Spacer()
            
            if let battery = viewModel.ringBattery {
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon(for: battery))
                        .font(.caption)
                        .foregroundColor(battery > 20 ? .secondary : Theme.critical)
                    Text("\(battery)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.secondaryBackground)
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.secondaryBackground)
        .cornerRadius(10)
    }
    
    private var emptyStateCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            
            Text("No Telemetry Synced Yet")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Connect your Oura Ring in the Settings tab to sync nocturnal biometrics and compute today's readiness score.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(20)
        .background(Theme.secondaryBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
    
    private var autonomicSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt.heart")
                    .foregroundColor(Theme.scoreColor(for: viewModel.readinessScore))
                Text("Autonomic Balance")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            Text(autonomicDescription)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.secondaryBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Computed Status Helpers
    
    private var bleStatusColor: Color {
        switch viewModel.bleState {
        case .connected: return Theme.optimal
        case .connecting, .authenticating, .discoveringServices: return Theme.strain
        case .error: return Theme.critical
        default: return .secondary
        }
    }
    
    private var bleStatusTitle: String {
        switch viewModel.bleState {
        case .connected: return "Oura Ring Connected"
        case .connecting: return "Connecting to Ring..."
        case .authenticating: return "Authenticating Session..."
        case .discoveringServices: return "Discovering Services..."
        case .scanning: return "Scanning for Ring..."
        case .error(let msg): return "Error: \(msg)"
        default: return "Ring Disconnected"
        }
    }
    
    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        default: return "battery.25"
        }
    }
    
    private var autonomicDescription: String {
        switch viewModel.readinessScore {
        case 85...100:
            return "Parasympathetic tone is dominant with stable resting heart rate and strong HRV rMSSD relative to your 14-day baseline. Your body is primed for full training capacity."
        case 70...84:
            return "Physiological recovery is nominal. Mild baseline deviations are well within expected autonomic equilibrium for standard daily activity."
        case 55...69:
            return "Moderate sympathetic dominance detected. Elevated resting heart rate or HRV suppression suggests accumulated systemic fatigue or thermal strain."
        default:
            return "Marked autonomic strain observed. Prioritize passive recovery, hydration, and sleep hygiene to facilitate cardiovascular and cellular restoration."
        }
    }
}
