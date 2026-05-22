import AppKit

/// Lightweight AppKit touchpoints for a SwiftUI menu bar app (activation policy, future bridges).
enum AppKitLifecycle {
    static func configureMenuBarAgentApp() {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Register for termination notifications to clean up llama-server.
        // We fire-and-forget pkill here because NSApplication.willTerminateNotification
        // must return immediately — we cannot block the main thread while waiting
        // for llama-server to die. The LlamaCppProcessManager already does a
        // controlled SIGTERM→SIGKILL shutdown before this fires; this is a final
        // safety net for edge cases where the manager's handle was lost.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task.detached(priority: .background) {
                // pkill by the exact binary name matches both a direct spawn
                // and any wrapper shell that launched it.
                try? await Process.run(
                    URL(fileURLWithPath: "/usr/bin/pkill"),
                    arguments: ["-9", "-f", "llama-server"]
                )
            }
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