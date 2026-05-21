import Foundation
import AppKit
import ApplicationServices
import OSLog

/// Self-contained Accessibility API manager with clipboard fallback.
/// Handles text context extraction and insertion for any focused app.
/// Includes AutoComp-inspired robustification: nested element resolution,
/// secure field detection, attributed string handling, and weak-text filtering.
@MainActor
final class AccessibilityManager {
    static let shared = AccessibilityManager()
    private let log = Logger(subsystem: "app.keybreeze", category: "ax")

    private init() {}

    // MARK: - Permissions

    func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Text Context Extraction

    /// Extracts text context using AX API with fallbacks.
    func getTextContext(maxChars: Int = 800) -> TextContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier

        let pidRef = AXUIElementCreateApplication(pid)
        guard let rawFocused = getFocusedElement(from: pidRef) else { return nil }

        // Resolve nested focused elements (AutoComp pattern)
        let focused = resolvedFocusedElement(from: rawFocused)

        // Reject secure fields immediately
        guard !isSecureField(focused) else {
            log.warning("Skipping secure field")
            return nil
        }

        // Strategy: AXValue + AXSelectedTextRange
        if let (before, after) = getContextViaValue(focused) {
            // Filter out weak/invisible text (zero-width chars, etc.)
            let filtered = filterWeakText(before)
            guard !filtered.isEmpty else { return nil }
            return TextContext(
                prefix: String(filtered.suffix(maxChars)),
                suffix: after
            )
        }

        return nil
    }

    private func getFocusedElement(from pidRef: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(pidRef, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let element = value else { return nil }
        return (element as! AXUIElement)
    }

    /// Resolves nested focused elements up to 6 levels deep (AutoComp pattern).
    /// Some apps (e.g. web views, complex editors) nest AX focused elements.
    private func resolvedFocusedElement(from element: AXUIElement) -> AXUIElement {
        var current = element
        for _ in 0..<6 {
            var nestedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXFocusedUIElementAttribute as CFString, &nestedRef) == .success,
                  let nestedRef else {
                return current
            }
            let nested = nestedRef as! AXUIElement
            if Unmanaged.passUnretained(current).toOpaque() == Unmanaged.passUnretained(nested).toOpaque() {
                return current
            }
            current = nested
        }
        return current
    }

    /// Check if the element is a secure text field (password fields).
    private func isSecureField(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let subrole = stringAttribute(kAXSubroleAttribute, from: element) ?? ""
        return role.localizedCaseInsensitiveContains("Secure")
            || subrole.localizedCaseInsensitiveContains("Secure")
    }

    private func getContextViaValue(_ element: AXUIElement) -> (String, String)? {
        // Try parameterized stringForRange first (more reliable in many editors)
        if let range = selectedRange(from: element),
           let rangedPrefix = stringForRange(from: element, range: .init(location: 0, length: range.location)) {
            let suffix = stringForRange(
                from: element,
                range: .init(location: range.location + range.length, length: max(0, 200))
            ) ?? ""
            return (rangedPrefix, suffix)
        }

        // Fallback: AXValue + AXSelectedTextRange
        var value: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success else { return nil }

        // Handle both String and NSAttributedString
        let text: String
        if let s = value as? String {
            text = s
        } else if let attributed = value as? NSAttributedString {
            text = attributed.string
        } else {
            return nil
        }

        var rangeValue: CFTypeRef?
        result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard result == .success, let rangeRef = rangeValue else { return (text, "") }

        // Convert AXValue to NSRange
        var nsRange = NSRange(location: 0, length: 0)
        let axResult = AXValueGetValue(rangeRef as! AXValue, .cfRange, &nsRange)
        guard axResult else { return (text, "") }

        let before = String(text.dropLast(text.count - nsRange.location))
        let after = String(text.dropFirst(nsRange.location + nsRange.length))

        return (before, after)
    }

    /// Read text for a specific range using parameterized attribute (more reliable).
    private func stringForRange(from element: AXUIElement, range: CFRange) -> String? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        var cfRange = range
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &value
        )
        guard status == .success, let value else { return nil }

        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    /// Get the selected text range from an element.
    private func selectedRange(from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard status == .success, let axValue = value else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    /// Filter out weak/invisible text (zero-width characters, etc.)
    private func filterWeakText(_ text: String) -> String {
        text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && ![0x200B, 0x200C, 0x200D, 0xFEFF, 0xFFFC].contains(scalar.value)
        }.isEmpty ? "" : text
    }

    /// Extract a common string attribute from an AX element.
    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success, let value else { return nil }

        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    // MARK: - Text Insertion

    func insertText(_ text: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier

        let pidRef = AXUIElementCreateApplication(pid)
        guard let focused = getFocusedElement(from: pidRef) else { return }

        // Try AX insertion first
        let inserted = performAXInsertion(text, on: focused)
        if inserted { return }

        // Fallback to clipboard
        insertViaClipboard(text)
    }

    private func performAXInsertion(_ text: String, on element: AXUIElement) -> Bool {
        // Get current selected range
        var rangeValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard result == .success, let rangeRef = rangeValue else { return false }

        var nsRange = NSRange(location: 0, length: 0)
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &nsRange) else { return false }

        // Get current value
        var currentValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)
        guard valueResult == .success, let currentText = currentValue as? String else { return false }

        // Replace the selected range with the new text
        let prefix = String(currentText.prefix(nsRange.location))
        let suffix = String(currentText.dropFirst(nsRange.location + nsRange.length))
        let newText = prefix + text + suffix

        // Set the new text value
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newText as CFString)
        guard setResult == .success else { return false }

        // Move cursor to end of inserted text
        let newCursorPos = NSRange(location: nsRange.location + text.count, length: 0)
        var axNewRange = newCursorPos
        if let axValue = AXValueCreate(.cfRange, &axNewRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue)
        }

        return true
    }

    /// Clipboard-based insertion with pasteboard restore (GhostType pattern).
    private func insertViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = [.maskCommand]
        keyUp?.flags = [.maskCommand]
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Restore pasteboard
        pasteboard.clearContents()
        if let saved = saved {
            pasteboard.writeObjects(saved)
        }
    }

    // MARK: - App Info

    func focusedAppBundleID() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return app.bundleIdentifier
    }

    // MARK: - Default Excluded Bundle IDs (GhostType pattern)
    nonisolated static var defaultExcludedBundleIDs: [String] {
        [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "org.vim.MacVim",
            "org.emacsformacosx.Emacs",
            "com.sublimetext.4",
            "com.barebones.bbedit",
            "com.apple.ActivityMonitor",
            "com.apple.Console"
        ]
    }

    nonisolated static var defaultManualOnlyBundleIDs: [String] {
        [
            "com.apple.mail",
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.apple.TextEdit",
            "com.apple.notes",
            "com.apple.pages",
            "com.apple.numbers",
            "com.apple.keynote"
        ]
    }
}

// MARK: - Public Interface

/// Text context extracted from the focused application.
struct TextContext {
    let prefix: String
    let suffix: String
}