import AppKit
import ApplicationServices

/// Text context extracted from the focused application.
struct TextContext {
    let prefix: String
    let suffix: String
    let cursorRect: CGRect
}

/// Single shared manager for Accessibility API interactions.
/// Handles text context extraction, text insertion, and app identity queries.
final class AccessibilityManager {
    static let shared = AccessibilityManager()

    private init() {}

    // MARK: - Permission Check

    /// Check if Accessibility permission is granted.
    func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Show the system prompt to request Accessibility permission.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Frontmost App

    /// Bundle identifier of the application that currently owns keyboard focus.
    /// Uses NSWorkspace (non-AX) for reliability even when AX permissions aren't granted.
    func focusedAppBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    // MARK: - App Gating Helpers

    /// Default excluded bundle IDs: IDEs and terminals where autocomplete is invasive.
    static let defaultExcludedBundleIDs: [String] = [
        // Terminals
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        // IDEs
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "org.vim.MacVim",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.WebStorm",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.CLion",
        "com.jetbrains.goland",
        "com.jetbrains.rider",
        "com.jetbrains.rubymine",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.AppCode",
        "com.jetbrains.fleet",
        "dev.zed.Zed",
        "com.apple.dt.Xcode",
        "com.panic.Nova",
        "abnerworks.Typora",
        // Cursor / AI coding assistants
        "cursor",
    ]

    /// Default manual-only bundle IDs: apps where auto-trigger may interfere.
    static let defaultManualOnlyBundleIDs: [String] = [
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "ru.keepcoder.Telegram",
        "com.facebook.archon.developerID",
    ]
}