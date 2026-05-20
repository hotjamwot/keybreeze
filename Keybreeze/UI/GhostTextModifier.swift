import SwiftUI

struct GhostTextModifier: ViewModifier {
    @Binding var draftText: String
    @Binding var suggestion: String
    @Binding var correctionState: CorrectionState?
    @Binding var isSchedulerActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSchedulerActive {
            // Overlay ghost text on top of the text field
            content
                .overlay(
                    ghostTextView
                        .padding(.leading, -5) // Adjust alignment
                        .padding(.top, -5) // Adjust alignment
                        .opacity(0.6)
                        .blendMode(.difference)
                )
                .onChange(of: draftText) { _ in
                    // Ensure ghost text stays in sync with draftText
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private var ghostTextView: some View {
        // Build the ghost text view
        let ghostText = buildGhostText()
        
        if !ghostText.isEmpty {
            Text(ghostText)
                .font(.body)
                .foregroundColor(correctionState != nil ? Color.green : Color.gray)
                .lineLimit(3...10)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 5) // Compensate for text field padding
                .padding(.top, 5) // Compensate for text field padding
        }
    }

    private func buildGhostText() -> String {
        // If there's a correction, show the correction
        if let correction = correctionState {
            // Show the correction in green
            return correction.suggestedCorrection
        }
        
        // Otherwise, show the suggestion
        if !suggestion.isEmpty {
            return suggestion
        }
        
        return ""
    }
}

extension View {
    func ghostText(draftText: Binding<String>, suggestion: Binding<String>, correctionState: Binding<CorrectionState?>, isSchedulerActive: Binding<Bool>) -> some View {
        self.modifier(GhostTextModifier(draftText: draftText, suggestion: suggestion, correctionState: correctionState, isSchedulerActive: isSchedulerActive))
    }
}
