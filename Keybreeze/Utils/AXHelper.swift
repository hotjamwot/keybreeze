import AppKit
import ApplicationServices
import Foundation

/// Wraps macOS Accessibility APIs behind Swift-friendly helpers for typed values, tree traversal,
/// element identity, and coordinate normalization.
///
/// Ported from Cotabby to improve geometry resolution for overlay positioning.
enum AXHelper {
    private static let knownEditableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXSearchField",
        kAXComboBoxRole as String
    ]

    private static let knownReadOnlyRoles: Set<String> = [
        kAXStaticTextRole as String,
        kAXImageRole as String,
        kAXButtonRole as String,
        "AXLink",
        kAXMenuItemRole as String
    ]

    // MARK: - Attribute Reading

    static func attributeNames(on element: AXUIElement) -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &names)
        guard result == .success, let names else { return [] }
        return names as? [String] ?? []
    }

    static func parameterizedAttributeNames(on element: AXUIElement) -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(element, &names)
        guard result == .success, let names else { return [] }
        return names as? [String] ?? []
    }

    static func stringValue(for attribute: CFString, on element: AXUIElement) -> String? {
        guard let value = copyAttributeValue(attribute, on: element) else { return nil }
        if let string = value as? String { return string }
        if let attributedString = value as? NSAttributedString { return attributedString.string }
        return nil
    }

    static func boolValue(for attribute: CFString, on element: AXUIElement) -> Bool? {
        guard let number = copyAttributeValue(attribute, on: element) as? NSNumber else { return nil }
        return number.boolValue
    }

    private static func axValue(from value: AnyObject?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    static func rangeValue(for attribute: CFString, on element: AXUIElement) -> NSRange? {
        guard let axValue = axValue(from: copyAttributeValue(attribute, on: element)) else { return nil }
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func rectValue(for attribute: CFString, on element: AXUIElement) -> CGRect? {
        guard let axValue = axValue(from: copyAttributeValue(attribute, on: element)) else { return nil }
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func parameterizedRectValue(
        for attribute: CFString,
        range: NSRange,
        on element: AXUIElement
    ) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }

        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value)
        guard result == .success, let axValue = axValue(from: value) else { return nil }
        guard AXValueGetType(axValue) == .cgRect else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    // MARK: - Text Marker Support (Chromium)

    /// Some applications (like Chromium and WebKit browsers) do not properly support AXBoundsForRange
    /// using NSRange. Instead, they use a private AXTextMarker system. This bypasses that.
    static func textMarkerCaretRect(on element: AXUIElement) -> CGRect? {
        let selectedMarkerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
        var markerRangeValue: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(element, selectedMarkerRangeAttribute, &markerRangeValue)
        guard result == .success, let markerRange = markerRangeValue else { return nil }

        let boundsForMarkerRangeAttribute = "AXBoundsForTextMarkerRange" as CFString
        var boundsValue: CFTypeRef?
        result = AXUIElementCopyParameterizedAttributeValue(element, boundsForMarkerRangeAttribute, markerRange, &boundsValue)
        guard result == .success, let axBounds = axValue(from: boundsValue) else { return nil }
        guard AXValueGetType(axBounds) == .cgRect else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(axBounds, .cgRect, &rect) else { return nil }
        return rect
    }

    static func copyAttributeValue(_ attribute: CFString, on element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as AnyObject?
    }

    // MARK: - Tree Traversal

    static func focusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let element = value else { return nil }
        guard CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(element, to: AXUIElement.self)
    }

    static func parentElement(of element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttributeValue(kAXParentAttribute as CFString, on: element) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func childElements(of element: AXUIElement) -> [AXUIElement] {
        guard let values = copyAttributeValue(kAXChildrenAttribute as CFString, on: element) as? [AnyObject] else {
            return []
        }
        return values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
    }

    static func elementIdentity(for element: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return "\(pid)-\(CFHash(element))"
    }

    static func elementIdentifier(for element: AXUIElement, bundleIdentifier: String) -> String {
        "\(bundleIdentifier)-\(elementIdentity(for: element))"
    }

    // MARK: - Editability Heuristics

    static func editabilityHintScore(role: String, explicitEditableFlag: Bool?) -> Int {
        var score = 0
        if explicitEditableFlag == true { score += 10 }
        if isKnownEditableRole(role) { score += 1 }
        return score
    }

    static func hasStrongEditabilitySignal(role: String, explicitEditableFlag: Bool?) -> Bool {
        explicitEditableFlag == true || isKnownEditableRole(role)
    }

    static func isKnownEditableRole(_ role: String) -> Bool {
        knownEditableRoles.contains(role)
    }

    static func isKnownReadOnlyRole(_ role: String) -> Bool {
        knownReadOnlyRoles.contains(role)
    }

    // MARK: - Coordinate Conversion

    /// Converts raw Accessibility coordinates into global AppKit points via a per-display Y-flip.
    static func cocoaRect(fromAccessibilityRect rect: CGRect) -> CGRect {
        guard !rect.isNull, rect != .zero else { return rect }
        let displays = displayGeometries()
        if let converted = DisplayCoordinateConverter.appKitRect(
            fromCoreGraphicsRect: rect,
            displays: displays
        ) {
            return converted
        }
        return legacyDesktopUnionFlip(rect)
    }

    /// Converts a text-range AX rect to Cocoa coordinates, using the element's AXFrame as anchor.
    static func validatedCocoaTextRect(
        fromAccessibilityRect textRect: CGRect,
        anchorFrame cocoaAnchorFrame: CGRect?
    ) -> CGRect {
        guard !textRect.isNull, textRect != .zero else { return textRect }

        let displays = displayGeometries()
        guard !displays.isEmpty else { return textRect }

        let flipped = DisplayCoordinateConverter.appKitRect(
            fromCoreGraphicsRect: textRect,
            displays: displays
        ) ?? legacyDesktopUnionFlip(textRect)

        guard let anchor = cocoaAnchorFrame, !anchor.isEmpty else { return flipped }

        let tolerance: CGFloat = 80
        let expandedAnchor = anchor.insetBy(dx: -tolerance, dy: -tolerance)

        if expandedAnchor.contains(CGPoint(x: flipped.midX, y: flipped.midY)) {
            return flipped
        }

        for scaledFlipped in DisplayCoordinateConverter.appKitRectsFromPixelRect(
            textRect,
            displays: displays
        ) where expandedAnchor.contains(CGPoint(x: scaledFlipped.midX, y: scaledFlipped.midY)) {
            return scaledFlipped
        }

        return flipped
    }

    private static func displayGeometries() -> [DisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
            else { return nil }

            let displayID = CGDirectDisplayID(number.uint32Value)
            return DisplayGeometry(
                appKitFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                coreGraphicsBounds: CGDisplayBounds(displayID),
                backingScaleFactor: screen.backingScaleFactor
            )
        }
    }

    private static func legacyDesktopUnionFlip(_ rect: CGRect) -> CGRect {
        let desktopBounds = NSScreen.screens
            .map(\.frame)
            .reduce(into: CGRect.null) { $0 = $0.union($1) }
        guard !desktopBounds.isNull else { return rect }
        return CGRect(
            x: rect.origin.x,
            y: desktopBounds.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}