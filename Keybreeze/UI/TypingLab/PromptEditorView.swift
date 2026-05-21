import SwiftUI

/// Runtime prompt editing — modify system and continuation prompts without rebuilding.
struct PromptEditorView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel

    @State private var showSystemPrompt = true
    @State private var showStyleNudge = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Runtime Prompt Editing", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))

            Text("Edits apply to the next prediction immediately. No rebuild required.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // System prompt
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("System Prompt Override")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Toggle("Edit", isOn: $showSystemPrompt)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if showSystemPrompt {
                    TextEditor(text: $sessionVM.customSystemPrompt)
                        .font(.caption.monospaced())
                        .frame(minHeight: 60, maxHeight: 120)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                        .overlay(alignment: .topLeading) {
                            if sessionVM.customSystemPrompt.isEmpty {
                                Text("Leave empty to use default system prompt…")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            // Style nudge
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Style Nudge")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Toggle("Edit", isOn: $showStyleNudge)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if showStyleNudge {
                    TextEditor(text: $sessionVM.styleNudge)
                        .font(.caption.monospaced())
                        .frame(minHeight: 60, maxHeight: 120)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                        .overlay(alignment: .topLeading) {
                            if sessionVM.styleNudge.isEmpty {
                                Text("Leave empty for default style…")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(8)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            // Apply note
            Text("Prompts with content will override PromptBuilder defaults. Empty = use built-in.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if sessionVM.customSystemPrompt.isEmpty {
                sessionVM.customSystemPrompt = PromptBuilder.defaultSystemPrompt
            }
        }
    }
}