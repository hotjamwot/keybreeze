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

    /// Tracks the last text we displayed — used to skip redundant updates
    /// during streaming when the content hasn't actually changed size.
    private var lastDisplayedText: String = ""

    // MARK: Configuration

    /// Font size matching a typical NSFont.systemFont(ofSize: ...) for body text.
    var fontSize: CGFloat = 14
    /// Opacity of the ghost text (matching GhostTextModifier's 0.45).
    var ghostOpacity: CGFloat = 0.45

    // MARK: Visibility

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: Show / Update / Hide

    /// Shows ghost text at the specified cursor position.
    /// Reuses the existing window when possible to avoid flicker during
    /// streaming token updates. Only recreates the window on first show
    /// or after a hide.
    func show(text: String, at cursorRect: CGRect) {
        guard !text.isEmpty else {
            log.debug("show() called with empty text — hiding")
            hide()
            return
        }

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
        let y = screenFrame.maxY - effectiveRect.origin.y - effectiveRect.height - contentSize.height - 2


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
            existingWindow.setFrame(newFrame, display: true, animate: false)
            log.debug("✅ Overlay window reused — frame=(\(newFrame.origin.x), \(newFrame.origin.y), \(newFrame.size.width)x\(newFrame.size.height)) isVisible=\(existingWindow.isVisible)")
        } else {
            // Hide any existing window state before creating new one
            hide()

            let overlayWindow = NSWindow(
                contentRect: newFrame,
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
            log.debug("✅ Overlay window created — frame=(\(newFrame.origin.x), \(newFrame.origin.y), \(newFrame.size.width)x\(newFrame.size.height)) isVisible=\(overlayWindow.isVisible)")
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
        let y = screenFrame.maxY - cursorRect.origin.y - cursorRect.height - contentSize.height - 2

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