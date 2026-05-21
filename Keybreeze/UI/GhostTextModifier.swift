import SwiftUI

/// Displays ghost text (prediction) as a grey, translucent overlay right after the committed text.
/// No blend modes, no inverted colors — just a simple foregroundColor opacity overlay.
struct GhostTextModifier: ViewModifier {
    @Binding var draftText: String
    @Binding var suggestion: String
    @Binding var correctionState: CorrectionState?
    @Binding var isSchedulerActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSchedulerActive && (!suggestion.isEmpty || correctionState != nil) {
            content
                .overlay(alignment: .topLeading) {
                    ghostTextOverlay
                        .allowsHitTesting(false)
                        .padding(.leading, 9)  // Match NSTextField inner padding
                        .padding(.top, 10)     // Match NSTextField inner padding vertical
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private var ghostTextOverlay: some View {
        if let correction = correctionState {
            // Correction state: strikethrough original, green suggestion
            HStack(spacing: 4) {
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
            // Normal ghost text: grey + translucent
            Text(suggestion)
                .font(.body)
                .foregroundColor(.secondary.opacity(0.45))
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