import SwiftUI

/// Runtime model parameter controls for rapid experimentation with typing feel.
/// Grouped into clear sections matching GhostType's clean settings panel approach.
struct ParameterControlsView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel
    @EnvironmentObject private var appState: AppState

    @Binding var showAdvancedSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enable tuning toggle
            Toggle(isOn: $sessionVM.tuningEnabled) {
                Label("Override Model Parameters", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)
            .onChange(of: sessionVM.tuningEnabled) { _, enabled in
                if enabled {
                    sessionVM.syncTuningFromModel()
                }
            }
            .padding(.bottom, 8)

            if sessionVM.tuningEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    // MARK: — Word Caps
                    GroupBox(label: Label("Suggestion Length", systemImage: "text.word.spacing").font(.caption)) {
                        VStack(alignment: .leading, spacing: 8) {
                            // Global max words
                            HStack {
                                Text("Max Words (global):")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $sessionVM.tuningMaxWords) {
                                    Text("Model default").tag(0)
                                    ForEach(2...15, id: \.self) { n in
                                        Text("\(n)").tag(n)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }

                            Divider()

                            // Mid-type word cap
                            modeWordCapPicker(
                                label: "While typing",
                                help: "Words to predict while you're actively typing (fast mode)",
                                value: $sessionVM.midTypeWords
                            )

                            // Pause word cap
                            modeWordCapPicker(
                                label: "On pause",
                                help: "Words to predict when you stop typing for a moment",
                                value: $sessionVM.pauseWords
                            )

                            Text("Set to 0 to use defaults (mid=3, pause=5)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }

                    // MARK: — Sampling Parameters
                    GroupBox(label: Label("Sampling", systemImage: "thermometer").font(.caption)) {
                        VStack(alignment: .leading, spacing: 6) {
                            parameterSlider(
                                label: "Temperature",
                                systemImage: "flame",
                                value: $sessionVM.temperature,
                                range: 0.0...1.5,
                                display: String(format: "%.2f", sessionVM.temperature)
                            )
                            parameterSlider(
                                label: "Top-P",
                                systemImage: "circle.dotted",
                                value: $sessionVM.topP,
                                range: 0.0...1.0,
                                display: String(format: "%.2f", sessionVM.topP)
                            )
                            parameterSlider(
                                label: "Repeat Penalty",
                                systemImage: "repeat",
                                value: $sessionVM.repeatPenalty,
                                range: 0.5...2.0,
                                display: String(format: "%.2f", sessionVM.repeatPenalty)
                            )
                            parameterSlider(
                                label: "Confidence Threshold",
                                systemImage: "checkmark.shield",
                                value: $sessionVM.confidenceThreshold,
                                range: 0.0...1.0,
                                display: String(format: "%.2f", sessionVM.confidenceThreshold)
                            )
                        }
                        .padding(.vertical, 4)
                    }

                    // MARK: — Behaviour Tuning
                    GroupBox(label: Label("Behaviour", systemImage: "brain.head.profile").font(.caption)) {
                        VStack(alignment: .leading, spacing: 6) {
                            parameterSlider(
                                label: "Verbosity Bias",
                                systemImage: "text.bubble",
                                value: $sessionVM.verbosityBias,
                                range: 0.0...1.0,
                                display: String(format: "%.2f", sessionVM.verbosityBias)
                            )
                            parameterSlider(
                                label: "Continuation Bias",
                                systemImage: "arrow.forward",
                                value: $sessionVM.continuationBias,
                                range: 0.0...1.0,
                                display: String(format: "%.2f", sessionVM.continuationBias)
                            )
                            parameterSlider(
                                label: "Instruction Strictness",
                                systemImage: "list.bullet.clipboard",
                                value: $sessionVM.instructionStrictness,
                                range: 0.0...1.0,
                                display: String(format: "%.2f", sessionVM.instructionStrictness)
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Enable parameter overrides to fine-tune the model for your typing style.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).cornerRadius(10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Component Helpers

    private func modeWordCapPicker(label: String, help: String, value: Binding<Int>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(help)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Picker("", selection: value) {
                Text("Default").tag(0)
                ForEach(1...PredictionMode.maxWordsLimit, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 80)
        }
    }

    private func parameterSlider(label: String, systemImage: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                Text("\(label):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }
}