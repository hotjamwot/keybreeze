import SwiftUI

/// Single shared source of truth for ghost text visual constants.
/// Both `GhostTextModifier` (playground) and `InlineGhostTextView` (overlay)
/// reference these values so the playground is a pixel-perfect test bed
/// for the system-wide appearance.
enum GhostTextStyle {
    /// Opacity of ghost suggestion text (grey/translucent).
    static let suggestionOpacity: Double = 0.45

    /// Opacity of the committed text invisibility layer (fully transparent).
    static let committedTextOpacity: Double = 0

    /// Font for ghost text — matches the system body font.
    static let font: Font = .body

    /// Maximum number of lines the ghost text can occupy before truncation.
    static let lineLimit: Int = 10

    /// Leading padding to align ghost overlay with the TextField content inset.
    /// Matches typical TextField padding (12) + stroke border (1).
    static let leadingPadding: CGFloat = 13

    /// Trailing padding so text wraps at the same width as the TextField.
    static let trailingPadding: CGFloat = 13

    /// Top padding to align ghost overlay with the TextField content inset.
    static let topPadding: CGFloat = 13

    /// Correction mode: opacity of the strikethrough original word.
    static let correctionOriginalOpacity: Double = 0.6

    /// Correction mode: colour of the strikethrough line.
    static let correctionStrikethroughColor: Color = .red

    /// Correction mode: colour of the suggested replacement.
    static let correctionSuggestionColor: Color = .green

    /// Overlay window font size (CGFloat version for NSFont).
    static let overlayFontSize: CGFloat = 14

    /// Overlay window ghost opacity.
    static let overlayGhostOpacity: CGFloat = 0.45

    /// Width limit for overlay content (prevents spanning the whole screen).
    static let overlayMaxWidth: CGFloat = 600
}