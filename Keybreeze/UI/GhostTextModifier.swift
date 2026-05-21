import SwiftUI

/// Displays ghost text (prediction) right after the committed text, at the cursor position.
/// Always uses an overlay to prevent view hierarchy changes that would steal focus.
struct GhostTextModifier: ViewModifier {
    @Binding var draftText: String
    @Binding var suggestion: String
    @Binding var correctionState: CorrectionState?
    @Binding var isSchedulerActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                ghostOverlayContent
                    .allowsHitTesting(false)
                    .padding(.leading, 9)  // Match NSTextField inner padding
                    .padding(.top, 10)     // Match NSTextField inner padding vertical
            }
    }

    @ViewBuilder
    private var ghostOverlayContent: some View {
        if isSchedulerActive, let correction = correctionState {
            // Correction: invisible committed text anchors position,
            // then strikethrough original + green suggestion follow
            HStack(spacing: 4) {
                Text(draftText)
                    .font(.body)
                    .foregroundColor(.clear)

                Text(correction.originalWord)
                    .font(.body)
                    .foregroundColor(.gray.opacity(0.6))
                    .strikethrough(true, color: .red)

                Text(correction.suggestedCorrection)
                    .font(.body)
                    .foregroundColor(.green)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            // Normal ghost text: invisible committed text anchors the position,
            // ghost suggestion flows right after it — even across line wraps.
            (Text(draftText)
                .font(.body)
                .foregroundColor(.clear)
            + Text(suggestion)
                .font(.body)
                .foregroundColor(.secondary.opacity(isSchedulerActive && !suggestion.isEmpty ? 0.45 : 0))
            )
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    func ghostText(draftText: Binding<String>, suggestion: Binding<String>, correctionState: Binding<CorrectionState?>, isSchedulerActive: Binding<Bool>) -> some View {
        self.modifier(GhostTextModifier(draftText: draftText, suggestion: suggestion, correctionState: correctionState, isSchedulerActive: isSchedulerActive))
    }
}