import AppKit

/// Lightweight AppKit touchpoints for a SwiftUI menu bar app (activation policy, future bridges).
enum AppKitLifecycle {
    static func configureMenuBarAgentApp() {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Register for termination notifications to clean up llama-server
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Kill any remaining llama-server process
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-f", "llama-server"]
            try? task.run()
            task.waitUntilExit()
        }
    }
}