import AppKit
import SwiftUI
import OSLog

/// Manages a borderless, transparent NSPanel that floats ghost text
/// near the cursor in the focused third-party app.
///
/// Inspired by KeyType's `GhostTextOverlayWindow` (CompletionUI package):
/// - Uses `NSPanel` with `.nonactivatingPanel` instead of `NSWindow`
///   so the panel never activates Keybreeze or steals focus.
/// - Reads the field's actual font from AX and sizes it from the caret
///   height (not a hardcoded point size), matching the host app's text.
/// - Applies per-app font size adjustment and vertical alignment offset
///   from `AppCompatibility` overrides.
/// - Adds a subtle contrast shadow so ghost text is readable on both
///   light and dark backgrounds.
@MainActor
final class SuggestionOverlayWindowController: @unchecked Sendable {
    private let log = Logger(subsystem: "app.keybreeze", category: "overlay")
    private var window: NSPanel?

    /// Tracks the last text we displayed — used to skip redundant updates
    /// during streaming when the content hasn't actually changed size.
    private var lastDisplayedText: String = ""

    /// Minimum distance (in points) the cursor must move before repositioning.
    /// Prevents the overlay from "jumping" on tiny cursor rect fluctuations.
    private let minimumRepositionDistance: CGFloat = 8

    /// The last position we actually rendered the overlay at (AppKit coordinates).
    /// Used to enforce the minimum reposition distance.
    private var lastRenderedOrigin: CGPoint?

    // MARK: Configuration

    /// Font size matching a typical NSFont.systemFont(ofSize: ...) for body text.
    /// Sourced from `GhostTextStyle` for consistency with the playground.
    var fontSize: CGFloat = GhostTextStyle.overlayFontSize
    /// Opacity of the ghost text — sourced from `GhostTextStyle`.
    var ghostOpacity: CGFloat = GhostTextStyle.overlayGhostOpacity
    /// Per-app font size adjustment factor (1.0 = no adjustment).
    var fontSizeAdjustmentFactor: Double = 1.0
    /// Per-app vertical alignment offset (in points). Positive = shift down.
    var verticalAlignmentOffset: Double = 0

    // MARK: Visibility

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: Show / Update / Hide

    /// Shows ghost text at the specified cursor position.
    /// Reuses the existing window when possible to avoid flicker during
    /// streaming token updates. Only recreates the window on first show
    /// or after a hide.
    ///
    /// - Parameters:
    ///   - text: The ghost text to display.
    ///   - cursorRect: Cursor rect in AX coordinates (top-left origin).
    ///   - fieldFont: The field's font resolved from AX (optional). When
    ///     provided, the overlay uses this font family sized from the caret
    ///     height for pixel-perfect matching with the host app's text.
    ///   - bundleID: Bundle ID for per-app overlay preferences.
    func show(text: String, at cursorRect: CGRect, fieldFont: NSFont? = nil, bundleID: String? = nil) {
        guard !text.isEmpty else {
            log.debug("show() called with empty text — hiding")
            hide()
            return
        }

        // Resolve per-app overlay preferences
        let appFontSizeAdjustment = AppCompatibility.fontSizeAdjustmentFactor(for: bundleID)
        let appVerticalOffset = AppCompatibility.verticalAlignmentOffset(for: bundleID)
        self.fontSizeAdjustmentFactor = appFontSizeAdjustment
        self.verticalAlignmentOffset = appVerticalOffset

        // Resolve the effective cursor rect. If the rect is invalid/zero,
        // compute a fallback position so the overlay still appears.
        let effectiveRect: CGRect
        if cursorRect.width >= 0, cursorRect.height > 0 {
            effectiveRect = cursorRect
            log.debug("Using provided cursorRect: (\(effectiveRect.origin.x), \(effectiveRect.origin.y), \(effectiveRect.size.width)x\(effectiveRect.size.height))")
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            // Fallback: position overlay at left-center of the screen
            effectiveRect = CGRect(
                x: screen.visibleFrame.minX + 50,
                y: screen.visibleFrame.midY,
                width: 2,
                height: 16
            )
            log.debug("Fallback cursorRect (screen-based): (\(effectiveRect.origin.x), \(effectiveRect.origin.y), \(effectiveRect.size.width)x\(effectiveRect.size.height))")
        } else {
            // Ultimate fallback: a reasonable fixed position
            effectiveRect = CGRect(x: 100, y: 300, width: 2, height: 16)
            log.debug("Fallback cursorRect (hardcoded): (\(effectiveRect.origin.x), \(effectiveRect.origin.y), \(effectiveRect.size.width)x\(effectiveRect.size.height))")
        }

        // Resolve font: use field font from AX when available, otherwise
        // fall back to the hardcoded fontSize. The resolved font is sized
        // from the caret height to match the host app's rendered text.
        let resolvedFont = resolveFont(fieldFont, caretHeight: effectiveRect.height)

        // Build the SwiftUI ghost content
        let ghostView = InlineGhostTextView(
            text: text,
            font: resolvedFont,
            opacity: ghostOpacity,
            fontSizeAdjustmentFactor: appFontSizeAdjustment
        )

        let hostingView = NSHostingView(rootView: ghostView)
        hostingView.frame.size = hostingView.fittingSize
        log.debug("HostingView fittingSize: (\(hostingView.frame.size.width)x\(hostingView.frame.size.height))")

        // Cap width so very long predictions don't span the whole screen
        let maxWidth: CGFloat = GhostTextStyle.overlayMaxWidth
        if hostingView.frame.width > maxWidth {
            hostingView.frame.size.width = maxWidth
            hostingView.frame.size = hostingView.fittingSize
            log.debug("Width capped to \(maxWidth), new fittingSize: (\(hostingView.frame.size.width)x\(hostingView.frame.size.height))")
        }

        let contentSize = hostingView.frame.size

        // Find the screen containing the cursor rect to handle multi-monitor setups
        let screen = NSScreen.screens.first { $0.frame.contains(effectiveRect.origin) } ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.frame

        // AX coordinate space: (0,0) = top-left of main screen.
        // NSScreen coordinate space: (0,0) = bottom-left of main screen.
        // X converts directly.
        // Y conversion:
        //   The AX coordinate (effectiveRect.origin.y) is top-down from the top of the screen (in AX space).
        //   If screens have different origins, we need to be careful.
        //   However, for the screen containing the rect, we can calculate Y relative to that screen.
        //
        //   Let's use the screen's frame for coordinate conversion.
        let x = effectiveRect.origin.x + effectiveRect.width

        // Apply per-app vertical alignment offset (positive = shift down in AX = shift up in AppKit)
        let verticalOffsetPoints = CGFloat(appVerticalOffset)
        let y = screenFrame.maxY - effectiveRect.origin.y - effectiveRect.height - contentSize.height - 2 - verticalOffsetPoints


        // Clamp to screen bounds so the overlay is always fully visible
        let clampedX = max(screenFrame.minX + 2, min(x, screenFrame.maxX - contentSize.width - 2))
        let clampedY = max(screenFrame.minY + 2, min(y, screenFrame.maxY - contentSize.height - 2))

        let newFrame = NSRect(
            origin: CGPoint(x: clampedX, y: clampedY),
            size: contentSize
        )

        // Reuse existing window if possible — avoids flicker from destroy+recreate
        if let existingWindow = window, existingWindow.isVisible {
            // Update content view for streaming tokens
            existingWindow.contentView = hostingView

            // Position stabilization: only reposition if the cursor has moved
            // significantly. This prevents the overlay from "jumping" on tiny
            // cursor rect fluctuations between keystrokes.
            let shouldReposition: Bool
            if let lastOrigin = lastRenderedOrigin {
                let dx = newFrame.origin.x - lastOrigin.x
                let dy = newFrame.origin.y - lastOrigin.y
                let distance = sqrt(dx * dx + dy * dy)
                shouldReposition = distance >= minimumRepositionDistance
            } else {
                shouldReposition = true // First show — always position
            }

            if shouldReposition {
                existingWindow.setFrame(newFrame, display: true, animate: false)
                lastRenderedOrigin = newFrame.origin
                log.debug("✅ Overlay window repositioned — frame=(\(newFrame.origin.x), \(newFrame.origin.y), \(newFrame.size.width)x\(newFrame.size.height))")
            } else {
                log.debug("✅ Overlay window kept position (delta too small) — keeping at (\(existingWindow.frame.origin.x), \(existingWindow.frame.origin.y))")
            }
        } else {
            // Hide any existing window state before creating new one
            hide()

            // Use NSPanel with .nonactivatingPanel so the panel never
            // activates Keybreeze or steals focus from the host app.
            // This matches KeyType's GhostTextOverlayWindow recipe.
            let panel = NSPanel(
                contentRect: newFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.backgroundColor = .clear
            panel.contentView = hostingView
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none

            self.window = panel

            // Show without activating Keybreeze
            panel.orderFrontRegardless()
            lastRenderedOrigin = newFrame.origin
            log.debug("✅ Overlay panel created — frame=(\(newFrame.origin.x), \(newFrame.origin.y), \(newFrame.size.width)x\(newFrame.size.height)) isVisible=\(panel.isVisible)")
        }

        // Track displayed text for redundant-update detection
        lastDisplayedText = text
    }

    /// Hides the overlay immediately.
    func hide() {
        guard let window else {
            return
        }
        log.debug("Hiding overlay window")
        window.orderOut(nil)
        self.window = nil
        lastDisplayedText = ""
        lastRenderedOrigin = nil  // Reset so next show() always positions
    }

    /// Repositions the overlay if it's currently visible, using a new cursor rect.
    /// Does not recreate the window — just moves it.
    func reposition(at cursorRect: CGRect) {
        guard let window, window.isVisible else {
            log.debug("reposition() called but no visible window")
            return
        }

        guard cursorRect.width >= 0, cursorRect.height > 0 else {
            log.debug("reposition() called with invalid rect — hiding")
            hide()
            return
        }

        // Find the screen containing the cursor rect to handle multi-monitor setups
        let screen = NSScreen.screens.first { $0.frame.contains(cursorRect.origin) } ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.frame
        let contentSize = window.frame.size

        let x = cursorRect.origin.x + cursorRect.width
        let verticalOffsetPoints = CGFloat(verticalAlignmentOffset)
        let y = screenFrame.maxY - cursorRect.origin.y - cursorRect.height - contentSize.height - 2 - verticalOffsetPoints

        let clampedX = max(screenFrame.minX + 2, min(x, screenFrame.maxX - contentSize.width - 2))
        let clampedY = max(screenFrame.minY + 2, min(y, screenFrame.maxY - contentSize.height - 2))

        log.debug("Repositioning overlay to (\(clampedX), \(clampedY))")
        window.setFrameOrigin(CGPoint(x: clampedX, y: clampedY))
    }

    // MARK: - Font Resolution

    /// Resolves the ghost text font from the field's AX font and caret height.
    ///
    /// Matches KeyType's `InlineGhostTextPresenter.resolveFont()`:
    /// - Keeps the field's **typeface** (family) from AX
    /// - Sizes it from the **caret height** rather than AX's reported point size
    ///   (several apps report the correct family but a default/stale size)
    /// - Applies the per-app `fontSizeAdjustmentFactor`
    /// - Falls back to system font when no field font is known
    private func resolveFont(_ fieldFont: NSFont?, caretHeight: CGFloat) -> NSFont {
        let fallbackLineHeight = fieldFont.map { ceil($0.ascender - $0.descender) }
            ?? ceil(NSFont.systemFont(ofSize: NSFont.systemFontSize).ascender
                    - NSFont.systemFont(ofSize: NSFont.systemFontSize).descender)

        // Trusted caret height: clamp oversized caret rects from AX
        let trustedHeight: CGFloat = {
            guard caretHeight > 0 else { return fallbackLineHeight }
            // If the caret height is suspiciously large relative to the field,
            // fall back to the system font size to avoid huge ghost text.
            if caretHeight >= 48 { return max(8, min(32, fallbackLineHeight)) }
            return max(8, min(48, caretHeight))
        }()

        if let font = fieldFont {
            let metricsHeight = font.ascender - font.descender
            let derived = (trustedHeight > 0 && metricsHeight > 0)
                ? trustedHeight * font.pointSize / metricsHeight
                : font.pointSize
            let size = max(1, derived * fontSizeAdjustmentFactor)
            if let scaled = NSFont(descriptor: font.fontDescriptor, size: size) {
                return scaled
            }
            return font
        }

        // No field font: estimate from caret height (~0.83× for typical UI fonts)
        let estimated = trustedHeight > 0 ? trustedHeight * 0.83 : NSFont.systemFontSize
        return .systemFont(ofSize: max(8, min(96, estimated * fontSizeAdjustmentFactor)))
    }
}

// MARK: - SwiftUI Ghost Text View

/// Renders inline ghost text — just the suggestion, grey and translucent,
/// matching Keybreeze's GhostTextModifier style but without the committed
/// text (that's already in the host app's text field).
///
/// Enhanced with KeyType-inspired contrast shadow for readability on both
/// light and dark backgrounds.
struct InlineGhostTextView: View {
    let text: String
    let font: NSFont
    let opacity: CGFloat
    let fontSizeAdjustmentFactor: CGFloat

    /// Legacy initializer for backward compatibility (uses hardcoded font size).
    init(text: String, fontSize: CGFloat = GhostTextStyle.overlayFontSize, opacity: CGFloat = GhostTextStyle.overlayGhostOpacity, fontSizeAdjustmentFactor: CGFloat = 1.0) {
        self.text = text
        self.font = NSFont.systemFont(ofSize: fontSize)
        self.opacity = opacity
        self.fontSizeAdjustmentFactor = fontSizeAdjustmentFactor
    }

    /// New initializer using resolved field font (from AX).
    init(text: String, font: NSFont, opacity: CGFloat, fontSizeAdjustmentFactor: CGFloat) {
        self.text = text
        self.font = font
        self.opacity = opacity
        self.fontSizeAdjustmentFactor = fontSizeAdjustmentFactor
    }

    private var foregroundColor: Color {
        Color(nsColor: visibleGhostColor())
    }

    private var shadowColor: Color {
        Color(nsColor: contrastShadowColor())
    }

    var body: some View {
        Text(text)
            .font(Font(font as CTFont))
            .foregroundStyle(foregroundColor)
            .shadow(color: shadowColor, radius: 0.6, x: 0, y: 0)
            .lineLimit(GhostTextStyle.lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
    }

    /// Ghost text follows the field's own text color when trustworthy, but
    /// browser AX occasionally reports a foreground color that is effectively
    /// the page background. Keep the final color semi-muted while forcing
    /// near-white/near-black extremes back toward visible gray.
    private func visibleGhostColor() -> NSColor {
        // Use a default grey when no field color is available
        let baseColor = NSColor(calibratedWhite: 0.42, alpha: 1.0)
        let luminance = relativeLuminance(baseColor)
        if luminance > 0.9 || luminance < 0.08 {
            return NSColor(calibratedWhite: 0.36, alpha: opacity)
        }
        return baseColor.withAlphaComponent(opacity)
    }

    /// Subtle contrast shadow so ghost text is readable on both light and dark backgrounds.
    /// Matches KeyType's GhostTextView approach.
    private func contrastShadowColor() -> NSColor {
        NSColor.white.withAlphaComponent(0.45)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0.5 }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }
}