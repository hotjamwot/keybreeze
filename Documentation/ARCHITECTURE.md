# Keybreeze — Architecture

This document is for humans and coding agents who need to change the project without rediscovering layout from scratch.

## What Keybreeze Is

A **macOS menu bar app** that provides **local, low-latency text continuation** (autocomplete), not a chat assistant. It uses **Ollama** over HTTP for inference and includes a **Typing Lab** — a permanent internal development environment with a live typing playground, inline ghost text, engine diagnostics, prediction history, runtime prompt editing, and runtime tuning controls.

**Design intent:** continuation only, short outputs, provider-agnostic core (`LLMProvider`), and a relentless focus on typing feel over technical impressiveness.

### What Keybreeze Is NOT

Keybreeze is NOT primarily an app integration project. It is a **real-time typing cognition and prediction engine**. External app integration is an interface problem. Typing feel is the product.

The project goal is not "Generate intelligent text." The project goal is **"Create uninterrupted writing flow."**

---

## Current Phase Status

| Phase | Status |
|-------|--------|
| Phase 0 — Project Skeleton | ✅ Complete |
| Phase 1 — LLM Pipeline | ✅ Complete |
| Phase 2 — Prediction Engine | ✅ Complete |
| Phase 2.5 — Ghost Text Harness | ✅ Complete |
| **Typing Lab / Feel Engineering** | **✅ Implemented** |
| Phase 3 — Obsidian Integration | 🔜 Next |
| Phase 4 — Tab Accept System | Later |
| Phase 5+ — Polish, Style Memory, Expansion | Later |

---

## Tech Stack

- **SwiftUI** + `MenuBarExtra` (`.window` style)
- **Swift Concurrency** (`async`/`await`, `Task`) for streaming and cancellation
- **Ollama** REST: `GET /api/tags` (model list), `POST /api/generate` (streaming completions)

## Directory Layout

| Path | Role |
|------|------|
| `Keybreeze/App/` | `@main` entry, AppKit activation policy (accessory agent) |
| `Keybreeze/Core/` | `AppState`, `EditorState`, `ModelRegistry`, `ContextBuilder`, `PredictionMode`, `PredictionEngine`, `PredictionScheduler`, `PredictionHistory`, `ShadowPredictor` |
| `Keybreeze/LLM/` | `LLMProvider` protocol, Ollama HTTP client, tags catalog, `PromptBuilder` |
| `Keybreeze/UI/` | Menu bar window, `PredictionSessionViewModel`, `TypingLab/` subfolder |
| `Keybreeze/Utils/` | `WordLimiter`, `Debouncer`, `KeybreezeLatencyLogger` |
| `Documentation/` | Planning and this architecture note |

## Runtime Object Graph

- **`KeybreezeApp`** owns `@StateObject` **`AppState`** and **`PredictionSessionViewModel`** (shared `AppState`).
- **`MenuBarContentView`** — model picker, **Typing Lab** entry point with "Expand" toggle (compact playground vs full lab), live typing harness with inline ghost text.
- **`TypingLabRootView`** — three-tab container (Playground, Diagnostics, History) with toggleable sections for diagnostics, parameters, and prompt editing.
- **`PredictionSessionViewModel`** — draft text field → **`PredictionScheduler`** → **`PredictionEngine`** → **`LLMProvider`**. Extended with: runtime model parameters (temperature, topP, repeatPenalty, confidenceThreshold), custom prompt overrides, `AggressionPreset` selection, `PredictionHistory` ring buffer, and prompt override wiring.
- **`PredictionTestViewModel`** — removed in Phase 2.5 (subsumed by Typing Lab).

## Prediction Pipeline

1. **`EditorState`** — text before/after caret (Typing Lab uses draft text; external editors come later).
2. **`ContextBuilder.focusedState(from:)`** — trims to ~800 characters before prompting.
3. **`PromptBuilder.continuationPrompt(for:modelOption:customSystemPrompt:customContinuationPrompt:)`** — strict autocomplete instructions + style profile from `ModelOption`. Supports runtime prompt overrides: non-empty strings replace built-in defaults.
4. **`PredictionScheduler`** — debounced loop:
   - **midType** — 150ms after keystroke, shorter word cap
   - **pause** — 450ms after last keystroke, full model word cap
   - cancels stale jobs on each keystroke; pause supersedes midType
   - passes custom prompt overrides to engine
5. **`PredictionEngine`** — single active stream, word cap via **`WordLimiter`**, cooperative cancel, custom prompt passthrough.
6. **`LLMProvider.streamCompletion`** — Ollama `/api/generate` streaming today.

## The Typing Lab

The Typing Lab is a **permanent internal development environment** that replaces the temporary test harness concept. It is a core part of the application architecture and remains useful even after external integrations ship.

### Why It Exists

The central challenge of Keybreeze is not Obsidian integration, Accessibility APIs, or ghost text rendering. It is:

- prediction timing and cancellation behaviour
- text cadence and responsiveness
- latency stability and interruption handling
- confidence gating and continuation quality
- live editing behaviour and suggestion restraint
- acceptance psychology and typing flow

The Typing Lab provides a controlled environment for rapidly iterating on these dimensions without external integration friction.

### Components (all implemented)

| Component | File(s) | Status |
|-----------|---------|--------|
| Persistent Typing Playground | `TypingLabRootView.swift`, `MenuBarContentView.swift` | ✅ |
| Live Engine Diagnostics Panel | `DiagnosticsPanelView.swift` | ✅ |
| Prediction History / Replay System | `PredictionHistory.swift`, `PredictionHistoryView.swift` | ✅ |
| Runtime Prompt Editing | `PromptEditorView.swift`, `PromptBuilder.swift`, `PredictionEngine.swift` | ✅ |
| Runtime Model Parameter Controls | `ParameterControlsView.swift` | ✅ |
| Aggression / Behaviour Presets | `PredictionSessionViewModel.swift` | ✅ |
| Thinking Suppression | Design principle (API-level TBD) | ⚠️ |
| Shadow Prediction Mode | `ShadowPredictor.swift` | ✅ |
| Editing Stability | Architecture supports it (ongoing) | ⚠️ |

### Architecture Clarification

The prediction engine remains fully decoupled from overlays, accessibility APIs, app integrations, and rendering systems. The Typing Lab UI is a **client of the engine**, not part of the engine itself. This preserves stability, debuggability, portability, and future cross-app expansion.

## Model Selection (Important)

1. **Live list**: `AppState.refreshAvailableModelsFromOllama()` calls **`OllamaModelCatalog.fetchInstalledTags`**, which hits **`GET {baseURL}/api/tags`**. That list is the same model names you see from `ollama list`.
2. **Tuning presets**: **`ModelRegistry.option(resolvingOllamaTag:)`** maps each tag to a **`ModelOption`**. Known tags (e.g. Qwen / Gemma presets) get hand-tuned `verbosityBias`, `continuationBias`, `instructionStrictness`, `displayName`, `temperature`, `topP`, `repeatPenalty`, `confidenceThreshold`. Any other installed model gets **sensible defaults**.
3. **Do not hardcode model tags in UI** beyond the registry presets used for display names and behaviour.

Per-model tuning fields on **`ModelOption`**:

| Field | Effect |
|-------|--------|
| `verbosityBias` | Steers prompt toward low/medium/high verbosity |
| `continuationBias` | Strict vs loose continuation framing |
| `instructionStrictness` | How strongly the model must follow autocomplete rules |
| `maxWords` | Upper bound for streamed completion length |
| `temperature` | LLM temperature (0.0–1.5) |
| `topP` | Top-p sampling (0.0–1.0) |
| `repeatPenalty` | Repetition penalty (0.5–2.0) |
| `confidenceThreshold` | Minimum confidence to display prediction |

## Ollama Configuration

- **`OllamaConfiguration.baseURL`** defaults to **`http://127.0.0.1:11434`** to avoid `localhost` resolving to IPv6 (`::1`) when the daemon only listens on IPv4.
- To point at another host, inject `OllamaConfiguration` where `AppState` is created (currently `KeybreezeApp` uses defaults).

## Adding a Second Inference Backend (e.g. llama.cpp)

The architecture now supports multiple backends through a clean abstraction layer. This makes it easy to add new inference engines like llama.cpp, HTTP APIs, or local libraries.

### Core Abstraction: LLMProvider

All backend services implement the `LLMProvider` protocol:

```swift
protocol LLMProvider {
    func streamCompletion(
        prompt: String,
        model: String,
        onToken: @escaping (String) -> Void
    ) async throws
    func cancel()
}
```

This protocol defines a single active stream with cooperative cancellation. Any type conforming to `LLMProvider` can be used interchangeably in the prediction engine.

### Backend Implementations

#### OllamaLLMService
The original implementation that communicates with the local Ollama daemon via HTTP API (`/api/generate` streaming endpoint).

#### LlamaCppService (NEW)
A new implementation that follows the same pattern. This provides a second selectable backend for comparing latency consistency, cadence, interruption handling, and overall writing feel.

### Backend Selection

#### LLMBackend Enum
An enum that represents the available backends and provides a factory method to create the appropriate provider:

```swift
enum LLMBackend: String, CaseIterable, Identifiable {
    case ollama
    case llamaCpp
    
    func makeProvider(configuration: LLMConfiguration) -> any LLMProvider
}
```

### Unified Configuration

#### LLMConfiguration
A struct that holds configuration for all supported backends, making it easy to pass around a single configuration object:

```swift
struct LLMConfiguration {
    var ollamaConfiguration: OllamaConfiguration
    var llamaCppConfiguration: LlamaCppConfiguration
}
```

### Integration Points

#### PredictionEngine
The prediction engine now accepts a `backend: LLMBackend` and `configuration: LLMConfiguration` in its initializer. It creates the appropriate provider using the backend's factory method:

```swift
init(backend: LLMBackend, configuration: LLMConfiguration) {
    self.backend = backend
    self.configuration = configuration
    self.provider = backend.makeProvider(configuration: configuration)
}
```

#### AppState
Updated to store:
- `selectedBackend: LLMBackend` - the currently active backend
- Both `ollamaConfiguration` and `llamaCppConfiguration` - independent configuration for each backend

#### PredictionSessionViewModel
Exposes the selected backend and creates the prediction engine with the correct configuration from appState.

#### UI Components
- **ParameterControlsView**: Added a segmented control for selecting the backend, bound to `predictionSession.selectedBackend`.
- **DiagnosticsPanelView**: Displays the currently selected backend alongside model information.

### Benefits

- **Clean Abstraction**: The `LLMProvider` protocol allows easy swapping of backends without affecting the rest of the codebase.
- **Side-by-Side Comparison**: Users can switch between Ollama and llama.cpp to compare latency consistency, cadence, interruption handling, and overall writing feel.
- **Future-Proof**: Adding new backends (e.g., HTTP API, Windows ML) only requires creating a new service that conforms to `LLMProvider`.
- **Configuration Management**: Both backends have their own configuration objects, making it easy to manage connection settings independently.

## Logging

- **`KeybreezeLatencyLogger`** prints a `[KeybreezeLatency]` block to stdout when at least one token was received (TTFT, total time, word count). Cancelled runs with no tokens are silent.
- Superseded **midType** requests cancelled by **pause** log at `debug` only — not as errors.

## Typing Lab Phase — New Files Added

```
Keybreeze/Core/PredictionHistory.swift     # PredictionRecord, PredictionParametersSnapshot, PredictionHistory
Keybreeze/Core/ShadowPredictor.swift       # Invisible prediction for quality evaluation
Keybreeze/UI/TypingLab/TypingLabRootView.swift   # Main container with 3-tab layout
Keybreeze/UI/TypingLab/DiagnosticsPanelView.swift    # Live metrics grid
Keybreeze/UI/TypingLab/ParameterControlsView.swift   # Runtime parameter sliders
Keybreeze/UI/TypingLab/PromptEditorView.swift        # Runtime prompt editing
Keybreeze/UI/TypingLab/PredictionHistoryView.swift   # Scrolling timeline with filter
```

## Files Modified

```
Keybreeze/Core/ModelRegistry.swift          # Extended ModelOption with temperature, topP, repeatPenalty, confidenceThreshold
Keybreeze/Core/PredictionEngine.swift       # Added custom prompt passthrough params
Keybreeze/Core/PredictionScheduler.swift    # Added updatePromptOverrides() closure
Keybreeze/LLM/PromptBuilder.swift           # Added customSystemPrompt, customContinuationPrompt params
Keybreeze/UI/MenuBarContentView.swift       # Redesigned with Typing Lab toggle + expand/collapse
Keybreeze/UI/PredictionSessionViewModel.swift  # Extended with params, presets, history, prompt overrides
```

## Next — Phase 3 Obsidian Integration

After the Typing Lab phase, Obsidian integration reuses the engine, scheduler, and overlay patterns proven in the Typing Lab. External integrations are implementation layers built on top of a solved interaction engine.

## Xcode Project

New Swift files must be added to **`Keybreeze.xcodeproj`** (PBXFileReference, PBXBuildFile, group, Sources phase). Missing entries cause "Cannot find X in scope" at compile time. The Typing Lab phase added 7 new files across Core and UI/TypingLab groups.

## Related Docs

- **`PHASE-PLAN.md`** — phased delivery plan with current status markers.
- **`BRIEF.md`** — product brief with strategic framing and current implementation details.