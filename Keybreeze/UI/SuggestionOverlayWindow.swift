import AppKit
import SwiftUI
import OSLog

/// Manages a borderless, transparent NSWindow that floats ghost text
/// near the cursor in the focused third-party app.
///
/// Inline ghost text (same baseline as the app's text, grey/translucent)
/// positioned immediately after the caret. Uses `popUpMenu` window level
/// so it appears above all normal app windows without stealing focus.
///
/// The overlay ignores mouse events entirely — the user can click through
/// it to interact with the underlying app.
@MainActor
final class SuggestionOverlayWindowController: @unchecked Sendable {
    private let log = Logger(subsystem: "app.keybreeze", category: "overlay")
    private var window: NSWindow?

    // MARK: Configuration

    /// Font size matching a typical NSFont.systemFont(ofSize: ...) for body text.
    var fontSize: CGFloat = 14
    /// Opacity of the ghost text (matching GhostTextModifier's 0.45).
    var ghostOpacity: CGFloat = 0.45

    // MARK: Visibility

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: Show / Hide

    /// Shows ghost text at the specified cursor position.
    /// - Parameters:
    ///   - text: The suggestion text to display (just the ghost part, not the committed text).
    ///   - cursorRect: Cursor bounding rect in AX coordinate space (origin top-left of main screen).
    ///                If `.zero` or invalid, the overlay will still appear at a computed
    ///                default position (centered near top of screen). This ensures the overlay
    ///                always shows even when AX cursor rect extraction fails.
    func show(text: String, at cursorRect: CGRect) {
        guard !text.isEmpty else {
            log.debug("show() called with empty text — hiding")
            hide()
            return
        }

        // Always hide existing window before creating a new one
        hide()

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
            log.debug("Fallback cursorRect (screen-based): (\(effectiveRect.origin.x), \(effectiveRect.origin.y), \(effectiveRect.size.width)x\(effectiveRect.size.height)) — screen=(\(screen.visibleFrame.origin.x), \(screen.visibleFrame.origin.y), \(screen.visibleFrame.size.width)x\(screen.visibleFrame.size.height))")
        } else {
            // Ultimate fallback: a reasonable fixed position
            effectiveRect = CGRect(x: 100, y: 300, width: 2, height: 16)
            log.debug("Fallback cursorRect (hardcoded): (\(effectiveRect.origin.x), \(effectiveRect.origin.y), \(effectiveRect.size.width)x\(effectiveRect.size.height))")
        }

        // Build the SwiftUI ghost content
        let ghostView = InlineGhostTextView(
            text: text,
            fontSize: fontSize,
            opacity: ghostOpacity
        )

        let hostingView = NSHostingView(rootView: ghostView)
        hostingView.frame.size = hostingView.fittingSize
        log.debug("HostingView fittingSize: (\(hostingView.frame.size.width)x\(hostingView.frame.size.height))")

        // Cap width so very long predictions don't span the whole screen
        let maxWidth: CGFloat = 600
        if hostingView.frame.width > maxWidth {
            hostingView.frame.size.width = maxWidth
            hostingView.frame.size = hostingView.fittingSize
            log.debug("Width capped to \(maxWidth), new fittingSize: (\(hostingView.frame.size.width)x\(hostingView.frame.size.height))")
        }

        let contentSize = hostingView.frame.size

        // Convert AX coordinates (origin top-left) to NSScreen coordinates (origin bottom-left)
        // and position the overlay just after the cursor (to the right, same baseline).
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            log.warning("No screen available — cannot position overlay")
            return
        }

        // Use effectiveRect for positioning
        let screenFrame = screen.frame

        // AX coordinate space: (0,0) = top-left of main screen.
        // NSScreen coordinate space: (0,0) = bottom-left of main screen.
        let x = effectiveRect.origin.x + effectiveRect.width
        let y = screenFrame.height - effectiveRect.origin.y - effectiveRect.height - contentSize.height + 2

        // Clamp to screen bounds so the overlay is always fully visible
        let clampedX = max(screenFrame.minX + 2, min(x, screenFrame.maxX - contentSize.width - 2))
        let clampedY = max(screenFrame.minY + 2, min(y, screenFrame.maxY - contentSize.height - 2))

        let windowFrame = NSRect(
            origin: CGPoint(x: clampedX, y: clampedY),
            size: contentSize
        )
        log.debug("Overlay window frame: (\(windowFrame.origin.x), \(windowFrame.origin.y), \(windowFrame.size.width)x\(windowFrame.size.height)) (pre-clamp x=\(x) y=\(y))")

        let overlayWindow = NSWindow(
            contentRect: windowFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        overlayWindow.level = .popUpMenu
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        overlayWindow.contentView = hostingView
        overlayWindow.animationBehavior = .none

        self.window = overlayWindow

        // Show without activating Keybreeze
        overlayWindow.orderFrontRegardless()
        log.debug("✅ Overlay window ordered front — frame=(\(overlayWindow.frame.origin.x), \(overlayWindow.frame.origin.y), \(overlayWindow.frame.size.width)x\(overlayWindow.frame.size.height)) isVisible=\(overlayWindow.isVisible)")
    }

    /// Hides the overlay immediately.
    func hide() {
        guard let window else {
            log.debug("hide() called but no window exists")
            return
        }
        log.debug("Hiding overlay window")
        window.orderOut(nil)
        self.window = nil
    }

    /// Repositions the overlay if it's currently visible, using a new cursor rect.
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

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let screenFrame = screen.frame
        let contentSize = window.frame.size

        let x = cursorRect.origin.x + cursorRect.width
        let y = screenFrame.height - cursorRect.origin.y - cursorRect.height - contentSize.height + 2

        let clampedX = max(screenFrame.minX + 2, min(x, screenFrame.maxX - contentSize.width - 2))
        let clampedY = max(screenFrame.minY + 2, min(y, screenFrame.maxY - contentSize.height - 2))

        log.debug("Repositioning overlay to (\(clampedX), \(clampedY))")
        window.setFrameOrigin(CGPoint(x: clampedX, y: clampedY))
    }
}

// MARK: - SwiftUI Ghost Text View

/// Renders inline ghost text — just the suggestion, grey and translucent,
/// matching Keybreeze's GhostTextModifier style but without the committed
/// text (that's already in the host app's text field).
struct InlineGhostTextView: View {
    let text: String
    let fontSize: CGFloat
    let opacity: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundColor(.secondary.opacity(opacity))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
    }
}