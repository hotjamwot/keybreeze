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

            // 2. Active toggle + mode indicator
            HStack(spacing: 8) {
                Toggle("Active", isOn: $sessionVM.isSchedulerActive)
                    .toggleStyle(.switch)
                    .labelsHidden()

                if sessionVM.isSchedulerActive {
                    if sessionVM.systemWideMode {
                        Text("System")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("Playground")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 3. System-wide mode toggle (only when active)
            if sessionVM.isSchedulerActive {
                Toggle(isOn: $sessionVM.systemWideMode) {
                    Label("Predict in all apps", systemImage: "app.connected.to.app.below.fill")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            // 4. Focused app info (when system-wide is active)
            if sessionVM.isSchedulerActive && sessionVM.systemWideMode,
               let appName = sessionVM.focusedAppName {
                HStack(spacing: 4) {
                    Circle()
                        .fill(sessionVM.isSystemWidePaused ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(sessionVM.isSystemWidePaused ? sessionVM.systemWidePauseReason : appName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            // 5. Settings
            Button {
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()
                .padding(.vertical, 2)

            // 6. Backend selector
            Picker("Backend", selection: $appState.selectedBackend) {
                ForEach(LLMBackend.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 7. Model selector
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

            // 8. Service status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.isOllamaRunning ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(appState.isOllamaRunning ? "Active" : "Inactive")
                    .foregroundStyle(appState.isOllamaRunning ? .green : .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 9. Suggestion preview (when system-wide and a suggestion exists)
            if sessionVM.isSchedulerActive && sessionVM.systemWideMode && !sessionVM.suggestion.isEmpty {
                HStack(spacing: 4) {
                    Text("→")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(sessionVM.suggestion)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Divider()
                .padding(.vertical, 2)

            // 10. Quit
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

    static func openWindow(appState: AppState, sessionVM: SessionViewModel) {
        // Switch to regular activation policy so the settings window
        // appears in the Dock and Cmd+Tab switcher while open.
        AppKitLifecycle.showInDockAndCmdTab()
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
        // The SessionViewModel is an app-level singleton shared with the
        // menu bar and other UI surfaces. Closing the settings window is
        // purely a UI action — it must NOT cancel predictions or touch
        // the session VM state. Predictions continue running in other apps.

        // 1. Release the window reference first, allowing the NSHostingView
        //    and its SwiftUI view hierarchy to deallocate synchronously.
        window = nil

        // 2. Defer the activation policy change to the next run loop
        //    iteration. setActivationPolicy(.accessory) triggers NSApp
        //    lifecycle notifications which can cause re-entrancy crashes
        //    if called while SwiftUI views are mid-teardown.
        DispatchQueue.main.async {
            AppKitLifecycle.restoreToAccessory()
        }
    }
}
