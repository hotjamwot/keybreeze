import SwiftUI

/// Main Typing Lab container — the permanent internal development environment
/// for iterating on typing feel, diagnostics, and model tuning.
struct TypingLabRootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel

    @State private var selectedTab: TypingLabTab = .playground
    @State private var showPlayground = true
    @State private var showDiagnostics = true
    @State private var showHistory = false
    @State private var showPromptEditor = false
    @State private var showParameters = false
    @State private var showShadowMode = false
    @State private var shadowOverlapCount: Int = 0
    @State private var shadowOverlapWords: Int = 0
    @State private var showAdvancedSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Typing Lab")
                    .font(.headline)
                Spacer()
                if sessionVM.isSchedulerActive {
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
                                .environmentObject(appState)
                                .environmentObject(sessionVM)
                        }

                        presetSection

                        if showParameters {
                            ParameterControlsView(showAdvancedSettings: $showAdvancedSettings)
                                .environmentObject(appState)
                                .environmentObject(sessionVM)
                        }

                        if showPromptEditor {
                            PromptEditorView()
                                .environmentObject(appState)
                                .environmentObject(sessionVM)
                        }

                    case .apps:
                        AppGatingPanelView()
                            .environmentObject(appState)
                            .environmentObject(sessionVM)

                    case .diagnostics:
                        DiagnosticsPanelView()
                            .environmentObject(appState)
                            .environmentObject(sessionVM)
                        ParameterControlsView(showAdvancedSettings: .constant(false))
                            .environmentObject(appState)
                            .environmentObject(sessionVM)

                    case .history:
                        PredictionHistoryView()
                            .environmentObject(appState)
                            .environmentObject(sessionVM)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Footer controls
            HStack(spacing: 12) {
                Toggle("Active", isOn: $sessionVM.isSchedulerActive)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!appState.canRunPrediction)

                Text(sessionVM.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Show latency if available
                if let latency = sessionVM.currentLatency {
                    Text(String(format: "%.1fms", latency * 1000))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }

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

            // Advanced settings toggle
            if selectedTab == .playground {
                Toggle("Show Advanced", isOn: $showAdvancedSettings)
                    .toggleStyle(.button)
                    .font(.caption)
            }
        }
    }

    // MARK: — Typing Playground

    private var typingPlaygroundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Typing Playground")
                .font(.subheadline.weight(.semibold))

            // Multi-line editor with ghost overlay
            TextField("Start typing…", text: $sessionVM.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(3...10)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.background)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .disabled(!sessionVM.isSchedulerActive)
                .onChange(of: sessionVM.draftText) { _, _ in
                    sessionVM.draftTextChanged()
                }
                .ghostText(draftText: $sessionVM.draftText, suggestion: $sessionVM.suggestion, correctionState: $sessionVM.correctionState, isSchedulerActive: $sessionVM.isSchedulerActive)

            // Mode indicator
            if !sessionVM.currentPredictionMode.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(sessionVM.isPredicting ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(sessionVM.currentPredictionMode)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }

            // Suggestion preview
            if sessionVM.isSchedulerActive && !sessionVM.suggestion.isEmpty {
                HStack(spacing: 0) {
                    Text("→ ")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(sessionVM.suggestion)
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

            Picker("Preset", selection: $sessionVM.aggressionPreset) {
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
    case apps = "Apps"
    case diagnostics = "Diagnostics"
    case history = "History"
}
