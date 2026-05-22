import SwiftUI

/// Main settings window — macOS preferences-style grouped form with tabs.
/// Minimal for now: contains a General pane and embeds Typing Lab.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .environmentObject(sessionVM)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            TypingLabSettingsView()
                .environmentObject(appState)
                .environmentObject(sessionVM)
                .tabItem {
                    Label("Typing Lab", systemImage: "laptopcomputer.trianglebadge.exclamationmark")
                }
        }
        .frame(minWidth: 580, minHeight: 480)
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel

    /// Tracks whether AX permissions have been granted.
    /// Refreshed when the view appears.
    @State private var accessibilityGranted: Bool = false

    var body: some View {
        Form {
            // MARK: - Active Toggle
            Section {
                HStack {
                    Text(sessionVM.isSchedulerActive ? "Disable Keybreeze" : "Enable Keybreeze")
                        .font(.body)
                    Spacer()
                    Button(action: {
                        sessionVM.isSchedulerActive.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(sessionVM.isSchedulerActive ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(sessionVM.isSchedulerActive ? "Disable Keybreeze" : "Enable Keybreeze")
                                .font(.caption2)
                                .foregroundStyle(sessionVM.isSchedulerActive ? .green : .orange)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.canRunPrediction)
                }

                // AX Permission status.
                // NOTE: We check status on appear only. The AX permission dialog
                // returns focus to the app after the user grants/denies, which
                // triggers .onAppear again so the status updates correctly.
                HStack {
                    Label(accessibilityGranted ? "Accessibility Access Granted" : "Accessibility Access Required",
                          systemImage: accessibilityGranted ? "hand.raised.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(accessibilityGranted ? .secondary : .orange)
                        .font(.body)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Grant AX Access") {
                            AccessibilityManager.shared.requestAccessibility()
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }
                .onAppear {
                    refreshAXStatus()
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Keybreeze requires Accessibility access to read and insert text in other apps.")
            }

            // MARK: - Model
            Section {
                Picker("Backend", selection: $appState.selectedBackend) {
                    ForEach(LLMBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                if appState.availableModels.isEmpty {
                    HStack {
                        Text("Model")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appState.modelCatalogStatus.isEmpty ? "Loading..." : appState.modelCatalogStatus)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Picker("Model", selection: $appState.selectedModel) {
                        ForEach(appState.availableModels) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
            } header: {
                Text("LLM Provider")
            } footer: {
                Text("Choose the backend and model used for inline predictions.")
            }

            // MARK: - Today's Stats
            Section {
                HStack {
                    Text("Keys Breezed Today")
                    Spacer()
                    Text("[\(sessionVM.dailyAcceptedCount)]")
                        .foregroundStyle(.secondary)
                        .font(.body.monospacedDigit())
                }
            } header: {
                Text("Statistics")
            }
        }
    }

    /// Refresh the AX permission status from the AccessibilityManager.
    private func refreshAXStatus() {
        accessibilityGranted = AccessibilityManager.shared.checkAccessibility()
    }
}

// MARK: - Typing Lab

struct TypingLabSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel

    var body: some View {
        TypingLabRootView()
            .environmentObject(appState)
            .environmentObject(sessionVM)
    }
}