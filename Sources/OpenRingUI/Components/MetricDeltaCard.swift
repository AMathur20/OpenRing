import SwiftUI

/// Status direction for physiological comparisons against rolling 14-day baselines.
public enum MetricDeltaStatus: Sendable {
    case optimal
    case nominal
    case warning
    
    public var color: Color {
        switch self {
        case .optimal: return Theme.optimal
        case .nominal: return Theme.nominal
        case .warning: return Theme.strain
        }
    }
}

/// Reusable biometric card displaying measured nocturnal values alongside 14-day baseline deltas.
public struct MetricDeltaCard: View {
    public let title: String
    public let iconName: String
    public let valueString: String
    public let baselineString: String
    public let deltaString: String
    public let status: MetricDeltaStatus
    
    public init(
        title: String,
        iconName: String,
        valueString: String,
        baselineString: String,
        deltaString: String,
        status: MetricDeltaStatus = .nominal
    ) {
        self.title = title
        self.iconName = iconName
        self.valueString = valueString
        self.baselineString = baselineString
        self.deltaString = deltaString
        self.status = status
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Icon + Title
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.subheadline)
                    .foregroundColor(status.color)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Delta Pill
                Text(deltaString)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.color.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            // Value
            Text(valueString)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            // Baseline Reference
            Text(baselineString)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Theme.secondaryBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
}

