import SwiftUI

/// Scrolling timeline of recent predictions with metadata for identifying failure modes
/// and evaluating prediction quality.
struct PredictionHistoryView: View {
    @EnvironmentObject private var predictionSession: PredictionSessionViewModel

    @State private var selectedResolution: PredictionResolution?
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with summary stats
            HStack {
                Label("Prediction History", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Clear") {
                    predictionSession.predictionHistory.clear()
                }
                .font(.caption)
                .disabled(predictionSession.predictionHistory.allRecords.isEmpty)
            }

            let history = predictionSession.predictionHistory
            HStack(spacing: 16) {
                statBadge(label: "Total", value: "\(history.allRecords.count)")
                statBadge(label: "Accepted", value: "\(history.count(resolution: .accepted))", color: .green)
                statBadge(label: "Ignored", value: "\(history.count(resolution: .ignored))", color: .yellow)
                statBadge(label: "Cancelled", value: "\(history.count(resolution: .cancelled))", color: .orange)
                statBadge(label: "Accept", value: String(format: "%.0f%%", history.acceptanceRate * 100))
            }
            .font(.caption.monospacedDigit())

            // Filter by resolution
            HStack {
                Text("Filter:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            // Scrolling list
            if filteredRecords.isEmpty {
                VStack(spacing: 8) {
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
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var filteredRecords: [PredictionRecord] {
        let records = predictionSession.predictionHistory.allRecords
        guard let selectedResolution else { return records }
        return records.filter { $0.resolution == selectedResolution }
    }

    private func statBadge(label: String, value: String, color: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label): \(value)")
                .foregroundStyle(.secondary)
        }
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
        let (color, label) = switch resolution {
        case .accepted: (Color.green, "A")
        case .ignored: (Color.yellow, "I")
        case .invalidated: (Color.orange, "INV")
        case .cancelled: (Color.gray, "X")
        case .rejected: (Color.red, "R")
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func formattedMS(_ interval: TimeInterval) -> String {
        String(format: "%.0fms", interval * 1000)
    }
}

