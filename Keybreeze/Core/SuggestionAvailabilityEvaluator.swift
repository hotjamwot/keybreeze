import Foundation

/// Centralizes the gating rules that decide whether Keybreeze can react to the current focus
/// and whether a refreshed prediction is worthwhile.
///
/// Ported from Cotabby's SuggestionAvailabilityEvaluator with regex-based app gating support.
enum SuggestionAvailabilityEvaluator {
    static func disabledReason(
        globallyEnabled: Bool = true,
        disabledAppBundleIdentifiers: Set<String> = [],
        disabledAppURLSchemes: [String] = [],
        inputMonitoringGranted: Bool,
        screenRecordingGranted: Bool = true,
        bundleIdentifier: String?,
        applicationName: String = "Unknown"
    ) -> String? {
        guard globallyEnabled else {
            return "Keybreeze is turned off."
        }

        if let bundleIdentifier,
           disabledAppBundleIdentifiers.contains(bundleIdentifier) {
            return "Keybreeze is disabled in \(applicationName)."
        }

        if let bundleIdentifier,
           TerminalAppDetector.isTerminal(bundleIdentifier: bundleIdentifier) {
            return "Keybreeze is not available in terminal apps."
        }

        guard inputMonitoringGranted else {
            return "Input Monitoring permission is required."
        }

        return nil
    }

    static func shouldSchedulePrediction(
        globallyEnabled: Bool = true,
        disabledAppBundleIdentifiers: Set<String> = [],
        disabledAppURLSchemes: [String] = [],
        inputMonitoringGranted: Bool,
        screenRecordingGranted: Bool = true,
        bundleIdentifier: String?,
        applicationName: String = "Unknown"
    ) -> Bool {
        disabledReason(
            globallyEnabled: globallyEnabled,
            disabledAppBundleIdentifiers: disabledAppBundleIdentifiers,
            disabledAppURLSchemes: disabledAppURLSchemes,
            inputMonitoringGranted: inputMonitoringGranted,
            screenRecordingGranted: screenRecordingGranted,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName
        ) == nil
    }
}

/// Simple terminal app detection.
enum TerminalAppDetector {
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "org.vim.MacVim",
        "org.emacsformacosx.Emacs",
        "com.sublimetext.4",
        "com.barebones.bbedit",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.jetbrains.intellij",
        "com.jetbrains.AppCode",
        "com.jetbrains.CLion",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.PyCharm",
        "com.jetbrains.RubyMine",
        "com.jetbrains.WebStorm",
        "com.tinyspeck.slackmacgap"
    ]

    static func isTerminal(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return terminalBundleIdentifiers.contains(bundleIdentifier)
    }
}