import Carbon
import Foundation

/// Tracks the current keyboard input source so the prediction engine can
/// suspend auto-trigger while a non-ASCII IME (Japanese, Chinese, Korean, etc.)
/// is composing. We treat the source as "safe" only when it is a plain
/// keyboard layout AND advertises ASCII capability.
///
/// Ported from GhostType with minimal changes.
final class InputSourceMonitor {
    static let shared = InputSourceMonitor()

    private(set) var isASCIICompatible: Bool = true
    private(set) var currentSourceID: String = ""

    private var observer: CFNotificationCenter?

    private init() {
        refresh()
        startObserving()
    }

    deinit {
        stopObserving()
    }

    private func startObserving() {
        let center = CFNotificationCenterGetDistributedCenter()
        observer = center

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            opaque,
            { _, opaque, _, _, _ in
                guard let opaque = opaque else { return }
                let monitor = Unmanaged<InputSourceMonitor>.fromOpaque(opaque).takeUnretainedValue()
                DispatchQueue.main.async { monitor.refresh() }
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }

    private func stopObserving() {
        if let center = observer {
            let opaque = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterRemoveEveryObserver(center, opaque)
        }
        observer = nil
    }

    func refresh() {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            isASCIICompatible = true
            currentSourceID = ""
            return
        }

        currentSourceID = stringProperty(source, key: kTISPropertyInputSourceID) ?? ""
        let isASCIICapable = boolProperty(source, key: kTISPropertyInputSourceIsASCIICapable)

        // Safe = any input source that advertises ASCII capability.
        // Japanese "Hiragana", Chinese "Pinyin", Korean "2-Set" etc. all set
        // isASCIICapable = false, so they are correctly filtered out.
        // We check isASCIICapable directly instead of matching on type string,
        // because macOS Sonoma/Sequoia can return different type identifiers
        // for the same "ABC" keyboard layout depending on system configuration.
        isASCIICompatible = isASCIICapable
    }

    private func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }
}