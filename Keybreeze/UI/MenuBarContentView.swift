import SwiftUI

/// Menu bar dropdown content — provides quick access to controls
/// and a "Settings…" action that opens the full settings window.
struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Daily completions statistic
            Text("[\(sessionVM.dailyAcceptedCount)] keys breezed today")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // 2. Settings (opens full settings window with General + Typing Lab)
            Button {
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 3. Backend selector (menu-style picker)
            Picker("Backend", selection: $appState.selectedBackend) {
                ForEach(LLMBackend.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 4. Model selector
            Text("Model")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 2)

            if appState.availableModels.isEmpty {
                Text(appState.modelCatalogStatus.isEmpty ? "Loading..." : appState.modelCatalogStatus)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            } else {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(appState.availableModels) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            // 5. Service status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isOllamaRunning ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(appState.isOllamaRunning ? "Active" : "Inactive")
                    .foregroundStyle(appState.isOllamaRunning ? .green : .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()
                .padding(.vertical, 2)

            // 6. Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Keybreeze", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .task {
            appState.refreshModels()
        }
    }

    private func openSettings() {
        SettingsWindowController.openWindow(
            appState: appState,
            sessionVM: sessionVM
        )
    }
}

// MARK: - Settings Window Controller

/// Manages opening the Settings window in a separate, standalone window.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let shared = SettingsWindowController()
    private var window: NSWindow?

    /// Shared reference to the session VM — set before opening the window,
    /// used during teardown to cancel in-flight predictions.
    static var sharedSessionVM: SessionViewModel?

    static func openWindow(appState: AppState, sessionVM: SessionViewModel) {
        sharedSessionVM = sessionVM
        shared.open(appState: appState, sessionVM: sessionVM)
    }

    private func open(appState: AppState, sessionVM: SessionViewModel) {
        // If window already exists and is visible, bring it to front
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let width: CGFloat = 700
        let height: CGFloat = 520

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - height) / 2

        let hostingView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(appState)
                .environmentObject(sessionVM)
        )

        let newWindow = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Keybreeze Settings"
        newWindow.contentView = hostingView
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Cancel any in-flight prediction so stale @MainActor callbacks
        // don't clash with SwiftUI's view teardown cycle.
        Self.sharedSessionVM?.cancelCurrentPrediction()
    }
}