# Keybreeze — architecture

This document is for humans and coding agents who need to change the project without rediscovering layout from scratch.

## What Keybreeze is

A **macOS menu bar app** that provides **local, low-latency text continuation** (autocomplete), not a chat assistant. It uses **Ollama** over HTTP for inference and includes a **live typing harness with inline ghost text** and **runtime tuning controls** in the menu bar window.

Design intent: **continuation only**, short outputs, provider-agnostic core (`LLMProvider`).

## Tech stack

- **SwiftUI** + `MenuBarExtra` (`.window` style)
- **Swift Concurrency** (`async`/`await`, `Task`) for streaming and cancellation
- **Ollama** REST: `GET /api/tags` (model list), `POST /api/generate` (streaming completions)

## Directory layout

| Path | Role |
|------|------|
| `Keybreeze/App/` | `@main` entry, AppKit activation policy (accessory agent) |
| `Keybreeze/Core/` | `AppState`, `EditorState`, `ModelRegistry`, `ContextBuilder`, `PredictionMode`, `PredictionEngine`, `PredictionScheduler` |
| `Keybreeze/LLM/` | `LLMProvider` protocol, Ollama HTTP client, tags catalog, `PromptBuilder` |
| `Keybreeze/UI/` | Menu bar window, `PredictionSessionViewModel` |
| `Keybreeze/Utils/` | `WordLimiter`, `Debouncer`, `KeybreezeLatencyLogger` |
| `Documentation/` | Planning and this architecture note |

## Runtime object graph

- **`KeybreezeApp`** owns `@StateObject` **`AppState`** and **`PredictionSessionViewModel`** (shared `AppState`).
- **`MenuBarContentView`** — model picker, **Live typing (Phase 2.5)** harness with inline ghost text, and collapsible **runtime tuning** section.
- **`PredictionSessionViewModel`** — draft text field → **`PredictionScheduler`** → **`PredictionEngine`** → **`LLMProvider`**. Exposes tuning overrides for verbosity, continuation, instruction strictness, and max words.
- **`PredictionTestViewModel`** — removed in Phase 2.5 (subsumed by live typing harness).

## Prediction pipeline (Phase 2)

1. **`EditorState`** — text before/after caret (harness uses draft text; Obsidian comes later).
2. **`ContextBuilder.focusedState(from:)`** — trims to ~800 characters before prompting.
3. **`PromptBuilder.continuationPrompt(for:modelOption:)`** — strict autocomplete instructions + style profile from `ModelOption`.
4. **`PredictionScheduler`** — debounced loop:
   - **midType** — 150ms after keystroke, shorter word cap
   - **pause** — 450ms after last keystroke, full model word cap
   - cancels stale jobs on each keystroke; pause supersedes midType
5. **`PredictionEngine`** — single active stream, word cap via **`WordLimiter`**, cooperative cancel.
6. **`LLMProvider.streamCompletion`** — Ollama `/api/generate` streaming today.

## Model selection (important)

1. **Live list**: `AppState.refreshAvailableModelsFromOllama()` calls **`OllamaModelCatalog.fetchInstalledTags`**, which hits **`GET {baseURL}/api/tags`**. That list is the same model names you see from `ollama list`.
2. **Tuning presets**: **`ModelRegistry.option(resolvingOllamaTag:)`** maps each tag to a **`ModelOption`**. Known tags (e.g. Qwen / Gemma presets) get hand-tuned `verbosityBias`, `continuationBias`, `instructionStrictness`, and `displayName`. Any other installed model gets **sensible defaults** so the app still works.
3. **Do not hardcode model tags in UI** beyond the registry presets used for display names and behaviour. New presets: add a `ModelOption` and register it in `presetsByOllamaId`.

Per-model tuning fields on **`ModelOption`** (used in prompts today; runtime sliders planned for Phase 2.5):

| Field | Effect |
|-------|--------|
| `verbosityBias` | Steers prompt toward low/medium/high verbosity |
| `continuationBias` | Strict vs loose continuation framing |
| `instructionStrictness` | How strongly the model must follow autocomplete rules |
| `maxWords` | Upper bound for streamed completion length |

## Ollama configuration

- **`OllamaConfiguration.baseURL`** defaults to **`http://127.0.0.1:11434`** to avoid `localhost` resolving to IPv6 (`::1`) when the daemon only listens on IPv4.
- To point at another host, inject `OllamaConfiguration` where `AppState` is created (currently `KeybreezeApp` uses defaults).

## Adding a second inference backend (e.g. llama.cpp)

1. Add a type conforming to **`LLMProvider`**.
2. Swap or branch the implementation passed into **`PredictionEngine`**. Keep **`ModelOption.ollamaId`** as “provider model id” or generalize naming when you add a second backend.

## Logging

- **`KeybreezeLatencyLogger`** prints a `[KeybreezeLatency]` block to stdout when at least one token was received (TTFT, total time, word count). Cancelled runs with no tokens are silent.
- Superseded **midType** requests cancelled by **pause** log at `debug` only — not as errors.

## Phase 2.5 — Ghost text harness + tuning (complete)

Inline ghost text renders as a low-opacity overlay directly on a plain-style TextField in the menu bar typing harness. Runtime tuning sliders for verbosity, continuation bias, and instruction strictness override model presets on the fly — no restart needed. The Phase 1 one-shot test harness has been removed. See **`PHASE-PLAN.md`** for the full plan.

## Next — Phase 3: Obsidian integration

## Xcode project

New Swift files must be added to **`Keybreeze.xcodeproj`** (PBXFileReference, PBXBuildFile, group, Sources phase). Missing entries cause “Cannot find X in scope” at compile time.

## Related docs

- **`PHASE-PLAN.md`** — phased delivery plan.
- **`BRIEF.md`** — product brief.
