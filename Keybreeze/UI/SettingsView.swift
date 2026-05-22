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

// MARK: - InfoTip

/// Inline information popover that displays helper text when tapped.
/// Used inline inside `HStack(spacing: 4)` next to `Text` labels.
private struct InfoTip: View {
    /// The helper text to display in the popover.
    let text: LocalizedStringKey
    
    /// Optional learn more URL. If provided, a "Learn more" link will appear at the bottom of the popover.
    let learnMoreURL: String?
    
    /// The width of the popover.
    private let popoverWidth: CGFloat = 280
    
    /// The padding inside the popover.
    private let popoverPadding: CGFloat = 14
    
    /// State tracking whether the popover is currently presented.
    @State private var isShowingPopover: Bool = false
    
    init(_ text: LocalizedStringKey, learnMoreURL: String? = nil) {
        self.text = text
        self.learnMoreURL = learnMoreURL
    }
    
    var body: some View {
        Button(action: {
            isShowingPopover = true
        }) {
            Image(systemName: "info.circle.fill")
                .renderingMode(.template)
                .scaleEffect(0.8)
                .foregroundColor(Color(NSColor.labelColor))
                .font(.system(size: 14))
                .buttonStyle(.plain)
                .frame(width: 20, height: 20, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPopover) {
            VStack(alignment: .leading) {
                // Helper text
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(Color.accentColor) // Changed from NSColor.accentColor to Color.accentColor
                    .fixedSize(horizontal: false, vertical: true)
                
                // Learn more link if URL is provided
                if let learnMoreURL = learnMoreURL {
                    Divider()
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    
                    Link("Learn more", destination: URL(string: learnMoreURL)!)
                        .foregroundColor(Color.accentColor)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, popoverPadding)
            .padding(.vertical, popoverPadding / 2)
            .frame(width: popoverWidth)
            .background(Color(NSColor.windowBackgroundColor))
        }
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
                Toggle(isOn: $sessionVM.isSchedulerActive) {
                    HStack(spacing: 4) {
                        Text(sessionVM.isSchedulerActive ? "Disable Keybreeze" : "Enable Keybreeze")
                            .font(.body)
                        InfoTip("Enable or disable Keybreeze system-wide.")
                    }
                }
                
                // AX Permission status.
                // NOTE: We check status on appear only. The AX permission dialog
                // returns focus to the app after the user grants/denies, which
                // triggers .onAppear again so the status updates correctly.
                HStack {
                    Label(accessibilityGranted ? "Accessibility Access Granted" : "Accessibility Access Required",
                          systemImage: accessibilityGranted ? "hand.raised.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(accessibilityGranted ? Color(NSColor.secondaryLabelColor) : Color(NSColor.orange))
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
                    .font(.title2)
                    .fontWeight(.semibold)
            } footer: {
                Text("Keybreeze requires Accessibility access to read and insert text in other apps.")
                    .settingsDescription()
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
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        Spacer()
                        Text(appState.modelCatalogStatus.isEmpty ? "Loading..." : appState.modelCatalogStatus)
                            .font(.caption)
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
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
                    .font(.title2)
                    .fontWeight(.semibold)
            } footer: {
                Text("Choose the backend and model used for inline predictions.")
                    .settingsDescription()
            }
            
            // MARK: - Today's Stats
            Section {
                HStack {
                    Text("Keys Breezed Today")
                    Spacer()
                    Text("[\(sessionVM.dailyAcceptedCount)]")
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .font(.body.monospacedDigit())
                }
            } header: {
                Text("Statistics")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
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

// MARK: - Helper Extensions

extension Text {
    /// Returns text styled as settings description (12pt secondary).
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
    }
}