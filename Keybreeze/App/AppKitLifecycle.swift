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
}
