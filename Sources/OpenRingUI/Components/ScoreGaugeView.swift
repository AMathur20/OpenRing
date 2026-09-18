import SwiftUI

/// Animated circular/radial progress gauge rendering wellness and readiness scores (0-100).
public struct ScoreGaugeView: View {
    public let score: Int
    public let title: String
    public let subtitle: String?
    public let size: CGFloat
    public let lineWidth: CGFloat
    
    public init(
        score: Int,
        title: String,
        subtitle: String? = nil,
        size: CGFloat = 180,
        lineWidth: CGFloat = 14
    ) {
        self.score = score
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.lineWidth = lineWidth
    }
    
    private var clampedScore: Int {
        min(max(score, 0), 100)
    }
    
    private var targetProgress: Double {
        Double(clampedScore) / 100.0
    }
    
    private var scoreColor: Color {
        Theme.scoreColor(for: clampedScore)
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background Track
                Circle()
                    .stroke(
                        scoreColor.opacity(0.18),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                
                // Progress Arc
                Circle()
                    .trim(from: 0.0, to: CGFloat(targetProgress))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [scoreColor.opacity(0.8), scoreColor]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: targetProgress)
                
                // Central Score Typography
                VStack(spacing: 2) {
                    Text("\(clampedScore)")
                        .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(title)
                        .font(.system(size: size * 0.09, weight: .medium, design: .default))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
            }
            .frame(width: size, height: size)
            
            // Subtitle / Status Tier Pill
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(scoreColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(scoreColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
