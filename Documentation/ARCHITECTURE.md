# Keybreeze — Architecture

## What Keybreeze Is

A **macOS menu bar app** providing **local, low-latency text continuation** (autocomplete). Uses **Ollama** or **llama.cpp** over HTTP. Includes **Typing Lab** — a permanent dev environment with live playground, diagnostics, prediction history, prompt editing, and runtime tuning.

**Design intent:** continuation only, short outputs, provider-agnostic core (`LLMProvider`), relentless focus on typing feel over raw intelligence.

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
| `Keybreeze/Core/` | `AppState`, `EditorState`, `ModelRegistry`, `ContextBuilder`, `PredictionMode`, `PredictionEngine`, `PredictionScheduler`, `PredictionHistory`, `ShadowPredictor` |
| `Keybreeze/LLM/` | `LLMProvider` protocol, Ollama + llama.cpp backends, `PromptBuilder` |
| `Keybreeze/UI/` | Menu bar window, `PredictionSessionViewModel`, `TypingLab/` subfolder |
| `Keybreeze/Utils/` | `WordLimiter`, `Debouncer`, `KeybreezeLatencyLogger` |

---

## Runtime Object Graph

```
KeybreezeApp
 ├── AppState (selectedModel, selectedBackend, model catalog, process manager)
 └── PredictionSessionViewModel (draft text → scheduler → engine → provider)
      └── PredictionScheduler (debounced midType/pause loop)
           └── PredictionEngine (single stream, word cap, cancellation)
                └── LLMProvider (OllamaLLMService | LlamaCppService)
```

- **Backend switching:** `AppState.selectedBackend` triggers `handleBackendChange()` which toggles model catalog, stops/starts `llama-server`, and rebuilds the engine.
- **Process management:** `LlamaCppProcessManager` spawns `/opt/homebrew/bin/llama-server`, waits for `/health` to respond `{"status":"ok"}`, and SIGKILLs on stop to free the port immediately.
- **GGUF scanning:** `LlamaCppModelCatalog.scanDirectory()` lists `.gguf` files from the configured models directory and maps them to `ModelOption` instances.

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
    func streamCompletion(prompt: String, model: String, onToken: @escaping (String) -> Void) async throws
    func cancel()
}
```

### Backends

| Backend | Service | How it works |
|---------|---------|--------------|
| Ollama | `OllamaLLMService` | SSE streaming via `/api/generate`, model tag sent per-request |
| llama.cpp | `LlamaCppService` | Non-streaming `POST /completion` (llama.cpp SSE has no terminating event, so non-streaming is used for reliability). Model loaded at server start, `model` param unused. |

### llama.cpp Lifecycle
- `LlamaCppProcessManager` auto-launches `llama-server` when backend switches to `.llamaCpp`.
- Health-checked via `/health` endpoint (up to 22.5s timeout for model loading).
- Auto-killed on backend switch or app termination (SIGKILL for immediate port release).
- Binary path: `/opt/homebrew/bin/llama-server` (Homebrew install).

### GGUF Models
- Directory: configurable via `LlamaCppConfiguration.modelsDirectory` (defaults to user's path).
- Scanned by `LlamaCppModelCatalog` for `.gguf` files; display names derived from filenames.
- Each GGUF file becomes a `ModelOption` with `ggufPath` set and `ollamaId` empty.

---

## Model Selection

- `AppState.refreshAvailableModels()` dispatches to the current backend's catalog.
- **Ollama:** `OllamaModelCatalog.fetchInstalledTags()` hits `GET /api/tags`.
- **llama.cpp:** `LlamaCppModelCatalog.scanDirectory()` walks the GGUF directory.
- `ModelRegistry.option(resolvingOllamaTag:)` maps tags to `ModelOption` with per-model presets.

---

## Key Design Decisions

- **Sandbox disabled** (`ENABLE_APP_SANDBOX = NO`) — required for file system access to GGUF directory and spawning `llama-server` as a child process.
- **Non-streaming for llama.cpp** — SSE mode never sends a terminating event, causing `bytes.lines` to hang indefinitely. Non-streaming delivers full response in one HTTP exchange (~400ms for 32 tokens on Gemma 4 E2B).
- **Runtime parameters** (`temperature`, `topP`, `repeatPenalty`, `confidenceThreshold`, biases) are user-tunable via Typing Lab sliders. Aggression presets (Conservative/Balanced/Aggressive) batch-set these.
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

New Swift files must be added to `Keybreeze.xcodeproj` (PBXFileReference, PBXBuildFile, group, Sources phase). The new llama.cpp files (`LlamaCppProcessManager.swift`, `LlamaCppModelCatalog.swift`) have been added.