import Foundation

/// Represents the state of the text editor at a given moment.
struct EditorState {
    /// Text before the cursor (what the user has typed so far).
    var textBeforeCursor: String
    /// Text after the cursor (if any, usually empty for our use case).
    var textAfterCursor: String
    /// Current cursor position (character index).
    var cursorPosition: Int
    /// Selection range (start and end character indices), or nil if no selection.
    var selection: NSRange?
    /// Whether the user is currently in a multi-line context (e.g., after a newline).
    var isMultiLine: Bool
    /// The current sentence start position (character index), or nil if not in a sentence.
    var sentenceStart: Int?
    /// The current paragraph start position (character index), or nil if not in a paragraph.
    var paragraphStart: Int?

    init(textBeforeCursor: String, textAfterCursor: String, cursorPosition: Int = 0, selection: NSRange? = nil, isMultiLine: Bool = false, sentenceStart: Int? = nil, paragraphStart: Int? = nil) {
        self.textBeforeCursor = textBeforeCursor
        self.textAfterCursor = textAfterCursor
        self.cursorPosition = cursorPosition
        self.selection = selection
        self.isMultiLine = isMultiLine
        self.sentenceStart = sentenceStart
        self.paragraphStart = paragraphStart
    }

    /// Calculates sentence start based on the text before the cursor.
    /// A sentence typically ends with a period, question mark, or exclamation mark followed by a space.
    var calculatedSentenceStart: Int? {
        guard !textBeforeCursor.isEmpty else { return nil }

        // Find the last sentence delimiter (period, question mark, exclamation mark) that is followed by a space or end of text
        let delimiters = CharacterSet(charactersIn: ".?!")
        guard let sentenceRange = Range(
            NSRange(location: 0, length: textBeforeCursor.utf16.count),
            in: textBeforeCursor
        ) else { return nil }

        var lastDelimiterIndex: Int?

        textBeforeCursor.enumerateSubstrings(
            in: sentenceRange,
            options: .byComposedCharacterSequences
        ) { substring, substringRange, _, _ in
            guard let substring = substring,
                  let lastChar = substring.unicodeScalars.last,
                  delimiters.contains(lastChar) else { return }

            // Check if this delimiter is followed by a space or end of text
            let nextIndex = substringRange.upperBound
            if nextIndex >= textBeforeCursor.endIndex
                || textBeforeCursor[nextIndex...].hasPrefix(" ")
            {
                lastDelimiterIndex = substringRange.lowerBound.utf16Offset(
                    in: textBeforeCursor
                )
            }
        }

        if let delimiterIndex = lastDelimiterIndex {
            // The sentence starts after the delimiter and space
            let sentenceStartIndex = delimiterIndex + 1
            return sentenceStartIndex
        } else {
            // No sentence delimiter found, return the start of the text
            return 0
        }
    }

    /// Calculates paragraph start based on the text before the cursor.
    /// A paragraph typically starts after two newlines or at the beginning of the text.
    var calculatedParagraphStart: Int? {
        guard !textBeforeCursor.isEmpty else { return nil }

        // Find the last double newline
        let paragraphs = textBeforeCursor.components(separatedBy: "\n\n")
        if let lastParagraph = paragraphs.last, !lastParagraph.isEmpty {
            // Find the start of the last paragraph
            var paragraphStart = 0
            if paragraphs.count > 1 {
                // Sum the lengths of previous paragraphs plus two newlines for each
                for i in 0..<paragraphs.count-1 {
                    paragraphStart += paragraphs[i].count + 2
                }
            }
            return paragraphStart
        } else {
            return 0
        }
    }

    /// Determines if the text is multi-line (contains newlines).
    var calculatedIsMultiLine: Bool {
        textBeforeCursor.contains("\n")
    }
}
