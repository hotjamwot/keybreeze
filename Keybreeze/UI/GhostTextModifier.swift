import SwiftUI

/// Displays ghost text (prediction) right after the committed text, at the cursor position.
/// Always uses an overlay to prevent view hierarchy changes that would steal focus.
/// Visual constants are sourced from `GhostTextStyle` for consistency with the overlay.
struct GhostTextModifier: ViewModifier {
    @Binding var draftText: String
    @Binding var suggestion: String
    @Binding var correctionState: CorrectionState?
    @Binding var isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                ghostOverlayContent
                    .allowsHitTesting(false)
                    .padding(.leading, GhostTextStyle.leadingPadding)
                    .padding(.top, GhostTextStyle.topPadding)
                    .padding(.trailing, GhostTextStyle.trailingPadding)
            }
    }

    @ViewBuilder
    private var ghostOverlayContent: some View {
        if isEnabled, let correction = correctionState {
            // Correction: invisible committed text anchors position,
            // then strikethrough original + green suggestion follow
            HStack(spacing: 4) {
                Text(draftText)
                    .font(GhostTextStyle.font)
                    .foregroundColor(.clear)

                Text(correction.originalWord)
                    .font(GhostTextStyle.font)
                    .foregroundColor(.gray.opacity(GhostTextStyle.correctionOriginalOpacity))
                    .strikethrough(true, color: GhostTextStyle.correctionStrikethroughColor)

                Text(correction.suggestedCorrection)
                    .font(GhostTextStyle.font)
                    .foregroundColor(GhostTextStyle.correctionSuggestionColor)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            // Normal ghost text: invisible committed text anchors the position,
            // ghost suggestion flows right after it — even across line wraps.
            (Text(draftText)
                .font(GhostTextStyle.font)
                .foregroundColor(.clear)
            + Text(suggestion)
                .font(GhostTextStyle.font)
                .foregroundColor(.secondary.opacity(isEnabled && !suggestion.isEmpty
                    ? GhostTextStyle.suggestionOpacity : 0))
            )
            .lineLimit(GhostTextStyle.lineLimit)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    func ghostText(draftText: Binding<String>, suggestion: Binding<String>, correctionState: Binding<CorrectionState?>, isEnabled: Binding<Bool>) -> some View {
        self.modifier(GhostTextModifier(draftText: draftText, suggestion: suggestion, correctionState: correctionState, isEnabled: isEnabled))
    }
}