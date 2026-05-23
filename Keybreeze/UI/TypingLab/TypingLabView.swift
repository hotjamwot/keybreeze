import SwiftUI

struct TypingLabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionVM: SessionViewModel
    
    @State private var showDiagnostics = true
    @State private var showParameters = false
    @State private var showPromptEditor = false
    @State private var showAdvancedSettings = false
    
    var body: some View {
        Form {
            Section {
                typingPlaygroundSection
            } header: {
                HStack {
                    Text("Typing Playground")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    if sessionVM.isSchedulerActive {
                        Circle()
                            .fill(Color(NSColor.green))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            
            Section {
                presetSection
            } header: {
                Text("Behaviour")
            }
            
            Section {
                controlPanelToggles
            } header: {
                Text("Control Panels")
            }
            
            if showDiagnostics {
                Section {
                    DiagnosticsPanelView()
                        .environmentObject(appState)
                        .environmentObject(sessionVM)
                } header: {
                    Text("Diagnostics")
                }
            }
            
            if showParameters {
                Section {
                    parameterControlsContent
                        .padding(.vertical, 12)
                } header: {
                    Text("Parameter Controls")
                }
            }
            
            if showPromptEditor {
                Section {
                    promptEditorContent
                } header: {
                    Text("Prompt Editor")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Subviews
    
    private var typingPlaygroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if sessionVM.draftText.isEmpty {
                    Text("Start typing to test predictions…")
                        .font(.body)
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                
                TextField("", text: $sessionVM.draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(3...10)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .strokeBorder(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                    )
                    .ghostText(
                        draftText: $sessionVM.draftText,
                        suggestion: $sessionVM.suggestion,
                        correctionState: .constant(nil),
                        isSchedulerActive: $sessionVM.isSchedulerActive
                    )
                    .onChange(of: sessionVM.draftText) { _, _ in
                        sessionVM.draftTextChanged()
                    }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var presetSection: some View {
        Picker("Preset", selection: $sessionVM.aggressionPreset) {
            ForEach(AggressionPreset.allCases, id: \.self) { preset in
                Text(preset.rawValue).tag(preset)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var controlPanelToggles: some View {
        HStack(spacing: 16) {
            panelToggle(label: "Diagnostics", isOn: $showDiagnostics, icon: "chart.bar")
            panelToggle(label: "Parameters", isOn: $showParameters, icon: "slider.horizontal.3")
            panelToggle(label: "Prompts", isOn: $showPromptEditor, icon: "doc.text")
        }
        .padding(.vertical, 6)
    }
    
    private func panelToggle(label: String, isOn: Binding<Bool>, icon: String) -> some View {
        Toggle(isOn: isOn) {
            Label(label, systemImage: icon)
                .font(.subheadline)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
    
    private var parameterControlsContent: some View {
        VStack(spacing: 16) {
            Toggle(isOn: $sessionVM.tuningEnabled) {
                HStack(spacing: 4) {
                    Text("Override Model Parameters")
                }
            }
            .toggleStyle(.switch)
            
            if sessionVM.tuningEnabled {
                VStack(spacing: 12) {
                    parameterSlider(label: "Temperature", value: $sessionVM.temperature, range: 0.0...1.5)
                    parameterSlider(label: "Top-P", value: $sessionVM.topP, range: 0.0...1.0)
                    parameterSlider(label: "Repeat Penalty", value: $sessionVM.repeatPenalty, range: 0.5...2.0)
                }
                .padding(.top, 8)
                .padding(.leading, 4)
            }
        }
    }
    
    private var promptEditorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("System Prompt")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextEditor(text: Binding(
                    get: { sessionVM.customSystemPrompt.isEmpty ? PromptBuilder.defaultSystemPrompt : sessionVM.customSystemPrompt },
                    set: { sessionVM.customSystemPrompt = $0 }
                ))
                .font(.body.monospaced())
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Style Nudge")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextEditor(text: $sessionVM.styleNudge)
                    .font(.body.monospaced())
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding(.vertical, 12)
    }
    
    private func parameterSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}