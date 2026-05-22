import Foundation
import OSLog
import AppKit

/// Bridges the Accessibility API text context into the CompletionController
/// for system-wide prediction.
///
/// Uses two complementary trigger mechanisms (inspired by Ghost Type):
/// 1. CGEventTap — captures keyDown events system-wide for instant trigger
/// 2. Idle safety poll — slower timer (500ms) catches paste/undo/mouse changes
///
/// Respects app gating (excluded/manual-only), IME composition safety,
/// and avoids processing Keybreeze's own windows (Typing Lab handles its own).
@MainActor
final class SystemWidePredictor {
    private let log = Logger(subsystem: "app.keybreeze", category: "system-wide")

    // MARK: Dependencies

    private let controller: CompletionController
    private let accessibility: AccessibilityManager
    private let inputMonitor: InputSourceMonitor

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

    /// The last app bundle ID we saw — used to detect app switches.
    private var lastAppBundleID: String?

    /// Whether we currently have an active text context (text field focused).
    private var hasActiveContext: Bool = false

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
        guard pollTask == nil else { return }
        log.info("System-wide predictor started")
        resetState()

        // 1. Start CGEventTap for instant keystroke-based triggering.
        //    This is the primary trigger — captures keyDown events system-wide,
        //    debounces, then reads AX context and feeds the controller.
        installEventTap()

        // 2. Start idle safety poll (500ms) to catch non-keyboard changes
        //    like paste, undo, mouse clicks, auto-correct, etc.
        pollTask = Task { [weak self] in
            await self?.idlePollLoop()
        }
    }

    func stop() {
        // Remove event tap
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        // Cancel tasks
        pollTask?.cancel()
        pollTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        resetState()
        log.info("System-wide predictor stopped")
    }

    private func resetState() {
        lastTextBeforeCursor = ""
        lastTextAfterCursor = ""
        lastAppBundleID = nil
        hasActiveContext = false
        isPaused = false
        pauseReason = ""
        focusedAppBundleID = nil
        focusedAppName = nil
    }

    // MARK: — Event Tap (Primary Trigger)

    /// Installs a CGEventTap that captures keyDown events system-wide.
    /// On each keystroke, we start a debounce timer, then read AX context
    /// and feed the controller.
    ///
    /// This is inspired by Ghost Type's GlobalKeyMonitor pattern — it avoids
    /// polling overhead and gives instant response to keystrokes.
    private func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard type == .keyDown,
                  let refcon else {
                return Unmanaged.passUnretained(event)
            }

            // Re-bridge self from the refcon
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
            log.warning("Failed to create event tap — predictions will rely on idle polling only")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        log.info("Event tap installed for system-wide keystroke capture")
    }

    /// Called from the CGEventTap callback on every keyDown event.
    /// Runs on the main actor via the event tap's run loop.
    private func handleKeyDown() {
        // Quick block checks before debouncing
        guard shouldProcessCurrentApp() else { return }

        // Debounce: cancel previous, schedule new
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                // 40ms debounce after last keystroke (matches CompletionController's 45ms)
                try await Task.sleep(for: .milliseconds(40))
                await self?.readAndPredict()
            } catch {
                // Cancelled
            }
        }
    }

    // MARK: — Idle Poll (Safety Net)

    /// Polls every 500ms to catch non-keyboard text changes (paste, undo, mouse clicks).
    /// Returns early if no app/text field is focused or nothing changed.
    private func idlePollLoop() async {
        let idleInterval: UInt64 = 500_000_000  // 500ms
        while !Task.isCancelled {
            // Only poll if we're not in the middle of a keystroke debounce
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
            handleNoFocus()
            return
        }

        focusedAppBundleID = bundleID
        focusedAppName = appName(for: bundleID)

        // 2. Gating checks
        guard shouldProcessApp(bundleID) else {
            // If we switched away from a text field, clear the suggestion
            if bundleID != lastAppBundleID {
                controller.suggestion = ""
                hasActiveContext = false
            }
            return
        }

        // 3. IME safety
        guard inputMonitor.isASCIICompatible else {
            setPaused(reason: "IME composition active")
            return
        }

        clearPaused()

        // 4. Detect app switch
        if bundleID != lastAppBundleID {
            lastAppBundleID = bundleID
            lastTextBeforeCursor = ""
            lastTextAfterCursor = ""
            hasActiveContext = false
        }

        // 5. Read text context
        guard let context = accessibility.getTextContext(maxChars: 800) else {
            if hasActiveContext {
                controller.suggestion = ""
                hasActiveContext = false
            }
            return
        }

        // 6. Check for meaningful change
        guard context.prefix != lastTextBeforeCursor || context.suffix != lastTextAfterCursor else {
            return // Nothing changed
        }

        lastTextBeforeCursor = context.prefix
        lastTextAfterCursor = context.suffix
        hasActiveContext = true

        // 7. Feed into prediction engine
        controller.editorStateChanged(EditorState(
            textBeforeCursor: context.prefix,
            textAfterCursor: context.suffix
        ))
    }

    // MARK: — App Gating

    /// Quick check that runs in the hot path (keyDown callback).
    /// Updates paused state but doesn't clear suggestions.
    private func shouldProcessCurrentApp() -> Bool {
        guard let bundleID = accessibility.focusedAppBundleID() else {
            handleNoFocus()
            return false
        }

        focusedAppBundleID = bundleID
        focusedAppName = appName(for: bundleID)

        return shouldProcessApp(bundleID)
    }

    private func shouldProcessApp(_ bundleID: String) -> Bool {
        // Skip Keybreeze itself
        if bundleID == "app.keybreeze.Keybreeze" {
            setPaused(reason: "Keybreeze focused")
            return false
        }

        // Check excluded
        if excludedBundleIDs.contains(bundleID) {
            setPaused(reason: "Excluded app")
            return false
        }

        // Check manual-only
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
            controller.suggestion = ""
            hasActiveContext = false
        }
        lastTextBeforeCursor = ""
        lastTextAfterCursor = ""
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
    }
}
