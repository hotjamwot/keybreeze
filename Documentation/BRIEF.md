# Keybreeze — Product Brief

*Local-first macOS menu bar app. Continuously predicts the next words you were already about to type, without interrupting flow.*

---

## Product Definition

A menu bar app that:
- Runs fully offline (Ollama or llama.cpp + GGUF)
- Provides inline ghost-text continuation
- Tab accepts one word at a time
- Prioritises latency and feel over raw intelligence

**Core promise:** *Create uninterrupted writing flow.* Not autocomplete spam. Not AI authorship. Cognitive acceleration through anticipatory language completion.

The soul of Keybreeze is: **Keybreeze is a local-first cognitive flow amplifier that predicts and removes low-friction language work without stealing authorship or interrupting momentum. It removes friction between thought and typing.**

---

## What Keybreeze Is NOT

Keybreeze is not primarily an app integration project. It is a **real-time typing cognition engine**. The central challenges are timing, cancellation, cadence, confidence, editing stability, and acceptance psychology — not Obsidian hooks or overlays.

External app integration is an interface problem. Typing feel is the product.

---

## Project Structure

```
Keybreeze/
├── App/              KeybreezeApp.swift, AppKit lifecycle, termination cleanup
├── Core/             AppState, ModelRegistry, PredictionEngine, Scheduler, History, ShadowPredictor
├── LLM/              LLMProvider protocol, Ollama + llama.cpp backends, PromptBuilder
├── UI/               MenuBarContentView, PredictionSessionViewModel, TypingLab/ (5 views)
├── Utils/            WordLimiter, Debouncer, LatencyLogger
```

---

## Backend: Dual-Engine Architecture

| Backend | Service | Protocol | Model Source |
|---------|---------|----------|-------------|
| Ollama | `OllamaLLMService` | SSE `/api/generate` | `ollama list` (Ollama tags) |
| llama.cpp | `LlamaCppService` | Non-streaming `POST /completion` | GGUF files from user directory |

Shared `LLMProvider` protocol. Backend selected via segmented control in the menu bar. Swapping backends auto-manages the `llama-server` process lifecycle (launch, health-check, SIGKILL on stop).

---

## Key Components

- **PredictionScheduler** — debounced midType (150ms) / pause (450ms) loop. Cancels stale jobs, passes runtime prompt overrides.
- **PredictionEngine** — single active stream, word cap, cooperative cancellation.
- **Typing Lab** — permanent dev environment: live playground, diagnostics panel, prediction history (ring buffer, 200 records), runtime prompt editing, parameter sliders, behaviour presets.
- **ShadowPredictor** — silent background predictions for quality evaluation.
- **ModelRegistry/ModelOption** — per-model presets (verbosity, strictness, temperature, topP, repeatPenalty, etc.). GGUF models get sensible defaults.
- **LlamaCppProcessManager** — spawns `llama-server` and waits for `/health` to confirm readiness.
- **LlamaCppModelCatalog** — scans directory for `.gguf` files and maps to `ModelOption`.

---

## Design Decisions

- **Sandbox disabled** — needed for file access to GGUF directory and `Process()` spawning.
- **Non-streaming for llama.cpp** — SSE never sends a terminating event, causing hangs. Non-streaming delivers full response in one HTTP exchange.
- **Runtime tuning** — all parameters overridable via sliders. Aggression presets for quick iteration.
- **Prediction history** — every prediction (accepted/ignored/cancelled) recorded with TTFT, total time, parameters.
- **No animation** — ghost text is static overlay. No flicker, no transitions.

---

## Phases

| Phase | Status |
|-------|--------|
| 0 — Project Skeleton | ✅ |
| 1 — LLM Pipeline (Ollama + llama.cpp) | ✅ |
| 2 — Prediction Engine | ✅ |
| 2.5 — Ghost Text + Tuning | ✅ |
| Typing Lab / Feel Engineering | ✅ |
| 3 — Obsidian Integration | 🔜 Next |
| 4 — Tab Accept System | Later |
| 5+ — Polish, Style Memory, Expansion | Later |

---

## Performance Targets

- Keystroke → UI update: <10ms
- Prediction scheduling: <50ms overhead
- Inference start: <100ms perceived
- Total latency goal: 30–60ms feel

---

## Philosophy

Keybreeze should feel like *assisted momentum* — not autocomplete, not AI co-writing. The system biases toward restraint, brevity, timing precision, and low interruption. The user must always feel in control.

Every architectural decision serves one goal: **the user feels like they are writing better and faster, not like an AI is writing for them.**