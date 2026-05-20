# Keybreeze — Architecture

## What Keybreeze Is

A **macOS menu bar app** providing **local, low-latency text continuation** (autocomplete). Uses **Ollama** (primary) or **llama.cpp** (secondary/experimental) over HTTP. Includes **Typing Lab** — a permanent dev environment with live playground, diagnostics, prediction history, prompt editing, and runtime tuning.

**Design intent:** continuation only, short outputs, provider-agnostic core (`LLMProvider`), relentless focus on typing feel over raw intelligence.

Not an inference infrastructure project. The LLM layer is replaceable plumbing — simplified to the smallest set of abstractions that pay rent.

---

## Phase Status

| Phase | Status |
|-------|--------|
| Phase 0 — Project Skeleton | ✅ |
| Phase 1 — LLM Pipeline (Ollama + llama.cpp) | ✅ |
| Phase 2 — Prediction Engine | ✅ |
| Phase 2.5 — Ghost Text Harness | ✅ |
| Typing Lab / Feel Engineering | ✅ |
| Phase 3 — Obsidian Integration | 🔜 Next |

---

## Directory Layout

| Path | Role |
|------|------|
| `Keybreeze/App/` | `@main` entry, AppKit activation policy, termination cleanup |
| `Keybreeze/Core/` | `AppState`, `EditorState`, `ModelRegistry`, `ContextBuilder`, `PredictionMode`, `PredictionEngine`, `PredictionScheduler`, `PredictionHistory`, `ShadowPredictor`, `AccessibilityManager`, `InputSourceMonitor`, `AppSettings` |
| `Keybreeze/LLM/` | `LLMProvider` protocol, `LLMBackend` enum, `LLMConfig`, Ollama + llama.cpp services (with internalized model catalog + process mgmt), `PromptBuilder` |
| `Keybreeze/UI/` | Menu bar window, `PredictionSessionViewModel`, `TypingLab/` subfolder |
| `Keybreeze/Utils/` | `WordLimiter`, `Debouncer`, `KeybreezeLatencyLogger` |

---

## Runtime Object Graph

```
KeybreezeApp
 ├── AppState (selectedModel, selectedBackend, LLMConfig, model catalog, server state)
 ├── AccessibilityManager (singleton: focused app detection, AX text read, insertion)
 ├── InputSourceMonitor (singleton: IME composition safety gate)
 └── PredictionSessionViewModel (draft text → scheduler → engine → provider)
      ├── AppSettings (consolidated Codable settings, single save/load entry point)
      └── PredictionScheduler (debounced midType/pause loop)
           └── PredictionEngine (single stream, word cap, cancellation)
                └── LLMProvider (OllamaLLMService | LlamaCppService)
```

- **Backend switching:** `AppState.selectedBackend` triggers `handleBackendChange()` which toggles model catalog, manages `LlamaCppService` server lifecycle, and rebuilds the engine.
- **Process management:** Internal to `LlamaCppService` — spawns `/opt/homebrew/bin/llama-server`, health-checks via `/health`, and SIGKILLs on stop. Exposes only `serverState` for UI readiness feedback.
- **GGUF scanning:** `LlamaCppService.scanModels()` lists `.gguf` files from the configured models directory and maps them to `ModelOption` instances.

---

## Prediction Pipeline

1. **`EditorState`** — text before/after caret from Typing Lab (or external editor later).
2. **`ContextBuilder.focusedState(from:)`** — trims to ~800 chars.
3. **`PromptBuilder.continuationPrompt(...)`** — strict autocomplete instructions + style profile.
4. **`PredictionScheduler`** — debounced loop: midType (150ms after keystroke, short word cap) / pause (450ms idle, full word cap).
5. **`PredictionEngine`** — single stream, word cap via `WordLimiter`, cooperative cancel, custom prompt passthrough.
6. **`LLMProvider.streamCompletion`** — Ollama `/api/generate` (SSE streaming) or llama.cpp `/completion` (non-streaming, full response delivered as one token).

---

## Backend Architecture

### LLMProvider Protocol
```swift
protocol LLMProvider {
    func streamCompletion(prompt: String, model: String, modelOption: ModelOption, onToken: @escaping (String) -> Void) async throws
    func cancel()
}
```

### Backends

| Backend | Service | How it works |
|---------|---------|--------------|
| Ollama (primary) | `OllamaLLMService` | SSE streaming via `/api/generate`, model tag sent per-request. Model catalog: `OllamaLLMService.fetchInstalledTags(baseURL:)` |
| llama.cpp (experimental) | `LlamaCppService` | Non-streaming `POST /completion` (llama.cpp SSE has no terminating event, so non-streaming is used for reliability). Model loaded at server start. Model catalog: `LlamaCppService.scanModels(directory:)`. Process lifecycle fully internalised (start/stop/health-check). |

### Configuration

A single flat `LLMConfig` struct replaces the exploded `LLMConfiguration` + `OllamaConfiguration` + `LlamaCppConfiguration` pattern:

```swift
struct LLMConfig: Equatable, Sendable {
    var backend: LLMBackend = .ollama
    var ollamaBaseURL: URL = URL(string: "http://127.0.0.1:11434")!
    var llamaCppBaseURL: URL = URL(string: "http://127.0.0.1:11345")!
    var llamaCppModelsDirectory: String = "/Users/..."
}
```

`AppState` holds a single `config` property and exposes `effectiveConfig` for engine creation. Consumers no longer assemble sub-configs.

### llama.cpp Lifecycle

- `LlamaCppService` owns the full lifecycle internally (spawn, health-check, SIGTERM→SIGKILL).
- `AppState` observes `llamaCppServerState` for UI readiness; it does not hold a reference to a process manager.
- On backend switch to `llamaCpp`, `AppState` calls `addLlamaCppService()` which wires state observation and stores an internal reference to the service.
- On app termination, `AppState.stopLlamaCppServer()` is called (via `AppKitLifecycle`).
- Metal isolation env vars (`GGML_METAL_NO_RETAIN_MEMORY`, `GGML_METAL_DEVICE_ID`, `GGML_METAL_RESOURCE_CACHE`) are injected by the service.

### GGUF Models

- Directory: configurable via `LLMConfig.llamaCppModelsDirectory`.
- Scanned by `LlamaCppService.scanModels(directory:)` for `.gguf` files; display names derived from filenames.
- Each GGUF file becomes a `ModelOption` with `ggufPath` set and `ollamaId` empty.

---

## Model Selection

- `AppState.refreshAvailableModels()` dispatches to the current backend's catalog.
- **Ollama:** `OllamaLLMService.fetchModelOptions(baseURL:)` hits `GET /api/tags` and resolves via `ModelRegistry`.
- **llama.cpp:** `LlamaCppService.scanModels(directory:)` walks the GGUF directory.
- `ModelRegistry.option(resolvingOllamaTag:)` maps tags to `ModelOption` with per-model presets.

---

## Key Design Decisions

- **LLM layer is deliberately thin.** No infrastructure-style layering, no over-separated config objects, no duplicated backend-specific logic. Ollama is the primary production backend; llama.cpp is secondary with its complexity internalised privately.
- **Sandbox disabled** (`ENABLE_APP_SANDBOX = NO`) — required for file system access to GGUF directory and spawning `llama-server` as a child process.
- **Non-streaming for llama.cpp** — SSE mode never sends a terminating event, causing `bytes.lines` to hang indefinitely. Non-streaming delivers full response in one HTTP exchange (~400ms for 32 tokens on Gemma 4 E2B).
- **Runtime parameters** (`temperature`, `topP`, `repeatPenalty`, `presencePenalty`, `confidenceThreshold`, biases) are user-tunable via Typing Lab sliders. Aggression presets (Conservative/Balanced/Aggressive) batch-set these.
- **Prompt editing** — system and continuation prompts are overridable at runtime via the Typing Lab.
- **Shadow prediction** — `ShadowPredictor` runs silent background predictions for quality evaluation.
- **Prediction history** — ring buffer (200 records) with TTFT, total time, resolution tracking.

---

## Logging

- `[KeybreezeLatency]` block in stdout: model, TTFT, total time, word count.
- Cancelled runs with no tokens are silent.
- Superseded midType requests cancelled by pause log at debug only.

---

## Xcode Project

New Swift files must be added to `Keybreeze.xcodeproj` (PBXFileReference, PBXBuildFile, group, Sources phase). The LLM layer consists of 5 files: `LLMProvider.swift`, `LLMBackend.swift`, `OllamaLLMService.swift`, `LlamaCppService.swift`, `PromptBuilder.swift`.