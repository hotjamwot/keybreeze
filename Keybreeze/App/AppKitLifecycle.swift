import AppKit

/// Lightweight AppKit touchpoints for a SwiftUI menu bar app (activation policy, future bridges).
enum AppKitLifecycle {
    static func configureMenuBarAgentApp() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
