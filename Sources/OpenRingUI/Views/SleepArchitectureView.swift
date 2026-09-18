import SwiftUI
import OpenRingCore
import OpenRingStorage

/// Tab 2: Sleep Architecture and 60 FPS Hypnogram View (DEC-018).
public struct SleepArchitectureView: View {
    @ObservedObject public var viewModel: SleepViewModel
    
    public init(viewModel: SleepViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !viewModel.hasSleepSession {
                        emptyStateCard
                    } else {
                        // Central Sleep Score Gauge
                        ScoreGaugeView(
                            score: viewModel.sleepScore,
                            title: "Sleep Score",
                            subtitle: viewModel.sleepTitle,
                            size: 190,
                            lineWidth: 16
                        )
                        .padding(.vertical, 8)
                        
                        // 60 FPS Interactive Hypnogram Chart (SwiftUI Charts)
                        HypnogramChartView(
                            epochs: viewModel.hypnogramEpochs,
                            selectedEpoch: $viewModel.selectedEpoch
                        )
                        
                        // Sleep Architecture Stage Durations Breakdown
                        stageBreakdownCard
                        
                        // Nocturnal Vitals Summary Card
                        nocturnalVitalsCard
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Sleep")
            .refreshable {
                await viewModel.loadLatestSleep()
            }
            .task {
                await viewModel.loadLatestSleep()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var stageBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Stage Breakdown")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(viewModel.durationString)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            VStack(spacing: 10) {
                stageProgressRow(
                    title: "Deep Sleep",
                    durationSec: viewModel.deepSleepSeconds,
                    color: Theme.deepSleep,
                    targetText: "Target: >= 1h 30m"
                )
                
                stageProgressRow(
                    title: "REM Sleep",
                    durationSec: viewModel.remSleepSeconds,
                    color: Theme.remSleep,
                    targetText: "Target: >= 1h 30m"
                )
                
                stageProgressRow(
                    title: "Light Sleep",
                    durationSec: viewModel.lightSleepSeconds,
                    color: Theme.lightSleep,
                    targetText: "Core restorative sleep"
                )
                
                stageProgressRow(
                    title: "Awake / Latency",
                    durationSec: viewModel.awakeSeconds,
                    color: Theme.awake,
                    targetText: "Time awake in bed"
                )
            }
        }
        .padding(16)
        .background(Theme.secondaryBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
    
    private func stageProgressRow(
        title: String,
        durationSec: Int,
        color: Color,
        targetText: String
    ) -> some View {
        let total = max(1, viewModel.durationSeconds)
        let fraction = min(1.0, Double(durationSec) / Double(total))
        let hours = durationSec / 3600
        let mins = (durationSec % 3600) / 60
        let timeStr = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        let pct = Int(round(fraction * 100))
        
        return VStack(spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text("\(timeStr) (\(pct)%)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.18))
                        .frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(fraction), height: 6)
                }
            }
            .frame(height: 6)
            
            HStack {
                Text(targetText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
    
    private var nocturnalVitalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nocturnal Vitals")
                .font(.headline)
                .foregroundColor(.primary)
            
            Divider()
                .background(Theme.cardBorder)
            
            HStack {
                vitalMetricItem(
                    title: "Lowest HR",
                    value: "\(viewModel.lowestHeartRate) bpm",
                    icon: "heart.fill",
                    color: Theme.optimal
                )
                
                Spacer()
                
                vitalMetricItem(
                    title: "Avg HR",
                    value: String(format: "%.0f bpm", viewModel.averageHeartRate),
                    icon: "waveform.path",
                    color: Theme.nominal
                )
                
                Spacer()
                
                vitalMetricItem(
                    title: "Avg HRV",
                    value: String(format: "%.0f ms", viewModel.averageRmssd),
                    icon: "waveform.path.ecg",
                    color: Theme.nominal
                )
                
                Spacer()
                
                vitalMetricItem(
                    title: "Temp Offset",
                    value: String(format: "%+.2f °C", viewModel.temperatureDeviation),
                    icon: "thermometer.medium",
                    color: viewModel.temperatureDeviation >= 0.5 ? Theme.strain : Theme.optimal
                )
            }
        }
        .padding(16)
        .background(Theme.secondaryBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
    
    private func vitalMetricItem(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
    }
    
    private var emptyStateCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "bed.double")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            
            Text("No Sleep Sessions Recorded")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Wear your ring overnight. Once synced, your interactive hypnogram and sleep stage breakdown will render here at 60 FPS.")
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
}
