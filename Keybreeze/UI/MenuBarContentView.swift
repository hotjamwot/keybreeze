import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var predictionTest: PredictionTestViewModel
    @EnvironmentObject private var predictionSession: PredictionSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keybreeze")
                .font(.headline)

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
                    }
                }

                Button("Refresh") {
                    Task { await appState.refreshAvailableModelsFromOllama() }
                }
                .disabled(predictionTest.isRunning || predictionSession.isPredicting)
            }

            if !appState.modelCatalogStatus.isEmpty {
                Text(appState.modelCatalogStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            liveTypingSection

            Divider()

            testHarnessSection
        }
        .padding()
        .frame(minWidth: 360)
        .task {
            await appState.refreshAvailableModelsFromOllama()
        }
    }

    private var liveTypingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live typing (Phase 2)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Active", isOn: $predictionSession.isSchedulerActive)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!appState.canRunPrediction)
            }

            TextField("Type here…", text: $predictionSession.draftText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3 ... 6)
                .disabled(!predictionSession.isSchedulerActive)
                .onChange(of: predictionSession.draftText) { _, _ in
                    predictionSession.draftTextChanged()
                }

            HStack(alignment: .top, spacing: 8) {
                Text("Suggestion:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(predictionSession.suggestion.isEmpty ? "—" : predictionSession.suggestion)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            Text(predictionSession.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var testHarnessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One-shot test (Phase 1)")
                .font(.subheadline.weight(.semibold))

            Text("Sample: \(PredictionTestViewModel.samplePrefix)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button("Test Prediction") {
                    predictionTest.runTestPrediction()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!appState.canRunPrediction || predictionTest.isRunning)

                Button("Cancel") {
                    predictionTest.cancel()
                }
                .disabled(!predictionTest.isRunning)
            }

            Text(predictionTest.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(predictionTest.streamedText.isEmpty ? " " : predictionTest.streamedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .font(.body.monospaced())
            }
            .frame(minHeight: 80)
        }
    }
}
