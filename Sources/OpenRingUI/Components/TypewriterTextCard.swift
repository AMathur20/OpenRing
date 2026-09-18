import SwiftUI

/// Formatted synthesis card with typewriter streaming token rendering and non-diagnostic disclaimers.
public struct TypewriterTextCard: View {
    public let text: String
    public let isStreaming: Bool
    public let modelTag: String
    
    public init(
        text: String,
        isStreaming: Bool = false,
        modelTag: String = "Llama-3.2-3B INT4"
    ) {
        self.text = text
        self.isStreaming = isStreaming
        self.modelTag = modelTag
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Model badge + generation state
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundColor(Theme.nominal)
                    Text(modelTag)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.nominal)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.nominal.opacity(0.12))
                .clipShape(Capsule())
                
                Spacer()
                
                if isStreaming {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Synthesizing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("On-Device / Offline")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Text Body
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No recovery synthesis generated yet today.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Tap 'Synthesize Morning Recovery' to run local edge AI analysis.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.vertical, 8)
            } else {
                Text(text)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                
                if isStreaming {
                    Text("▎")
                        .font(.body)
                        .foregroundColor(Theme.nominal)
                }
            }
            
            Divider()
                .background(Theme.cardBorder)
            
            // Mandatory FDA SaMD & App Store 1.4.1 Disclaimer Footer
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 1)
                
                Text("OpenRing provides athletic recovery and sleep hygiene coaching exclusively for general wellness. It does not provide medical diagnoses or replace clinical care.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
}

