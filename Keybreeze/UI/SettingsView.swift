import SwiftUI

/// Main settings window — macOS preference style with sidebar navigation.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel
    
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case typingLab = "Typing Lab"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .typingLab: return "testtube.2"
            }
        }
    }
    
    @State private var selection: Tab? = .general
    
    var body: some View {
        HSplitView {
            // Sidebar
            List {
                ForEach(Tab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selection == tab
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150, idealWidth: 170, maxWidth: 220)

            // Detail
            Group {
                switch selection {
                case .general:
                    GeneralSettingsView()
                        .environmentObject(appState)
                        .environmentObject(sessionVM)
                case .typingLab:
                    TypingLabView()
                        .environmentObject(appState)
                        .environmentObject(sessionVM)
                case .none:
                    EmptyDetailView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Empty Detail
private struct EmptyDetailView: View {
    var body: some View {
        Text("Select a tab")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - General
struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel
    
    @State private var accessibilityGranted: Bool = false
    
    var body: some View {
        Form {
            // MARK: - Status
            Section {
                Toggle(isOn: Binding(
                    get: { sessionVM.isEnabled },
                    set: { sessionVM.isEnabled = $0 }
                )) {
                    HStack(spacing: 4) {
                        Text(sessionVM.isEnabled ? "Keybreeze is On" : "Keybreeze is Off")
                    }
                }
                .toggleStyle(.switch)
                
                accessibilityRow
            } header: {
                Text("Status")
            } footer: {
                Text("Keybreeze requires Accessibility access to read and insert text in other apps.")
                    .settingsDescription()
            }
            
            // MARK: - Statistics
            Section {
                statisticsCard
            } header: {
                Text("Statistics")
            }
            
            // MARK: - AI Settings
            Section {
                Picker("Backend", selection: $appState.selectedBackend) {
                    ForEach(LLMBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                
                if appState.availableModels.isEmpty {
                    LabeledContent("Model") {
                        Text(appState.modelCatalogStatus.isEmpty ? "Loading..." : appState.modelCatalogStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Model", selection: $appState.selectedModel) {
                        ForEach(appState.availableModels) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
            } header: {
                Text("AI Settings")
            } footer: {
                Text("Configure your LLM provider and model for inline predictions.")
                    .settingsDescription()
            }
            
            // MARK: - Auto completion
            Section {
                Text("Coming soon...")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } header: {
                Text("Auto Completion Options")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            accessibilityGranted = AccessibilityManager.shared.checkAccessibility()
        }
    }
    
    // MARK: - Accessibility Row
    
    @ViewBuilder
    private var accessibilityRow: some View {
        if accessibilityGranted {
            LabeledContent {
                statusPill(label: "Granted", color: .green)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.green)
                    Text("Accessibility Access")
                }
            }
        } else {
            LabeledContent {
                HStack(spacing: 8) {
                    statusPill(label: "Required", color: .orange)
                    Button("Grant Access") {
                        AccessibilityManager.shared.requestAccessibility()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.orange)
                    Text("Accessibility Access")
                }
            }
        }
    }
    
    // MARK: - Statistics Card
    
    private var statisticsCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Keys Breezed Today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(sessionVM.dailyAcceptedCount)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.08))
        )
    }
    
    // MARK: - Status Pill
    
    private func statusPill(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.1)))
    }
}

// MARK: - Helper Extensions
extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }
}