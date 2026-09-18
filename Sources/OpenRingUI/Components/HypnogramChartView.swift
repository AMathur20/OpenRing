import SwiftUI
import Charts
import OpenRingCore

/// Formatted epoch for interactive hypnogram visualization.
public struct HypnogramEpoch: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let stage: SleepStage
    public let stageIndex: Int
    
    public init(
        id: UUID = UUID(),
        timestamp: Date,
        stage: SleepStage
    ) {
        self.id = id
        self.timestamp = timestamp
        self.stage = stage
        switch stage {
        case .deep: self.stageIndex = 0
        case .light: self.stageIndex = 1
        case .rem: self.stageIndex = 2
        case .awake, .unknown: self.stageIndex = 3
        }
    }
    
    public var stageTitle: String {
        switch stage {
        case .deep: return "Deep Sleep"
        case .light: return "Light Sleep"
        case .rem: return "REM Sleep"
        case .awake: return "Awake"
        case .unknown: return "Unknown"
        }
    }
    
    public var color: Color {
        switch stage {
        case .deep: return Theme.deepSleep
        case .light: return Theme.lightSleep
        case .rem: return Theme.remSleep
        case .awake, .unknown: return Theme.awake
        }
    }
}

/// 60 FPS interactive hypnogram chart rendering nocturnal sleep stages with time scrubbing (DEC-018).
public struct HypnogramChartView: View {
    public let epochs: [HypnogramEpoch]
    @Binding public var selectedEpoch: HypnogramEpoch?
    
    public init(epochs: [HypnogramEpoch], selectedEpoch: Binding<HypnogramEpoch?> = .constant(nil)) {
        self.epochs = epochs
        self._selectedEpoch = selectedEpoch
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with active scrub details
            HStack {
                Text("Sleep Architecture")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let selected = selectedEpoch {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(selected.color)
                            .frame(width: 8, height: 8)
                        
                        Text(selected.stageTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(selected.color)
                        
                        Text(selected.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.tertiaryBackground)
                    .cornerRadius(8)
                } else {
                    Text("Touch to inspect")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if epochs.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "bed.double")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No sleep hypnogram data recorded")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(Theme.secondaryBackground)
                .cornerRadius(12)
            } else {
                // Interactive Chart
                Chart {
                    ForEach(epochs) { epoch in
                        BarMark(
                            x: .value("Time", epoch.timestamp, unit: .minute),
                            y: .value("Stage", epoch.stageIndex + 1)
                        )
                        .foregroundStyle(epoch.color)
                    }
                    
                    if let selected = selectedEpoch {
                        RuleMark(x: .value("Selected", selected.timestamp))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                .chartYScale(domain: 0...4)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let intVal = value.as(Int.self) {
                                Text(yAxisLabel(for: intVal - 1))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.hour())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 170)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if let frame = proxy.plotFrame {
                                            let currentX = value.location.x - geometry[frame].origin.x
                                            guard currentX >= 0, currentX <= proxy.plotSize.width else { return }
                                            if let date: Date = proxy.value(atX: currentX) {
                                                selectedEpoch = findNearestEpoch(to: date)
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedEpoch = nil
                                    }
                            )
                    }
                }
                
                // Hypnogram Legend
                HStack(spacing: 12) {
                    legendItem(title: "Deep", color: Theme.deepSleep)
                    legendItem(title: "Light", color: Theme.lightSleep)
                    legendItem(title: "REM", color: Theme.remSleep)
                    legendItem(title: "Awake", color: Theme.awake)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Theme.secondaryBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
    
    private func yAxisLabel(for index: Int) -> String {
        switch index {
        case 0: return "Deep"
        case 1: return "Light"
        case 2: return "REM"
        case 3: return "Awake"
        default: return ""
        }
    }
    
    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func findNearestEpoch(to date: Date) -> HypnogramEpoch? {
        guard !epochs.isEmpty else { return nil }
        return epochs.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
    }
}
