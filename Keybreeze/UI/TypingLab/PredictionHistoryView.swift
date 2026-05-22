import SwiftUI

/// Scrolling timeline of recent predictions with metadata for identifying failure modes
/// and evaluating prediction quality.
struct PredictionHistoryView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel
    
    @State private var selectedResolution: PredictionResolution?
    
    var body: some View {
        Form {
            // Header Section
            Section {
                HStack {
                    Label("Prediction History", systemImage: "clock.arrow.circlepath")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("Clear") {
                        sessionVM.predictionHistory.clear()
                    }
                    .font(.caption)
                    .disabled(sessionVM.predictionHistory.allRecords.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } header: {
                VStack {
                    Text("Prediction History")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    Divider()
                        .opacity(0.5)
                        .padding(.bottom, 4)
                }
            }

            // Statistics Section
            Section {
                HStack(spacing: 16) {
                    statBadge(label: "Total", value: "\(sessionVM.predictionHistory.allRecords.count)")
                    statBadge(label: "Accepted", value: "\(sessionVM.predictionHistory.count(resolution: .accepted))", color: .green)
                    statBadge(label: "Ignored", value: "\(sessionVM.predictionHistory.count(resolution: .ignored))", color: .yellow)
                    statBadge(label: "Cancelled", value: "\(sessionVM.predictionHistory.count(resolution: .cancelled))", color: .orange)
                    statBadge(label: "Accept", value: String(format: "%.0f%%", sessionVM.predictionHistory.acceptanceRate * 100))
                }
                .font(.body.monospacedDigit())
                // Use standard modifiers (settingsDescription extension exists in SettingsView.swift)
                .font(.system(size: 12))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                VStack {
                    Text("Statistics")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    Divider()
                        .opacity(0.5)
                        .padding(.bottom, 4)
                }
            }

            // Filter Section
            Section {
                HStack(spacing: 12) {
                    Text("Filter:")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)
                    
                    Picker("Resolution", selection: $selectedResolution) {
                        Text("All").tag(nil as PredictionResolution?)
                        ForEach(PredictionResolution.allCases, id: \.self) { res in
                            Text(res.rawValue.capitalized).tag(res as PredictionResolution?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    
                    Spacer()
                    
                    Text("\(filteredRecords.count) records")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } header: {
                VStack {
                    Text("Filter")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    Divider()
                        .opacity(0.5)
                        .padding(.bottom, 4)
                }
            }

            // History List Section
            Section {
                if sessionVM.predictionHistory.allRecords.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No prediction records yet.\nStart typing in the playground to populate history.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    List(filteredRecords.reversed()) { record in
                        PredictionHistoryRow(record: record)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 200)
                }
            } header: {
                VStack {
                    Text("History")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    Divider()
                        .opacity(0.5)
                        .padding(.bottom, 4)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var filteredRecords: [PredictionRecord] {
        let records = sessionVM.predictionHistory.allRecords
        guard let selectedResolution else { return records }
        return records.filter { $0.resolution == selectedResolution }
    }
    
    private func statBadge(label: String, value: String, color: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor).opacity(0.2))
        )
    }
}

// MARK: — Row

struct PredictionHistoryRow: View {
    let record: PredictionRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                resolutionBadge(record.resolution)
                Text(record.modelDisplayName)
                    .font(.caption2.weight(.medium))
                Spacer()
                Text(record.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(formattedMS(record.totalTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            if !record.typedContext.isEmpty {
                Text(record.typedContext.suffix(120))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            if !record.generatedContinuation.isEmpty {
                Text(record.generatedContinuation)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            
            if record.mode != "midType" {
                Text(record.mode)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func resolutionBadge(_ resolution: PredictionResolution) -> some View {
        switch resolution {
        case .accepted:
            Text("A")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.15), in: Capsule())
        case .ignored:
            Text("I")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.yellow.opacity(0.15), in: Capsule())
        case .invalidated:
            Text("INV")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15), in: Capsule())
        case .cancelled:
            Text("X")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.gray)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.gray.opacity(0.15), in: Capsule())
        case .rejected:
            Text("R")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.15), in: Capsule())
        }
    }
    
    private func formattedMS(_ interval: TimeInterval) -> String {
        String(format: "%.0fms", interval * 1000)
    }
}