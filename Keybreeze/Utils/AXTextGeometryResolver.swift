import AppKit
import ApplicationServices
import Foundation

/// Resolves caret and input-frame geometry from AX elements.
/// Centralizes the fragile browser/native heuristics used to place overlays correctly.
///
/// Ported from Cotabby's AXTextGeometryResolver.
@MainActor
struct AXTextGeometryResolver {
    /// Resolves the full input frame for workflows that need the whole field bounds.
    func resolveInputFrameRect(for element: AXUIElement) -> CGRect? {
        guard let frame = AXHelper.rectValue(for: "AXFrame" as CFString, on: element),
            !frame.isEmpty
        else {
            return nil
        }
        return AXHelper.cocoaRect(fromAccessibilityRect: frame)
    }

    /// Finds the best caret anchor available, preferring bounds-for-range and falling back to
    /// element frame estimation.
    func resolveCaretRect(
        for element: AXUIElement,
        selection: NSRange,
        supportsBoundsForRange: Bool,
        supportsFrame: Bool,
        cocoaAnchorFrame: CGRect?,
        textValue: String? = nil
    ) -> CaretGeometryResult? {
        // Branch 1: Zero-length BoundsForRange at the caret position.
        if supportsBoundsForRange,
            let rect = AXHelper.parameterizedRectValue(
                for: kAXBoundsForRangeParameterizedAttribute as CFString,
                range: NSRange(location: selection.location, length: 0),
                on: element
            ), !rect.isEmpty {
            let cocoaRect = AXHelper.validatedCocoaTextRect(
                fromAccessibilityRect: rect,
                anchorFrame: cocoaAnchorFrame
            )
            if rectIsNearAnchor(cocoaRect, anchor: cocoaAnchorFrame) {
                return CaretGeometryResult(
                    rect: normalizedCaretRect(fromZeroLengthRangeRect: cocoaRect),
                    quality: .exact
                )
            }
        }

        // Branch 1.5: Chromium / WebKit AXTextMarker fallback.
        if let markerRect = AXHelper.textMarkerCaretRect(on: element), !markerRect.isEmpty {
            let cocoaRect = AXHelper.validatedCocoaTextRect(
                fromAccessibilityRect: markerRect,
                anchorFrame: cocoaAnchorFrame
            )
            return CaretGeometryResult(
                rect: normalizedCaretRect(fromZeroLengthRangeRect: cocoaRect),
                quality: .exact
            )
        }

        // Branch 2: BoundsForRange on the character before the caret.
        if supportsBoundsForRange,
            selection.location > 0,
            let rect = AXHelper.parameterizedRectValue(
                for: kAXBoundsForRangeParameterizedAttribute as CFString,
                range: NSRange(location: selection.location - 1, length: 1),
                on: element
            ), !rect.isEmpty {
            let cocoaRect = AXHelper.validatedCocoaTextRect(
                fromAccessibilityRect: rect,
                anchorFrame: cocoaAnchorFrame
            )
            if rectIsNearAnchor(cocoaRect, anchor: cocoaAnchorFrame) {
                return CaretGeometryResult(
                    rect: CGRect(
                        x: cocoaRect.maxX, y: cocoaRect.minY, width: 2, height: cocoaRect.height),
                    quality: .derived
                )
            }
        }

        // Branch 2.5: Child text-run proportional estimation.
        if let parentText = textValue, !parentText.isEmpty {
            if let result = resolveCaretFromChildTextRuns(
                element: element,
                parentSelection: selection,
                parentText: parentText
            ) {
                return result
            }
        }

        // Branch 3: AXFrame fallback.
        if supportsFrame,
            let frame = AXHelper.rectValue(for: "AXFrame" as CFString, on: element), !frame.isEmpty {
            let cocoaRect = AXHelper.cocoaRect(fromAccessibilityRect: frame)
            if cocoaRect.width > 10, let text = textValue {
                let estimatedX = conservativeEstimatedCaretX(
                    in: cocoaRect,
                    text: text,
                    selection: selection
                )
                let clampedX = min(estimatedX, cocoaRect.maxX)
                return CaretGeometryResult(
                    rect: CGRect(
                        x: clampedX, y: cocoaRect.minY, width: 2, height: cocoaRect.height),
                    quality: .estimated
                )
            }
            return CaretGeometryResult(rect: cocoaRect, quality: .estimated)
        }

        return nil
    }

    private func conservativeEstimatedCaretX(
        in cocoaRect: CGRect,
        text: String,
        selection: NSRange
    ) -> CGFloat {
        let nsText = text as NSString
        let safeLocation = min(selection.location, nsText.length)
        let prefix = nsText.substring(to: safeLocation)
        let currentLinePrefix = prefix.components(separatedBy: .newlines).last ?? prefix
        let lineNSString = currentLinePrefix as NSString

        let estimatedWidthBias: CGFloat = 1.1
        let measuredWidth =
            lineNSString.size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 15)
            ]).width * estimatedWidthBias
        let perCharacterCeiling: CGFloat = 13.3 * estimatedWidthBias
        let estimatedWidth = min(
            measuredWidth,
            CGFloat(lineNSString.length) * perCharacterCeiling
        )

        return cocoaRect.minX + estimatedWidth
    }

    private func resolveCaretFromChildTextRuns(
        element: AXUIElement,
        parentSelection: NSRange,
        parentText: String
    ) -> CaretGeometryResult? {
        let parentTextLength = (parentText as NSString).length
        guard parentSelection.location <= parentTextLength else { return nil }

        let textRuns = collectStaticTextRuns(from: element)
        guard !textRuns.isEmpty else { return nil }

        var totalChars = 0
        var totalWidth: CGFloat = 0
        for run in textRuns {
            totalChars += (run.text as NSString).length
            totalWidth += run.frame.width
        }
        let charWidth: CGFloat? = totalChars > 0 ? totalWidth / CGFloat(totalChars) : nil

        let caretOffset = parentSelection.location
        var cumulative = 0
        for run in textRuns {
            let runLen = (run.text as NSString).length
            if caretOffset <= cumulative + runLen {
                let localOffset = caretOffset - cumulative
                let fraction = runLen > 0 ? CGFloat(localOffset) / CGFloat(runLen) : 1.0
                let cocoaFrame = AXHelper.cocoaRect(fromAccessibilityRect: run.frame)
                let caretX = cocoaFrame.minX + fraction * cocoaFrame.width
                return CaretGeometryResult(
                    rect: CGRect(
                        x: caretX, y: cocoaFrame.minY, width: 2, height: cocoaFrame.height),
                    quality: .derived,
                    observedCharWidth: charWidth
                )
            }
            cumulative += runLen
        }

        let lastFrame = AXHelper.cocoaRect(fromAccessibilityRect: textRuns.last!.frame)
        return CaretGeometryResult(
            rect: CGRect(x: lastFrame.maxX, y: lastFrame.minY, width: 2, height: lastFrame.height),
            quality: .derived,
            observedCharWidth: charWidth
        )
    }

    private func collectStaticTextRuns(from root: AXUIElement) -> [(text: String, frame: CGRect)] {
        let maxDepth = 8
        let maxNodes = 300
        var visitedNodes = 0
        var seen = Set<String>()
        var runs: [(text: String, frame: CGRect)] = []

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= maxDepth, visitedNodes < maxNodes else { return }
            let identity = AXHelper.elementIdentity(for: element)
            guard seen.insert(identity).inserted else { return }
            visitedNodes += 1

            let role = AXHelper.stringValue(for: kAXRoleAttribute as CFString, on: element)
            if role == kAXStaticTextRole as String,
                let text = AXHelper.stringValue(for: kAXValueAttribute as CFString, on: element),
                !text.isEmpty,
                let frame = AXHelper.rectValue(for: "AXFrame" as CFString, on: element),
                !frame.isEmpty {
                runs.append((text, frame))
            }

            guard depth < maxDepth else { return }
            for child in AXHelper.childElements(of: element) {
                walk(child, depth: depth + 1)
            }
        }

        for child in AXHelper.childElements(of: root) {
            walk(child, depth: 1)
        }

        return runs
    }

    /// Confirms a BoundsForRange result actually belongs to the focused field's neighborhood.
    func rectIsNearAnchor(_ cocoaRect: CGRect, anchor: CGRect?) -> Bool {
        guard let anchor, !anchor.isEmpty else { return true }
        let tolerance: CGFloat = 80
        let expanded = anchor.insetBy(dx: -tolerance, dy: -tolerance)
        return expanded.contains(CGPoint(x: cocoaRect.midX, y: cocoaRect.midY))
    }

    private func normalizedCaretRect(fromZeroLengthRangeRect rect: CGRect) -> CGRect {
        guard !rect.isEmpty else { return rect }
        let normalizedWidth: CGFloat = 2
        return CGRect(x: rect.minX, y: rect.minY, width: normalizedWidth, height: rect.height)
    }
}

/// Pairs a caret rect with the method that produced it.
struct CaretGeometryResult {
    let rect: CGRect
    let quality: CaretGeometryQuality
    let observedCharWidth: CGFloat?

    init(rect: CGRect, quality: CaretGeometryQuality, observedCharWidth: CGFloat? = nil) {
        self.rect = rect
        self.quality = quality
        self.observedCharWidth = observedCharWidth
    }
}