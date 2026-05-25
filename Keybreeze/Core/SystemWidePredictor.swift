import Foundation
import OSLog
import AppKit
import Combine

/// Bridges the Accessibility API text context into the CompletionController
/// for system-wide prediction.
///
/// Uses two complementary trigger mechanisms (inspired by Ghost Type):
/// 1. CGEventTap — captures keyDown events system-wide for instant trigger
/// 2. Idle safety poll — slower timer (500ms) catches paste/undo/mouse changes
///
/// Respects app gating (excluded/manual-only), IME composition safety,
/// and avoids processing Keybreeze's own windows (Typing Lab handles its own).
///
/// Also owns the SuggestionOverlayWindowController — a floating, transparent,
/// borderless window that displays ghost text after the cursor in the focused
/// third-party app.
@MainActor
final class SystemWidePredictor {
    private let log = Logger(subsystem: "app.keybreeze", category: "system-wide")

    // MARK: Dependencies

    private let controller: CompletionController
    private let accessibility: AccessibilityManager
    private let inputMonitor: InputSourceMonitor
    private let overlay: SuggestionOverlayWindowController
    private var cancellables = Set<AnyCancellable>()

    // MARK: Configuration

    /// Bundle IDs where auto-prediction is completely disabled.
    var excludedBundleIDs: [String] = []

    /// Bundle IDs where auto-prediction is disabled but manual Tab still works.
    var manualOnlyBundleIDs: [String] = []

    /// Whether predictions should fire in manual-only apps.
    var predictInManualOnly: Bool = false

    // MARK: State

    /// Idle safety poll task (500ms, catches paste/undo/mouse changes)
    private var pollTask: Task<Void, Never>?

    /// CGEventTap for system-wide keystroke capture
    private var eventTap: CFMachPort?

    /// The text context we last sent to the controller. We compare against this
    /// to skip redundant predictions when nothing changed.
    private var lastTextBeforeCursor: String = ""
    private var lastTextAfterCursor: String = ""

    /// The last known cursor rect (AX coordinate space) — used to position the overlay
    /// when a new suggestion arrives from the controller.
    private var lastCursorRect: CGRect = .zero

    /// The LAST VALID cursor rect we succeeded to fetch. When AX fails to resolve
    /// a new cursor rect (common in Terminal, web views, Electron apps), we keep
    /// using this cached value so the overlay still appears rather than getting
    /// permanently stuck at `.zero`.
    private var lastValidCursorRect: CGRect = .zero

    /// Tracks the last known cursor rect for cursor-movement detection.
    /// When text is unchanged but cursor moves (arrow keys, mouse click),
    /// we must invalidate the suggestion per §6.
    private var lastSeenCursorRect: CGRect = .zero

    /// The last app bundle ID we saw — used to detect app switches.
    private var lastAppBundleID: String?

    /// Whether we currently have an active text context (text field focused).
    private var hasActiveContext: Bool = false

    /// Consecutive failures to read AX context — used to implement a grace period
    /// before clearing the suggestion.
    private var axFailureCount: Int = 0
    private let axFailureThreshold: Int = 3

    /// Debounce task for triggered reads — ensures we wait for text to settle.
    private var debounceTask: Task<Void, Never>?

    // MARK: Published (for MenuBar display)

    /// Bundle ID of the currently focused app, or nil if none.
    @Published private(set) var focusedAppBundleID: String?

    /// Display name of the currently focused app.
    @Published private(set) var focusedAppName: String?

    /// Whether we're currently paused (e.g., IME composition active, or blocked app).
    @Published private(set) var isPaused: Bool = false

    /// Reason for pausing, shown in UI.
    @Published private(set) var pauseReason: String = ""

    // MARK: Init

    init(
        controller: CompletionController,
        accessibility: AccessibilityManager,
        inputMonitor: InputSourceMonitor
    ) {
        self.controller = controller
        self.accessibility = accessibility
        self.inputMonitor = inputMonitor
        self.overlay = SuggestionOverlayWindowController()

        // Observe suggestion changes from the controller and show/hide overlay.
        controller.$suggestion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] suggestion in
                guard let self else { return }
                if self.isPaused { return }
                if suggestion.isEmpty {
                    self.log.debug("Overlay: suggestion cleared → hiding")
                    self.overlay.hide()
                } else {
                    self.log.debug("Overlay: suggestion received '\(suggestion)' → showing at cursorRect=(\(self.lastCursorRect.origin.x), \(self.lastCursorRect.origin.y), \(self.lastCursorRect.size.width)x\(self.lastCursorRect.size.height))")
                    self.overlay.show(text: suggestion, at: self.lastCursorRect)
                }
            }
            .store(in: &cancellables)
    }

    /// Convenience init using the shared AccessibilityManager and InputSourceMonitor.
    /// These are @MainActor singletons, so this init must also be @MainActor.
    convenience init(controller: CompletionController) {
        self.init(
            controller: controller,
            accessibility: .shared,
            inputMonitor: .shared
        )
    }

    // MARK: Lifecycle

    func start() {
        guard pollTask == nil else {
            log.debug("start() called but already running")
            return
        }
        log.info("System-wide predictor starting...")
        resetState()

        // 1. Start CGEventTap for instant keystroke-based triggering.
        installEventTap()

        // 2. Start idle safety poll (500ms).
        pollTask = Task { [weak self] in
            await self?.idlePollLoop()
        }
    }

    func stop() {
        log.info("System-wide predictor stopping")
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        pollTask?.cancel()
        pollTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        overlay.hide()
        resetState()
        log.info("System-wide predictor stopped")
    }

    private func resetState() {
        lastTextBeforeCursor = ""
        lastTextAfterCursor = ""
        lastCursorRect = .zero
        lastValidCursorRect = .zero
        lastAppBundleID = nil
        hasActiveContext = false
        isPaused = false
        pauseReason = ""
        focusedAppBundleID = nil
        focusedAppName = nil
    }

    // MARK: — Event Tap (Primary Trigger)

    /// Installs a CGEventTap that captures keyDown events system-wide.
    private func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard type == .keyDown,
                  let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let predictor = Unmanaged<SystemWidePredictor>.fromOpaque(refcon).takeUnretainedValue()
            predictor.handleKeyDown()
            return Unmanaged.passUnretained(event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        )

        guard let eventTap else {
            log.warning("⚠️ Failed to create event tap! Run loop polling will be used as fallback. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        log.info("✅ Event tap installed for system-wide keystroke capture")
    }

    /// Called from the CGEventTap callback on every keyDown event.
    private func handleKeyDown() {
        guard shouldProcessCurrentApp() else { return }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(40))
                await self?.readAndPredict()
            } catch {
                // Cancelled
            }
        }
    }

    // MARK: — Idle Poll (Safety Net)

    /// Polls every 500ms to catch non-keyboard text changes.
    private func idlePollLoop() async {
        log.debug("Idle poll loop started")
        let idleInterval: UInt64 = 500_000_000  // 500ms
        while !Task.isCancelled {
            if debounceTask == nil {
                await readAndPredict()
            }
            try? await Task.sleep(nanoseconds: idleInterval)
        }
    }

    // MARK: — Core Read + Predict

    /// Reads AX context from the focused app and, if changed, feeds it to the controller.
    private func readAndPredict() async {
        // 1. Check focused app
        guard let bundleID = accessibility.focusedAppBundleID() else {
            log.debug("No focused app bundle ID")
            handleNoFocus()
            return
        }

        focusedAppBundleID = bundleID
        focusedAppName = appName(for: bundleID)

        // 2. Gating checks (only log on app switch to reduce noise)
        if bundleID != lastAppBundleID {
            log.debug("Current focused app bundle ID: \(bundleID)")
        }

        if bundleID == "app.keybreeze.Keybreeze" {
            // log.debug("Current app is Keybreeze — ignoring")
            return
        }
        
        guard shouldProcessApp(bundleID) else {
            if bundleID != lastAppBundleID {
                log.debug("App switch to blocked app '\(bundleID)' — clearing suggestion")
                DispatchQueue.main.async { [weak self] in
                    self?.controller.suggestion = ""
                }
                hasActiveContext = false
            }
            return
        }

        // 3. IME safety
        guard inputMonitor.isASCIICompatible else {
            log.debug("IME composition active — pausing")
            setPaused(reason: "IME composition active")
            return
        }

        clearPaused()

        // 4. Detect app switch
        if bundleID != lastAppBundleID {
            log.debug("App switched to '\(bundleID)' — resetting context")
            lastAppBundleID = bundleID
            lastTextBeforeCursor = ""
            lastTextAfterCursor = ""
            hasActiveContext = false
        }

        // 5. Read text context via AX
        log.debug("Reading AX text context from '\(bundleID)'...")
        guard let context = accessibility.getTextContext(maxChars: 800) else {
            axFailureCount += 1
            log.debug("AX getTextContext returned nil (failure \(self.axFailureCount)/\(self.axFailureThreshold))")
            if hasActiveContext && axFailureCount >= axFailureThreshold {
                log.debug("Lost active text context — clearing suggestion")
                DispatchQueue.main.async { [weak self] in
                    self?.controller.suggestion = ""
                    self?.overlay.hide()
                }
                hasActiveContext = false
            }
            return
        }
        axFailureCount = 0
        log.debug("AX context: prefix='\(context.prefix.suffix(60))' suffix='\(context.suffix.prefix(20))' cursorRect=(\(context.cursorRect.origin.x), \(context.cursorRect.origin.y), \(context.cursorRect.size.width)x\(context.cursorRect.size.height))")

        // 6. Resolve cursor rect BEFORE the text-unchanged guard.
        // Critical: even when text hasn't changed, the cursor may have moved
        // (arrow keys, mouse click). We need to:
        //   a) detect movement and invalidate the suggestion (§6),
        //   b) keep lastCursorRect up to date for when a new suggestion arrives.
        resolveCursorRect(from: context)
        let cursorRectChanged = lastSeenCursorRect != .zero
            && lastSeenCursorRect != lastCursorRect
        lastSeenCursorRect = lastCursorRect

        // 7. Check for meaningful change
        guard context.prefix != lastTextBeforeCursor || context.suffix != lastTextAfterCursor else {
            // Per §6: cursor moved without text change → invalidate prediction immediately.
            // This covers arrow keys, mouse clicks, and selection changes picked up
            // by the idle poll (500ms). The event tap handles keyDown instantly.
            if cursorRectChanged && hasActiveContext && !controller.suggestion.isEmpty {
                log.debug("Cursor moved without text change — invalidating suggestion")
                lastValidCursorRect = .zero
                DispatchQueue.main.async { [weak self] in
                    self?.controller.suggestion = ""
                }
            }
            log.debug("Text unchanged — skipping prediction")
            return
        }

        lastTextBeforeCursor = context.prefix
        lastTextAfterCursor = context.suffix
        hasActiveContext = true

        // 8. Feed into prediction engine
        log.debug("Feeding EditorState to controller (prefix length=\(context.prefix.count))")
        controller.editorStateChanged(EditorState(
            textBeforeCursor: context.prefix,
            textAfterCursor: context.suffix
        ))
    }

    /// Resolves the best cursor rect to use for overlay positioning, using
    /// a 4-tier fallback chain when AX cursor rect extraction fails.
    private func resolveCursorRect(from context: TextContext) {
        let axCursorRect = context.cursorRect

        if axCursorRect.width >= 0, axCursorRect.height > 0 {
            // Tier 1: Valid rect from AX — cache and use
            log.debug("Cursor rect: Tier 1 (AX embedded) — (\(axCursorRect.origin.x), \(axCursorRect.origin.y), \(axCursorRect.size.width)x\(axCursorRect.size.height))")
            lastCursorRect = axCursorRect
            lastValidCursorRect = axCursorRect
        } else if let independentRect = accessibility.getCursorRect(),
                  independentRect.width >= 0, independentRect.height > 0 {
            // Tier 2: Independent fetch succeeded
            log.debug("Cursor rect: Tier 2 (AX independent retry) — (\(independentRect.origin.x), \(independentRect.origin.y), \(independentRect.size.width)x\(independentRect.size.height))")
            lastCursorRect = independentRect
            lastValidCursorRect = independentRect
        } else if lastValidCursorRect != .zero {
            // Tier 3: Use last known valid position
            log.debug("Cursor rect: Tier 3 (cached) — (\(self.lastValidCursorRect.origin.x), \(self.lastValidCursorRect.origin.y), \(self.lastValidCursorRect.size.width)x\(self.lastValidCursorRect.size.height))")
            lastCursorRect = self.lastValidCursorRect
        } else {
            // Tier 4: Compute from focused window
            let computed = computeFallbackCursorRect()
            log.debug("Cursor rect: Tier 4 (computed from window) — (\(computed.origin.x), \(computed.origin.y), \(computed.size.width)x\(computed.size.height))")
            lastCursorRect = computed
        }
    }

    /// Computes a reasonable fallback cursor rect when AX cursor resolution fails.
    /// Positions the overlay roughly in the center-left area of the focused window,
    /// which is where text input typically appears.
    private func computeFallbackCursorRect() -> CGRect {
        guard let appBundleID = accessibility.focusedAppBundleID() else {
            return CGRect(x: 100, y: 200, width: 2, height: 16)
        }

        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == appBundleID {
            let pidRef = AXUIElementCreateApplication(app.processIdentifier)
            var windowValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                pidRef,
                kAXMainWindowAttribute as CFString,
                &windowValue
            )
            if result == .success, let windowElement = windowValue {
                var positionValue: CFTypeRef?
                var sizeValue: CFTypeRef?
                let posResult = AXUIElementCopyAttributeValue(
                    windowElement as! AXUIElement,
                    kAXPositionAttribute as CFString,
                    &positionValue
                )
                let sizeResult = AXUIElementCopyAttributeValue(
                    windowElement as! AXUIElement,
                    kAXSizeAttribute as CFString,
                    &sizeValue
                )

                if posResult == .success, sizeResult == .success,
                   let posValue = positionValue, let szValue = sizeValue {
                    var position = CGPoint.zero
                    var size = CGSize.zero
                    if AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
                       AXValueGetValue(szValue as! AXValue, .cgSize, &size) {
                        let caretX = position.x + size.width * 0.2
                        let caretY = position.y + size.height * 0.3
                        log.debug("Computed fallback cursorRect: (\(caretX), \(caretY)) for bundle \(appBundleID)")
                        return CGRect(x: caretX, y: caretY, width: 2, height: 16)
                    }
                }
            }
        }

        if let screen = NSScreen.main {
            let frame = screen.frame
            log.debug("Fallback cursorRect (screen-based): (\(frame.midX), \(frame.midY))")
            return CGRect(
                x: frame.midX - 200,
                y: frame.midY + 100,
                width: 2,
                height: 16
            )
        }

        return CGRect(x: 100, y: 200, width: 2, height: 16)
    }

    // MARK: — App Gating

    private func shouldProcessCurrentApp() -> Bool {
        guard let bundleID = accessibility.focusedAppBundleID() else {
            handleNoFocus()
            return false
        }

        focusedAppBundleID = bundleID
        focusedAppName = appName(for: bundleID)

        if bundleID == "app.keybreeze.Keybreeze" {
            // log.debug("Current app is Keybreeze — ignoring")
            return false
        }

        if excludedBundleIDs.contains(bundleID) {
            log.debug("Keydown in excluded app '\(bundleID)' — skipping")
            setPaused(reason: "Excluded app")
            return false
        }

        if manualOnlyBundleIDs.contains(bundleID) && !predictInManualOnly {
            log.debug("Keydown in manual-only app '\(bundleID)' — skipping")
            setPaused(reason: "Manual-only app")
            return false
        }

        return shouldProcessApp(bundleID)
    }

    private func shouldProcessApp(_ bundleID: String) -> Bool {
        if bundleID == "app.keybreeze.Keybreeze" {
            setPaused(reason: "Keybreeze focused")
            return false
        }

        if excludedBundleIDs.contains(bundleID) {
            setPaused(reason: "Excluded app")
            return false
        }

        if manualOnlyBundleIDs.contains(bundleID) && !predictInManualOnly {
            setPaused(reason: "Manual-only app")
            return false
        }

        return true
    }

    // MARK: Helpers

    private func handleNoFocus() {
        focusedAppBundleID = nil
        focusedAppName = nil
        lastAppBundleID = nil
        if hasActiveContext {
            log.debug("No focus — clearing suggestion and hiding overlay")
            DispatchQueue.main.async { [weak self] in
                self?.controller.suggestion = ""
                self?.overlay.hide()
            }
            hasActiveContext = false
        }
        lastTextBeforeCursor = ""
        lastTextAfterCursor = ""
        lastCursorRect = .zero
        lastValidCursorRect = .zero
        setPaused(reason: "No app focused")
    }

    private func setPaused(reason: String) {
        isPaused = true
        pauseReason = reason
    }

    private func clearPaused() {
        isPaused = false
        pauseReason = ""
    }

    /// Resolve a bundle ID to a human-readable app name using NSWorkspace.
    private func appName(for bundleID: String) -> String? {
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == bundleID {
                return app.localizedName ?? bundleID
            }
        }
        return bundleID
    }

    deinit {
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        pollTask?.cancel()
        debounceTask?.cancel()
        Task { @MainActor in
            overlay.hide()
        }
        cancellables.removeAll()
    }
}