import Foundation
import ApplicationServices

/// Commits accepted suggestions back into the host app by synthesizing Unicode keyboard events.
/// Uses a queue-based approach with millisecond delays to prevent keystroke drops in heavy
/// editors like VSCode and Electron-based apps.
///
/// Ported from Cotabby's SuggestionInserter with queue-based timing for stability.
@MainActor
final class SuggestionInserter {
    private let suppressionController: InputSuppressionController

    private(set) var lastErrorMessage: String?

    init(suppressionController: InputSuppressionController) {
        self.suppressionController = suppressionController
    }

    /// Posts a single Unicode keydown/keyup pair for the accepted suggestion.
    /// Returns false if the suggestion was empty or event creation failed.
    func insert(_ suggestion: String) -> Bool {
        let normalized = suggestion.replacingOccurrences(of: "\r", with: "")
        guard !normalized.isEmpty else {
            lastErrorMessage = "Suggestion was empty."
            return false
        }

        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            lastErrorMessage = "Unable to create a synthetic keyboard event."
            return false
        }

        let utf16CodeUnits = Array(normalized.utf16)
        suppressionController.registerSyntheticInsertion(expectedKeyDownCount: 1)
        keyDownEvent.keyboardSetUnicodeString(stringLength: utf16CodeUnits.count, unicodeString: utf16CodeUnits)
        keyUpEvent.keyboardSetUnicodeString(stringLength: utf16CodeUnits.count, unicodeString: utf16CodeUnits)
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
        lastErrorMessage = nil
        return true
    }

    /// Inserts text character-by-character with millisecond delays between each character.
    /// This is more reliable for rich editors than inserting the entire string at once,
    /// as it gives the host app time to process each keystroke.
    func insertCharacterByCharacter(_ text: String, interCharacterDelay: UInt64 = 5_000_000) async {
        let normalized = text.replacingOccurrences(of: "\r", with: "")
        guard !normalized.isEmpty else { return }

        suppressionController.registerSyntheticInsertion(expectedKeyDownCount: normalized.count)

        for character in normalized {
            guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                return
            }

            let chars = Array(String(character).utf16)
            chars.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                keyDownEvent.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                keyUpEvent.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            }

            keyDownEvent.post(tap: .cghidEventTap)
            keyUpEvent.post(tap: .cghidEventTap)

            if interCharacterDelay > 0 {
                try? await Task.sleep(nanoseconds: interCharacterDelay)
            }
        }
    }
}