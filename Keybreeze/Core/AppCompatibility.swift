import Foundation

/// How the ghost text overlay is positioned relative to the caret.
/// Matches KeyType's `OverlayPreference` — used for per-app tuning.
enum OverlayPreference {
    /// Standard inline ghost text on the same baseline as the caret.
    case inline
    /// Text mirror: overlay appears below the caret (for mid-line completions
    /// where inline would overlap existing text).
    case textMirror
    /// No overlay shown (e.g., password managers).
    case hidden
}

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

    /// Custom prompt instructions for this app (fed into the prompt as a section).
    let customPromptSuffix: String

    /// Per-app overlay preference (inline, textMirror, or hidden).
    let overlayPreference: OverlayPreference

    /// Font size adjustment factor for the overlay (1.0 = no adjustment).
    /// Some apps report slightly different font metrics; this corrects for that.
    let fontSizeAdjustmentFactor: Double

    /// Vertical offset (in points) applied to the overlay position.
    /// Positive values shift the overlay downward. Useful for apps where
    /// the caret rect is slightly misaligned.
    let verticalAlignmentOffset: Double

    /// Static factory for a default entry with sensible defaults.
    static func entry(
        _ bundleIdentifier: String,
        predictionEnabled: Bool = true,
        environmentContextDisabled: Bool = false,
        usePasteboardInsertion: Bool = false,
        customPromptSuffix: String = "",
        overlayPreference: OverlayPreference = .inline,
        fontSizeAdjustmentFactor: Double = 1.0,
        verticalAlignmentOffset: Double = 0
    ) -> TargetOverride {
        TargetOverride(
            bundleIdentifier: bundleIdentifier,
            predictionEnabled: predictionEnabled,
            environmentContextDisabled: environmentContextDisabled,
            usePasteboardInsertion: usePasteboardInsertion,
            customPromptSuffix: customPromptSuffix,
            overlayPreference: overlayPreference,
            fontSizeAdjustmentFactor: fontSizeAdjustmentFactor,
            verticalAlignmentOffset: verticalAlignmentOffset
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

    /// Get the overlay preference for this app.
    static func overlayPreference(for bundleIdentifier: String?) -> OverlayPreference {
        guard let bundleIdentifier else { return .inline }
        return override(for: bundleIdentifier)?.overlayPreference ?? .inline
    }

    /// Get the font size adjustment factor for this app (1.0 = no adjustment).
    static func fontSizeAdjustmentFactor(for bundleIdentifier: String?) -> Double {
        guard let bundleIdentifier else { return 1.0 }
        return override(for: bundleIdentifier)?.fontSizeAdjustmentFactor ?? 1.0
    }

    /// Get the vertical alignment offset for this app (in points).
    static func verticalAlignmentOffset(for bundleIdentifier: String?) -> Double {
        guard let bundleIdentifier else { return 0 }
        return override(for: bundleIdentifier)?.verticalAlignmentOffset ?? 0
    }

    /// Get all bundle identifiers that are suppressed.
    /// Useful for populating the `excludedBundleIDs` list for backward compatibility.
    static var allSuppressedBundleIDs: Set<String> {
        Set(overrides.values.filter { !$0.predictionEnabled }.map(\.bundleIdentifier))
    }
}
