import SwiftUI

/// Live engine diagnostics panel showing real-time metrics about prediction performance.
struct DiagnosticsPanelView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel

    @State private var ttftHistory: [Double] = []
    @State private var totalTimeHistory: [Double] = []
    @State private var latencyTimer: Timer?
    @State private var showCopySuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Engine Diagnostics", systemImage: "chart.bar")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Copy Log") {
                    let log = exportLogs()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log, forType: .string)
                    showCopySuccess = true
                }
                .font(.caption)
                .disabled(sessionVM.predictionHistory.allRecords.isEmpty)
            }
            if showCopySuccess {
                Text("Log copied to clipboard!")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 8)
            }
            let history = sessionVM.predictionHistory
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                diagnosticItem(label: "Backend", value: "\(sessionVM.appState.selectedBackend.displayName)")
                diagnosticItem(label: "Model", value: sessionVM.effectiveModelOption.displayName)
                diagnosticItem(label: "Mode", value: sessionVM.currentPredictionMode.isEmpty ? "—" : sessionVM.currentPredictionMode)
                diagnosticItem(label: "TTFT", value: formattedLatency(history.averageTimeToFirstToken))
                diagnosticItem(label: "Avg Time", value: formattedLatency(history.averageTotalTime))
                diagnosticItem(label: "Cancel Count", value: "\(history.count(resolution: .cancelled))")
                diagnosticItem(label: "Accepted", value: "\(history.count(resolution: .accepted))")
                diagnosticItem(label: "Ignored", value: "\(history.count(resolution: .ignored))")
                diagnosticItem(label: "Accept Rate", value: formattedPercent(history.acceptanceRate))
                diagnosticItem(label: "Context Size", value: "\(sessionVM.draftText.count) chars")
                diagnosticItem(label: "Prediction", value: "\(wordCount(in: sessionVM.suggestion)) words")
            }
            .font(.caption.monospacedDigit())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private func diagnosticItem(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label + ":")
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func formattedLatency(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "—" }
        let ms = interval * 1000
        if ms < 1000 {
            return String(format: "%.0f ms", ms)
        }
        return String(format: "%.1f s", interval)
    }

    private func formattedPercent(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    private func wordCount(in text: String) -> Int {
        return text.split(separator: " ").filter { !$0.isEmpty }.count
    }

    private func exportLogs() -> String {
        let history = sessionVM.predictionHistory
        var log = "=== Keybreeze Diagnostics ===\n"
        log += "Generated: \(Date())\n"
        log += "\n"
        log += "=== Model Parameters ===\n"
        let model = sessionVM.effectiveModelOption
        log += "Model: \(model.displayName) (\(model.ollamaId))\n"
        log += "Temperature: \(sessionVM.temperature)\n"
        log += "Top P: \(sessionVM.topP)\n"
        log += "Repeat Penalty: \(sessionVM.repeatPenalty)\n"
        log += "Confidence Threshold: \(sessionVM.confidenceThreshold)\n"
        log += "\n"
        log += "=== Word Caps ===\n"
        log += "Model maxWords: \(model.maxWords)\n"
        let midType = sessionVM.midTypeWords > 0 ? "\(sessionVM.midTypeWords)" : "default (3)"
        let pause = sessionVM.pauseWords > 0 ? "\(sessionVM.pauseWords)" : "default (5)"
        log += "Mid-Type cap: \(midType)\n"
        log += "Pause cap: \(pause)\n"
        log += "\n"
        log += "=== Recent Predictions (last 20) ===\n"
        for record in history.allRecords.suffix(20) {
            log += "\n"
            log += "\(DateFormatter.localizedString(from: record.timestamp, dateStyle: .short, timeStyle: .short)): "
            log += "\(record.mode) - \(record.resolution.rawValue) - "
            log += "TTFT: \(String(format: "%.0fms", (record.timeToFirstToken ?? 0) * 1000)), "
            log += "Total: \(String(format: "%.0fms", record.totalTime * 1000))\n"
            log += "Context: \(String(record.typedContext.suffix(100)))\n"
            log += "Continuation: \(record.generatedContinuation)\n"
        }
        log += "\n"
        log += "=== Summary ===\n"
        log += "Total Predictions: \(history.allRecords.count)\n"
        log += "Accepted: \(history.count(resolution: .accepted))\n"
        log += "Ignored: \(history.count(resolution: .ignored))\n"
        log += "Cancelled: \(history.count(resolution: .cancelled))\n"
        log += "Acceptance Rate: \(String(format: "%.1f", history.acceptanceRate * 100))%\n"
        log += "Avg TTFT: \(history.averageTimeToFirstToken > 0 ? String(format: "%.0fms", history.averageTimeToFirstToken * 1000) : "—")\n"
        log += "Avg Total Time: \(history.averageTotalTime > 0 ? String(format: "%.0fms", history.averageTotalTime * 1000) : "—")\n"
        log += "Word Caps: midType=\(midType), pause=\(pause)\n"
        return log
    }
}