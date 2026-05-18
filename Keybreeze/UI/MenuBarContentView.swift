import SwiftUI
import OSLog

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var predictionSession: PredictionSessionViewModel

    @State private var showTuning = false
    private let log = Logger(subsystem: "app.keybreeze", category: "menu-bar")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keybreeze")
                .font(.headline)

            // Model selector row
            HStack {
                Group {
                    if appState.availableModels.isEmpty {
                        Text("No models loaded yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Picker("Model", selection: $appState.selectedModel) {
                            ForEach(appState.availableModels) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: appState.selectedModel) { _, newModel in
                            log.info("Selected model: \(newModel.ollamaId) (\(newModel.displayName))")
                            if predictionSession.tuningEnabled {
                                predictionSession.syncTuningFromModel()
                            }
                        }
                    }
                }

                Button("Refresh") {
                    Task { await appState.refreshAvailableModelsFromOllama() }
                }
                .disabled(predictionSession.isPredicting)
            }

            // Catalog status (connection errors, empty list)
            if !appState.modelCatalogStatus.isEmpty {
                Text(appState.modelCatalogStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            liveTypingSection

            if showTuning {
                Divider()
                tuningSection
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 300)
        .task {
            await appState.refreshAvailableModelsFromOllama()
        }
    }

    // MARK: — Live typing with inline ghost text (Phase 2.5)

    private var liveTypingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live typing (Phase 2.5)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Active", isOn: $predictionSession.isSchedulerActive)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!appState.canRunPrediction)
            }

            // TextField with ghost overlay pinned to its exact geometry.
            // Use plain style + custom border so overlay is visible (no opaque bg).
            TextField("Type here…", text: $predictionSession.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(4 ... 8)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                        .fill(.background)
                )
                .disabled(!predictionSession.isSchedulerActive)
                .onChange(of: predictionSession.draftText) { _, _ in
                    predictionSession.draftTextChanged()
                }
                .overlay(alignment: .topLeading) {
                    if predictionSession.isSchedulerActive,
                       !predictionSession.suggestion.isEmpty {
                        (Text(predictionSession.draftText).foregroundColor(.clear)
                         + Text(predictionSession.suggestion).foregroundColor(.secondary.opacity(0.35)))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }

            // Status line
            HStack(spacing: 12) {
                if predictionSession.isSchedulerActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(predictionSession.isPredicting ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(predictionSession.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !predictionSession.currentPredictionMode.isEmpty {
                        Text(predictionSession.currentPredictionMode)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }

                    Spacer()

                    Button(showTuning ? "Hide Tuning" : "Tuning") {
                        showTuning.toggle()
                        if showTuning && !predictionSession.tuningEnabled {
                            predictionSession.tuningEnabled = true
                            predictionSession.syncTuningFromModel()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)
                } else {
                    Text(predictionSession.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Suggestion text preview (below the field, for easy reading)
            if predictionSession.isSchedulerActive && !predictionSession.suggestion.isEmpty {
                HStack(spacing: 0) {
                    Text("→ ")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(predictionSession.suggestion)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: — Runtime tuning controls

    @ViewBuilder
    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Runtime Tuning")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Override", isOn: $predictionSession.tuningEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: predictionSession.tuningEnabled) { _, enabled in
                        if enabled {
                            predictionSession.syncTuningFromModel()
                        }
                    }
            }

            Group {
                tuningSlider(label: "Verbosity", value: $predictionSession.verbosityBias, range: 0.0 ... 1.0)
                tuningSlider(label: "Continuation", value: $predictionSession.continuationBias, range: 0.0 ... 1.0)
                tuningSlider(label: "Strictness", value: $predictionSession.instructionStrictness, range: 0.0 ... 1.0)
            }
            .disabled(!predictionSession.tuningEnabled)

            HStack {
                Text("Max words:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $predictionSession.tuningMaxWords) {
                    Text("Model default").tag(0)
                    ForEach(2 ... 20, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!predictionSession.tuningEnabled)
            }
            .padding(.top, 2)
        }
    }

    private func tuningSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(label):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: value, in: range)
        }
    }
}