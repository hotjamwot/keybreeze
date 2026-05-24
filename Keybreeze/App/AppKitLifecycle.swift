import AppKit

/// Lightweight AppKit touchpoints for a SwiftUI menu bar app (activation policy, future bridges).
enum AppKitLifecycle {
    /// Reference to the BackendManager for clean process termination on app exit.
    /// Set during app launch from AppState.init().
    nonisolated(unsafe) static weak var backendManager: BackendManager?

    static func configureMenuBarAgentApp() {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Register for termination notifications to clean up backend processes.
        // Uses synchronous SIGKILL because willTerminateNotification must return
        // immediately — we cannot block the main thread or wait for async operations.
        //
        // BackendManager.terminateAllSync() kills processes we spawned (ollama
        // only if we spawned it, llama-server always), then pkill -9 as a safety net.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            backendManager?.terminateAllSync()
        }
    }

    /// Temporarily switch to `.regular` activation policy so the settings
    /// window appears in the Dock and Cmd+Tab switcher while visible.
    /// Call `.restoreToAccessory()` when the window closes.
    static func showInDockAndCmdTab() {
        if NSApplication.shared.activationPolicy() != .regular {
            NSApplication.shared.setActivationPolicy(.regular)
            // Bring the app to front so the window is immediately visible
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    /// Restore the `.accessory` activation policy (no Dock icon,
    /// no Cmd+Tab presence) after the settings window closes.
    static func restoreToAccessory() {
        if NSApplication.shared.activationPolicy() != .accessory {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
