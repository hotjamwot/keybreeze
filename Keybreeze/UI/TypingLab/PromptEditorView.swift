import SwiftUI

/// Runtime prompt editing — modify system and continuation prompts without rebuilding.
struct PromptEditorView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel

    @State private var showSystemPrompt = true
    @State private var showStyleNudge = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Runtime Prompt Editing", systemImage: "doc.text.magnifyingglass")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Edits apply to the next prediction immediately. No rebuild required.")
                .font(.body)
                .foregroundStyle(.secondary)
                .settingsDescription()

            // System prompt
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("System Prompt Override")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Toggle("Edit", isOn: $showSystemPrompt)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if showSystemPrompt {
                    TextEditor(text: $sessionVM.customSystemPrompt)
                        .font(.body.monospaced())
                        .frame(minHeight: 80, maxHeight: 150)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor).opacity(0.5))
                        )
                        .overlay(alignment: .topLeading) {
                            if sessionVM.customSystemPrompt.isEmpty {
                                Text("Leave empty to use default system prompt…")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(10)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            // Style nudge
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Style Nudge")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Toggle("Edit", isOn: $showStyleNudge)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if showStyleNudge {
                    TextEditor(text: $sessionVM.styleNudge)
                        .font(.body.monospaced())
                        .frame(minHeight: 80, maxHeight: 150)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor).opacity(0.5))
                        )
                        .overlay(alignment: .topLeading) {
                            if sessionVM.styleNudge.isEmpty {
                                Text("Leave empty for default style…")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(10)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            // Apply note
            Text("Prompts with content will override PromptBuilder defaults. Empty = use built-in.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .settingsDescription()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
        .onAppear {
            if sessionVM.customSystemPrompt.isEmpty {
                sessionVM.customSystemPrompt = PromptBuilder.defaultSystemPrompt
            }
        }
    }
}