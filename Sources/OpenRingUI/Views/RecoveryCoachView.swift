import SwiftUI
import OpenRingCore
import OpenRingStorage
import OpenRingAI

/// Tab 3: On-Device Edge AI Recovery Coach View (DEC-004, DEC-005, DEC-012, DEC-018).
public struct RecoveryCoachView: View {
    @ObservedObject public var viewModel: CoachViewModel
    
    public init(viewModel: CoachViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Card: Edge AI Engine Specs
                    engineHeaderCard
                    
                    // Main Recovery Synthesis Card with Live Typewriter Rendering
                    TypewriterTextCard(
                        text: viewModel.synthesisText,
                        isStreaming: viewModel.isGenerating,
                        modelTag: viewModel.modelTag
                    )
                    
                    // Error message display
                    if let err = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.critical)
                            Text(err)
                                .font(.footnote)
                                .foregroundColor(Theme.critical)
                        }
                        .padding(12)
                        .background(Theme.critical.opacity(0.12))
                        .cornerRadius(10)
                    }
                    
                    // Action Trigger Button
                    Button {
                        Task {
                            await viewModel.generateSynthesis()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isGenerating {
                                ProgressView()
                                    .tint(.white)
                                Text("Synthesizing Offline...")
                                    .fontWeight(.semibold)
                            } else {
                                Image(systemName: "sparkles")
                                Text(viewModel.synthesisText.isEmpty ? "Synthesize Morning Recovery" : "Regenerate Coaching")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.white)
                        .background(
                            viewModel.isGenerating ? Theme.nominal.opacity(0.6) : Theme.nominal
                        )
                        .cornerRadius(14)
                    }
                    .disabled(viewModel.isGenerating || !viewModel.hasEvaluation)
                    
                    if !viewModel.hasEvaluation {
                        Text("Sync nightly telemetry to enable AI recovery synthesis.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Recovery")
            .refreshable {
                await viewModel.loadTodaySynthesis()
            }
            .task {
                await viewModel.loadTodaySynthesis()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var engineHeaderCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.nominal.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "apple.terminal")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.nominal)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Edge AI Engine")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("100% Offline")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.optimal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.optimal.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Text("Llama-3.2-3B Quantized INT4 via Apple Metal GPU")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
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

