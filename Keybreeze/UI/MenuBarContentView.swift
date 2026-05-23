import SwiftUI

/// Menu bar dropdown content — provides quick access to controls
/// and a "Settings…" action that opens the full settings window.
struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Daily completions statistic
            Text("\(sessionVM.dailyAcceptedCount) keys breezed today")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // 2. Active toggle button
            Button(action: {
                sessionVM.isSchedulerActive.toggle()
            }) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(sessionVM.isSchedulerActive ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(sessionVM.isSchedulerActive ? "Active" : "Enable Keybreeze")
                        .font(.caption2)
                        .foregroundStyle(sessionVM.isSchedulerActive ? .green : .orange)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 3. Focused app info (removed - always system-wide when active)
            // 4. Settings
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

            // 9. Suggestion preview (when active and a suggestion exists)
            if sessionVM.isSchedulerActive && !sessionVM.suggestion.isEmpty {
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
        // If window already exists, check if it's still valid (in NSApp.windows) and visible.
        if let existingWindow = window {
            if NSApplication.shared.windows.contains(existingWindow) {
                if existingWindow.isVisible {
                    existingWindow.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    return
                }
            } else {
                // Window is no longer in the application's window list, so it's gone.
                window = nil
            }
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
        // 1. Clear the delegate before anything else to stop receiving events
        window?.delegate = nil
        
        // 2. Release the window reference
        window = nil

        // 3. Defer the activation policy change to the next run loop
        //    iteration. setActivationPolicy(.accessory) triggers NSApp
        //    lifecycle notifications which can cause re-entrancy crashes
        //    if called while SwiftUI views are mid-teardown.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppKitLifecycle.restoreToAccessory()
        }
    }
    
    // We keep windowDidClose empty or remove it if we use windowWillClose
    func windowDidClose(_ notification: Notification) {
    }
}
