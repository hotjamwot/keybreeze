import Foundation

/// Per-app compatibility configuration.
///
/// Data-driven override table that replaces hardcoded bundle ID lists.
/// Each entry specifies how Keybreeze should behave in a specific app.
/// This is the Keybreeze equivalent of KeyType's `TargetOverride` struct.
///
/// Design principles (from D18 — KeyType as reference):
/// - Simple: a flat struct, not a protocol hierarchy
/// - Extensible: new fields added here propagate everywhere
/// - Data-driven: overrides are defined in a table, not scattered across code
struct TargetOverride {
    /// Bundle identifier of the target app.
    let bundleIdentifier: String

    /// Whether predictions should fire at all.
    /// `false` = suppress entirely (e.g., terminals, password managers).
    let predictionEnabled: Bool

    /// Whether to disable environment context (e.g., app name, window title)
    /// from the prompt. Code editors produce noisy environment context that
    /// biases prose predictions toward code.
    let environmentContextDisabled: Bool

    /// Whether to use pasteboard-based insertion instead of keyboard synthesis.
    /// Some apps (e.g., Google Docs, WeChat) don't handle synthetic keystrokes.
    let usePasteboardInsertion: Bool

    /// Custom prompt suffix to append for this app.
    /// Use to bias the model toward the app's domain (e.g., "Write in formal email style" for Gmail).
    let customPromptSuffix: String

    /// Static factory for a default entry with sensible defaults.
    static func entry(
        _ bundleIdentifier: String,
        predictionEnabled: Bool = true,
        environmentContextDisabled: Bool = false,
        usePasteboardInsertion: Bool = false,
        customPromptSuffix: String = ""
    ) -> TargetOverride {
        TargetOverride(
            bundleIdentifier: bundleIdentifier,
            predictionEnabled: predictionEnabled,
            environmentContextDisabled: environmentContextDisabled,
            usePasteboardInsertion: usePasteboardInsertion,
            customPromptSuffix: customPromptSuffix
        )
    }
}

/// Central registry of per-app compatibility overrides.
///
/// Lookup is O(1) via dictionary. The seed table covers the most common
/// apps where Keybreeze's default behavior would cause issues.
enum AppCompatibility {
    /// The master override table — keyed by bundle identifier.
    /// This replaces the hardcoded `TerminalAppDetector.terminalBundleIdentifiers`
    /// and `excludedBundleIDs` / `manualOnlyBundleIDs` lists.
    private static let overrides: [String: TargetOverride] = {
        var table: [String: TargetOverride] = [:]

        // MARK: - Terminals (suppress entirely)
        // Predictions are useless and disruptive in terminal apps.
        let terminals = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.github.wez.wezterm",
            "io.alacritty",
            "net.kovidgoyal.kitty",
            "dev.warp.Warp-Stable",
        ]
        for id in terminals {
            table[id] = .entry(id, predictionEnabled: false)
        }

        // MARK: - Code editors (suppress — code completion is handled by IDE)
        // Note: VSCode is NOT suppressed — user wants prose predictions there
        let codeEditors = [
            "com.jetbrains.intellij",
            "com.jetbrains.AppCode",
            "com.jetbrains.CLion",
            "com.jetbrains.PhpStorm",
            "com.jetbrains.PyCharm",
            "com.jetbrains.RubyMine",
            "com.jetbrains.WebStorm",
            "com.jetbrains.GoLand",
            "com.jetbrains.Rider",
            "org.vim.MacVim",
            "org.emacsformacosx.Emacs",
            "com.sublimetext.4",
            "com.barebones.bbedit",
        ]
        for id in codeEditors {
            table[id] = .entry(id, predictionEnabled: false)
        }

        // MARK: - Password managers (suppress — security-critical)
        let passwordManagers = [
            "com.agilebits.onepassword7",
            "com.agilebits.onepassword",
            "com.lastpass.LastPass",
            "com.1password.1password",
            "ru.keepassxc",
            "com.kitware.Shutterbug",  // KeePassXC variant
        ]
        for id in passwordManagers {
            table[id] = .entry(id, predictionEnabled: false)
        }

        // MARK: - System utilities (suppress)
        let systemUtilities = [
            "com.apple.ActivityMonitor",
            "com.apple.Console",
            "com.apple.SystemPreferences",
            "com.apple.SystemSettings",
            "com.apple.finder",
        ]
        for id in systemUtilities {
            table[id] = .entry(id, predictionEnabled: false)
        }

        // MARK: - Web surfaces (pasteboard insertion + disable env context)
        // Google Docs, Notion, etc. don't handle synthetic keystrokes well.
        let webSurfaces = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "org.mozilla.firefox",
            "com.brave.Browser",
            "com.operasoftware.Opera",
        ]
        for id in webSurfaces {
            table[id] = .entry(
                id,
                environmentContextDisabled: true,
                usePasteboardInsertion: true
            )
        }

        // MARK: - Messaging apps (pasteboard insertion)
        let messaging = [
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "ru.keepassxc",
            "com.apple.MobileSMS",
            "com.apple.iChat",
            "com.tencent.xinWeChat",
        ]
        for id in messaging {
            table[id] = .entry(id, usePasteboardInsertion: true)
        }

        return table
    }()

    // MARK: - Public API

    /// Look up the override for a given bundle identifier.
    /// Returns `nil` if no override exists (use Keybreeze defaults).
    static func override(for bundleIdentifier: String) -> TargetOverride? {
        overrides[bundleIdentifier]
    }

    /// Check if a bundle identifier should be suppressed entirely.
    /// This is the primary gating check — replaces `TerminalAppDetector.isTerminal()`
    /// and the `excludedBundleIDs` list.
    static func isSuppressed(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return override(for: bundleIdentifier)?.predictionEnabled == false
    }

    /// Check if environment context should be disabled for this app.
    /// When true, the prompt should omit app name, window title, etc.
    static func isEnvironmentContextDisabled(for bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return override(for: bundleIdentifier)?.environmentContextDisabled == true
    }

    /// Get the custom prompt suffix for this app, if any.
    static func customPromptSuffix(for bundleIdentifier: String?) -> String {
        guard let bundleIdentifier else { return "" }
        return override(for: bundleIdentifier)?.customPromptSuffix ?? ""
    }

    /// Get all bundle identifiers that are suppressed.
    /// Useful for populating the `excludedBundleIDs` list for backward compatibility.
    static var allSuppressedBundleIDs: Set<String> {
        Set(overrides.values.filter { !$0.predictionEnabled }.map(\.bundleIdentifier))
    }
}