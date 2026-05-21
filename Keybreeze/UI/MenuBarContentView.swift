import SwiftUI

/// Menu bar dropdown content — provides quick access to controls
/// and an "Open Typing Lab" action that opens the full typing lab window.
struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Keybreeze")
                    .font(.headline)
                Spacer()
                if sessionVM.isPredicting {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }
                if sessionVM.isSchedulerActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Open Typing Lab
            Button {
                openTypingLab()
            } label: {
                Label("Open Typing Lab…", systemImage: "laptopcomputer.trianglebadge.exclamationmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Backend selector
            VStack(alignment: .leading, spacing: 4) {
                Text("Backend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                Picker("Backend", selection: $appState.selectedBackend) {
                    ForEach(LLMBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

                // Model selector
                Text("Model")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                if appState.availableModels.isEmpty {
                    Text(appState.modelCatalogStatus.isEmpty ? "Loading..." : appState.modelCatalogStatus)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                } else {
                    Picker("Model", selection: $appState.selectedModel) {
                        ForEach(appState.availableModels) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 6)

            // Status message
            if !appState.modelCatalogStatus.isEmpty {
                Text(appState.modelCatalogStatus)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Divider()

            // Active toggle
            HStack {
                Text("Active")
                    .font(.body)
                Spacer()
                Toggle("Active", isOn: $sessionVM.isSchedulerActive)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!appState.canRunPrediction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Status
            HStack(spacing: 6) {
                if sessionVM.isPredicting {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
                Text(sessionVM.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider()

            // Quit
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

    private func openTypingLab() {
        // Store references to shared state before opening window
        TypingLabWindowController.sharedAppState = appState
        TypingLabWindowController.sharedSessionVM = sessionVM
        TypingLabWindowController.openWindow()
    }
}

// MARK: - Typing Lab Window Controller

/// Manages opening the Typing Lab in a separate, standalone window.
final class TypingLabWindowController: NSObject, NSWindowDelegate {
    private static let shared = TypingLabWindowController()
    private var window: NSWindow?

    /// Shared state from the menu bar — set before calling `openWindow()`.
    static var sharedAppState: AppState?
    static var sharedSessionVM: SessionViewModel?

    static func openWindow() {
        shared.open()
    }

    private func open() {
        // If window already exists and is visible, bring it to front
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        guard let appState = Self.sharedAppState,
              let sessionVM = Self.sharedSessionVM else {
            return
        }

        let width: CGFloat = 720
        let height: CGFloat = 640

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - height) / 2

        let hostingView = NSHostingView(
            rootView: TypingLabRootView()
                .environmentObject(appState)
                .environmentObject(sessionVM)
        )

        let newWindow = NSWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Keybreeze — Typing Lab"
        newWindow.contentView = hostingView
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
