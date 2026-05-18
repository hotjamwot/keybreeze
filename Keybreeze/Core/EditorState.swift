import Foundation

/// Snapshot of editor text around the caret. Phase 1 uses a mock; later this maps from Obsidian/accessibility.
struct EditorState: Equatable, Sendable {
    var textBeforeCursor: String
    var textAfterCursor: String

    init(textBeforeCursor: String, textAfterCursor: String = "") {
        self.textBeforeCursor = textBeforeCursor
        self.textAfterCursor = textAfterCursor
    }
}
