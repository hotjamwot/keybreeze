import SwiftUI
import OSLog

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var predictionSession: PredictionSessionViewModel

    @State private var showTypingLab = true
    private let log = Logger(subsystem: "app.keybreeze", category: "menu-bar")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Keybreeze")
                    .font(.headline)

                Spacer()

                // Engine status indicator
                if predictionSession.isSchedulerActive {
                    Circle()
                        .fill(predictionSession.isPredicting ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                }
            }

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

            // Mode toggle: Typing Lab vs compact mode
            HStack {
                Text("Typing Lab")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Toggle("Active", isOn: $predictionSession.isSchedulerActive)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!appState.canRunPrediction)

                Toggle("Expand", isOn: $showTypingLab)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if showTypingLab {
                TypingLabRootView()
                    .environmentObject(appState)
                    .environmentObject(predictionSession)
            } else {
                // Compact mode: just the playground
                compactPlayground
            }
        }
        .padding()
        .frame(minWidth: 680, minHeight: 600)
        .task {
            await appState.refreshAvailableModelsFromOllama()
        }
    }

    // MARK: — Compact playground (when Typing Lab is collapsed)

    private var compactPlayground: some View {
        VStack(alignment: .leading, spacing: 8) {
            // TextField with ghost overlay
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
                .onKeyPress(.tab) {
                    if predictionSession.isSchedulerActive && !predictionSession.suggestion.isEmpty {
                        predictionSession.acceptSuggestion()
                        return .handled
                    }
                    return .ignored
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
                } else {
                    Text(predictionSession.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Suggestion text preview
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
}