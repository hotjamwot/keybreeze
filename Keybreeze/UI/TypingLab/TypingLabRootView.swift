import SwiftUI

/// Main Typing Lab container — the permanent internal development environment
/// for iterating on typing feel, diagnostics, and model tuning.
struct TypingLabRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var predictionSession: PredictionSessionViewModel

    @State private var selectedTab: TypingLabTab = .playground
    @State private var showPlayground = true
    @State private var showDiagnostics = true
    @State private var showHistory = false
    @State private var showPromptEditor = false
    @State private var showParameters = false
    @State private var showShadowMode = false
    @State private var shadowOverlapCount: Int = 0
    @State private var shadowOverlapWords: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Typing Lab")
                    .font(.headline)
                Spacer()
                if predictionSession.isSchedulerActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 8)

            // Tab bar
            Picker("Section", selection: $selectedTab) {
                ForEach(TypingLabTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .playground:
                        typingPlaygroundSection

                        if showDiagnostics {
                            DiagnosticsPanelView()
                        }

                        presetSection

                        if showParameters {
                            ParameterControlsView()
                        }

                        if showPromptEditor {
                            PromptEditorView()
                        }

                    case .diagnostics:
                        DiagnosticsPanelView()
                        ParameterControlsView()

                    case .history:
                        PredictionHistoryView()
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Footer controls
            HStack(spacing: 12) {
                Toggle("Active", isOn: $predictionSession.isSchedulerActive)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!appState.canRunPrediction)

                Text(predictionSession.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Toggle visibility of sections
                if selectedTab == .playground {
                    Toggle("Diag", isOn: $showDiagnostics)
                        .toggleStyle(.button)
                        .font(.caption)
                    Toggle("Params", isOn: $showParameters)
                        .toggleStyle(.button)
                        .font(.caption)
                    Toggle("Prompts", isOn: $showPromptEditor)
                        .toggleStyle(.button)
                        .font(.caption)
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: — Typing Playground

    private var typingPlaygroundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Typing Playground")
                .font(.subheadline.weight(.semibold))

            // Multi-line editor with ghost overlay
            TextField("Start typing…", text: $predictionSession.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(3...10)
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
                        Task { await predictionSession.acceptSuggestion() }
                        return .handled
                    }
                    return .ignored
                }

            // Mode indicator
            if !predictionSession.currentPredictionMode.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(predictionSession.isPredicting ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(predictionSession.currentPredictionMode)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }

            // Suggestion preview
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
                    Spacer()
                    Text("Tab to accept")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }
        }
    }

    // MARK: — Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Behaviour Preset")
                .font(.subheadline.weight(.semibold))

            Picker("Preset", selection: $predictionSession.aggressionPreset) {
                ForEach(AggressionPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

enum TypingLabTab: String, CaseIterable {
    case playground = "Playground"
    case diagnostics = "Diagnostics"
    case history = "History"
}