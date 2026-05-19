import SwiftUI

/// Runtime model parameter controls for rapid experimentation with typing feel.
struct ParameterControlsView: View {
    @EnvironmentObject private var predictionSession: PredictionSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Backend selector
            HStack {
                Text("Backend:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { predictionSession.appState.selectedBackend },
                    set: { predictionSession.appState.selectedBackend = $0 }
                )) {
                    ForEach(LLMBackend.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.bottom, 8)

            Label("Runtime Model Parameters", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))

            Group {
                parameterSlider(
                    label: "Temperature",
                    value: $predictionSession.temperature,
                    range: 0.0...1.5,
                    display: String(format: "%.2f", predictionSession.temperature)
                )
                parameterSlider(
                    label: "Top-P",
                    value: $predictionSession.topP,
                    range: 0.0...1.0,
                    display: String(format: "%.2f", predictionSession.topP)
                )
                parameterSlider(
                    label: "Repeat Penalty",
                    value: $predictionSession.repeatPenalty,
                    range: 0.5...2.0,
                    display: String(format: "%.2f", predictionSession.repeatPenalty)
                )
                parameterSlider(
                    label: "Confidence Threshold",
                    value: $predictionSession.confidenceThreshold,
                    range: 0.0...1.0,
                    display: String(format: "%.2f", predictionSession.confidenceThreshold)
                )
                parameterSlider(
                    label: "Verbosity Bias",
                    value: $predictionSession.verbosityBias,
                    range: 0.0...1.0,
                    display: String(format: "%.2f", predictionSession.verbosityBias)
                )
                parameterSlider(
                    label: "Continuation Bias",
                    value: $predictionSession.continuationBias,
                    range: 0.0...1.0,
                    display: String(format: "%.2f", predictionSession.continuationBias)
                )
                parameterSlider(
                    label: "Instruction Strictness",
                    value: $predictionSession.instructionStrictness,
                    range: 0.0...1.0,
                    display: String(format: "%.2f", predictionSession.instructionStrictness)
                )
            }

            // Max words picker
            HStack {
                Text("Max Words:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $predictionSession.tuningMaxWords) {
                    Text("Model default").tag(0)
                    ForEach(2...20, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func parameterSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(label):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: value, in: range)
        }
    }
}
