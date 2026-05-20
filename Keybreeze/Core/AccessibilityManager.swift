import AppKit
import ApplicationServices
import OSLog

/// Text context extracted from the focused application.
struct TextContext {
    let prefix: String
    let suffix: String
    let cursorRect: CGRect
}

/// Strategy used for the last text insertion attempt.
enum InsertionStrategy: String {
    case ax
    case clipboard
}

/// Single shared manager for Accessibility API interactions.
/// Handles text context extraction, text insertion, and app identity queries.
///
/// # Internal Partition Discipline
/// - App gating helpers (bundle ID lists): lines ~30–100
/// - Text context retrieval (two-strategy): lines ~105–230
/// - Text insertion (AX + clipboard fallback): lines ~235–340
/// - AX tree walking / element finding: lines ~345–460
/// - Low-level AX helpers: lines ~465–560
final class AccessibilityManager {
    static let shared = AccessibilityManager()

    private let log = Logger(subsystem: "app.keybreeze", category: "ax-manager")

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

    // MARK: - Feature Flags

    /// Feature flag for two-strategy AX context reading (Win 3).
    /// Default: true (enabled). Users can toggle off via `defaults write app.keybreeze UseAXContextReader -bool NO`
    /// without a binary rollback if a regression is encountered.
    private var useAXContextReader: Bool {
        // Use object(forKey:) so we can distinguish "not set" from "explicitly false".
        // The default is true (enabled) for the AX reader.
        UserDefaults.standard.object(forKey: "UseAXContextReader") as? Bool ?? true
    }

    /// Feature flag for clipboard-fallback insertion (Win 4).
    /// Default: false (disabled) until the first round of field-testing completes.
    private var useClipboardFallback: Bool {
        UserDefaults.standard.object(forKey: "UseClipboardFallback") as? Bool ?? false
    }

    // MARK: - Text Context Retrieval (Two-Strategy)

    /// Reads text context from the currently focused text element.
    ///
    /// **Strategy 1 (AXValue + AXSelectedTextRange):** Works with native macOS text
    /// fields, TextEdit, Notes, Xcode source editors, etc. Returns the full text via
    /// `kAXValueAttribute` and the cursor via `kAXSelectedTextRangeAttribute`.
    ///
    /// **Strategy 2 (AXStringForRange):** Works with browser/web-hybrid apps (Chrome,
    /// Arc, Slack, Discord, Cursor, VS Code web views) where `kAXValueAttribute`
    /// returns empty but `AXStringForRange` on the same element returns the full text.
    ///
    /// Both strategies produce the same `TextContext`, so callers are agnostic.
    func getTextContext(maxChars: Int = 800) -> TextContext? {
        // Guard behind feature flag — if disabled, return nil so callers fall through
        // to their existing behaviour (e.g. ContextBuilder uses the mock draftText).
        guard useAXContextReader else {
            log.debug("AX context reader disabled via feature flag")
            return nil
        }

        guard let element = findBestTextElement() else {
            log.debug("No text element found")
            return nil
        }

        // Strategy 1: AXValue + AXSelectedTextRange (native text fields, TextEdit, etc.)
        if let context = getContextViaValue(element: element, maxChars: maxChars) {
            return context
        }

        // Strategy 2: AXStringForRange (browsers, web apps, etc.)
        if let context = getContextViaSelectedText(element: element, maxChars: maxChars) {
            return context
        }

        log.debug("Element found but no text attributes available (role: \(self.getRoleDescription(element)))")
        return nil
    }

    // MARK: - Text Insertion (AX + Clipboard Fallback)

    /// Inserts text into the currently focused text element.
    ///
    /// **Primary strategy:** AX value mutation via `AXUIElementSetAttributeValue`.
    /// **Fallback strategy (behind feature flag):** clipboard-based insertion with
    /// pasteboard restore after 0.5 s.
    ///
    /// Logs the strategy used and any failure reason for insertion observability.
    func insertText(_ text: String) {
        let frontmostID = focusedAppBundleID() ?? "unknown"

        // Try AX-based insertion first
        if let element = findBestTextElement() {
            if let range = getSelectedRange(element),
               let fullText = getStringAttribute(element, attribute: kAXValueAttribute) {
                let nsString = fullText as NSString
                let insertionPoint = min(range.location, nsString.length)
                let before = nsString.substring(to: insertionPoint)
                let after = nsString.substring(from: insertionPoint)
                let newText = before + text + after

                let setResult = AXUIElementSetAttributeValue(
                    element, kAXValueAttribute as CFString, newText as CFTypeRef)
                if setResult == .success {
                    let newCursorPos = insertionPoint + text.count
                    setSelectedRange(element, range: NSRange(location: newCursorPos, length: 0))
                    logInsertion(strategy: .ax, app: frontmostID, success: true)
                    return
                } else {
                    log.debug("AX insertion failed with error \(setResult.rawValue) — will try clipboard fallback")
                }
            } else {
                log.debug("AX element found but no value/range attributes — will try clipboard fallback")
            }
        } else {
            log.debug("No text element found for insertion — will try clipboard fallback")
        }

        // Clipboard fallback (behind feature flag)
        guard useClipboardFallback else {
            log.debug("Clipboard fallback disabled via feature flag — insertion aborted")
            logInsertion(strategy: .clipboard, app: frontmostID, success: false)
            return
        }

        insertViaClipboard(text)
        logInsertion(strategy: .clipboard, app: frontmostID, success: true)
    }

    /// Logs insertion strategy and result via os_log for insertion observability.
    private func logInsertion(strategy: InsertionStrategy, app: String, success: Bool) {
        log.debug("Insertion strategy: \(strategy.rawValue, privacy: .public), app: \(app, privacy: .public), success: \(success)")
    }

    // MARK: - Find Best Text Element

    /// Walk the AX tree to find the element that actually holds editable text.
    /// This handles complex hierarchies like Safari web content, Notes, etc.
    private func findBestTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        // Step 1: Get the focused application
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp else {
            log.debug("No focused application")
            return nil
        }

        // Step 2: Get the focused UI element
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            log.debug("No focused element in app")
            return nil
        }

        let axElement = element as! AXUIElement
        let role = getStringAttribute(axElement, attribute: kAXRoleAttribute) ?? "unknown"
        log.debug("Focused element role: \(role, privacy: .public)")

        // If the focused element already has text content, use it directly
        if hasTextContent(axElement) {
            return axElement
        }

        // For AXWebArea and AXGroup: try to find the focused child with text
        if let textChild = findTextElementInTree(axElement, depth: 0, maxDepth: 5) {
            return textChild
        }

        // Walk up to parent — focused element might be a button/label inside a text field
        if let parent = getParent(axElement), hasTextContent(parent) {
            return parent
        }

        // Return original element anyway — caller can try its own strategies
        return axElement
    }

    /// Recursively search the AX tree for an element with text content.
    /// Follows focused children first, then searches all children.
    private func findTextElementInTree(_ element: AXUIElement, depth: Int, maxDepth: Int) -> AXUIElement? {
        guard depth < maxDepth else { return nil }

        // Check if this element's focused child has text
        var focusedChild: AnyObject?
        if AXUIElementCopyAttributeValue(
            element, kAXFocusedUIElementAttribute as CFString, &focusedChild) == .success,
           let fc = focusedChild {
            let child = fc as! AXUIElement
            if hasTextContent(child) { return child }
            // Continue searching deeper through the focused child
            if let deeper = findTextElementInTree(child, depth: depth + 1, maxDepth: maxDepth) {
                return deeper
            }
        }

        // Search direct children for text-bearing roles
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else {
            return nil
        }

        // Limit to first 20 children to avoid excessive traversal
        let limit = min(childArray.count, 20)
        for i in 0..<limit {
            let child = childArray[i]
            let role = getStringAttribute(child, attribute: kAXRoleAttribute) ?? ""

            if role == kAXTextFieldRole as String ||
               role == kAXTextAreaRole as String ||
               role == kAXComboBoxRole as String {
                if hasTextContent(child) { return child }
            }

            // Recurse into web areas and groups
            if role == "AXWebArea" || role == kAXGroupRole as String {
                if let found = findTextElementInTree(child, depth: depth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }

        return nil
    }

    // MARK: - Context Extraction Helpers

    /// Strategy 1: Extract context using AXValue + AXSelectedTextRange.
    private func getContextViaValue(element: AXUIElement, maxChars: Int) -> TextContext? {
        guard let fullText = getStringAttribute(element, attribute: kAXValueAttribute),
              !fullText.isEmpty else {
            return nil
        }

        let selectedRange = getSelectedRange(element)
        let cursorPosition = selectedRange?.location ?? fullText.count

        guard cursorPosition <= fullText.count else { return nil }

        let prefixStart = max(0, cursorPosition - maxChars)
        let suffixEnd = min(fullText.count, cursorPosition + maxChars)

        let startIdx = fullText.index(fullText.startIndex, offsetBy: prefixStart)
        let cursorIdx = fullText.index(fullText.startIndex, offsetBy: cursorPosition)
        let endIdx = fullText.index(fullText.startIndex, offsetBy: suffixEnd)

        let prefix = String(fullText[startIdx..<cursorIdx])
        let suffix = String(fullText[cursorIdx..<endIdx])

        guard !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let cursorRect = getCursorRect(element, caretOffset: cursorPosition)
        return TextContext(prefix: prefix, suffix: suffix, cursorRect: cursorRect)
    }

    /// Strategy 2: Extract context using AXStringForRange (browser/web fallback).
    private func getContextViaSelectedText(element: AXUIElement, maxChars: Int) -> TextContext? {
        guard let selectedRange = getSelectedRange(element) else { return nil }

        let cursorPosition = selectedRange.location

        let prefixRange = NSRange(location: max(0, cursorPosition - maxChars),
                                  length: min(cursorPosition, maxChars))
        let prefix = getStringForRange(element, range: prefixRange) ?? ""

        let suffixStart = cursorPosition + selectedRange.length
        let suffixRange = NSRange(location: suffixStart, length: maxChars)
        let suffix = getStringForRange(element, range: suffixRange) ?? ""

        guard !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let cursorRect = getCursorRect(element, caretOffset: cursorPosition)
        return TextContext(prefix: prefix, suffix: suffix, cursorRect: cursorRect)
    }

    // MARK: - Clipboard Fallback Insertion

    /// Clipboard-based text insertion with pasteboard restore after 0.5 s.
    /// Saves the current pasteboard, writes the new text, simulates Cmd+V,
    /// then restores the original contents after a short delay.
    private func insertViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Restore clipboard after a short delay
        if let old = oldContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    // MARK: - Check Element for Text Content

    /// Check if an element has text content we can read.
    private func hasTextContent(_ element: AXUIElement) -> Bool {
        // Has AXValue (full text)?
        if let val = getStringAttribute(element, attribute: kAXValueAttribute), !val.isEmpty {
            return true
        }
        // Has AXSelectedTextRange (cursor position)?
        if getSelectedRange(element) != nil {
            return true
        }
        return false
    }

    // MARK: - Low-Level AX Helpers

    private func getStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func getSelectedRange(_ element: AXUIElement) -> NSRange? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }

        var range = CFRange(location: 0, length: 0)
        if AXValueGetValue(axValue as! AXValue, .cfRange, &range) {
            return NSRange(location: range.location, length: range.length)
        }
        return nil
    }

    private func setSelectedRange(_ element: AXUIElement, range: NSRange) {
        var cfRange = CFRange(location: range.location, length: range.length)
        if let value = AXValueCreate(.cfRange, &cfRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        }
    }

    private func getStringForRange(_ element: AXUIElement, range: NSRange) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var result: AnyObject?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &result
        )
        guard err == .success else { return nil }
        return result as? String
    }

    private func getCursorRect(_ element: AXUIElement, caretOffset: Int) -> CGRect {
        var cfRange = CFRange(location: caretOffset, length: 0)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return getElementPosition(element)
        }

        var bounds: AnyObject?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &bounds
        )

        if result == .success, let boundsValue = bounds {
            var rect = CGRect.zero
            if AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.height > 0 {
                return rect
            }
        }

        return getElementPosition(element)
    }

    private func getElementPosition(_ element: AXUIElement) -> CGRect {
        var position: AnyObject?
        var size: AnyObject?

        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)

        var point = CGPoint.zero
        var axSize = CGSize.zero

        if let posValue = position {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        }
        if let sizeValue = size {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &axSize)
        }

        return CGRect(x: point.x, y: point.y, width: axSize.width, height: axSize.height)
    }

    private func getParent(_ element: AXUIElement) -> AXUIElement? {
        var parent: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent)
        guard result == .success, let p = parent else { return nil }
        return (p as! AXUIElement)
    }

    private func getRoleDescription(_ element: AXUIElement) -> String {
        let role = getStringAttribute(element, attribute: kAXRoleAttribute) ?? "?"
        let subrole = getStringAttribute(element, attribute: kAXSubroleAttribute) ?? ""
        return subrole.isEmpty ? role : "\(role)/\(subrole)"
    }
}