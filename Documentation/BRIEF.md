# Keybreeze — Product Brief

*Local-first macOS menu bar app. Continuously predicts the next words you were already about to type, without interrupting flow.*

---

## Product Definition

A menu bar app that:
- Runs fully offline (Ollama primary, llama.cpp optional)
- Provides inline ghost-text continuation
- Tab accepts one word at a time
- Prioritises latency and feel over raw intelligence

**Core promise:** *Create uninterrupted writing flow.* Not autocomplete spam. Not AI authorship. Cognitive acceleration through anticipatory language completion.

The soul of Keybreeze is: **Keybreeze is a local-first cognitive flow amplifier that predicts and removes low-friction language work without stealing authorship or interrupting momentum. It removes friction between thought and typing.**

---

## What Keybreeze Is NOT

Keybreeze is not an inference infrastructure project. It is not a model orchestration platform. The LLM layer is replaceable plumbing — deliberately kept thin, quiet, and invisible.

Keybreeze is a **prediction scheduler, a context engine, a typing flow system, and an insertion/cadence engine** — not a tool for managing inference infrastructure.

External app integration is an interface problem. Typing feel is the product.

---

## Behavioral Specifications

### Core UX Philosophy

The assistant must feel:

* Invisible
* Immediate
* Non-intrusive
* Forgiving
* Cognitively lightweight
* Always one thought ahead
* Never "thinking"

The user should feel like:

> "The computer already knows what I'm trying to say."

Latency is the primary feature. Not intelligence.

### Performance Targets

- **First token latency:** <50ms (ideal)
- **Full prediction latency:** 40-90ms (ideal), 100-140ms (acceptable), >180ms (bad)
- **UI frame rate:** 60fps
- **Keystroke processing:** <8ms
- **Debounce timing:** 35-60ms after final keystroke, sweet spot ~45ms

### Prediction Display

- Inline ghost text immediately after caret, same baseline as text
- Visual style: Grey, slightly translucent, lower contrast than committed text
- No popup by default
- Only display once minimum confidence threshold reached OR first full word completed (to avoid "dancing" predictions)

### Acceptance Behavior

- **Tab key:** Accepts full visible prediction instantly, inserts prediction, moves caret to end
- **Right Arrow:** Accepts next predicted word only (word-by-word acceptance), creating high trust and fine-grained control

### Prediction Invalidation

Predictions disappear instantly (no fade animation) when:
- User types incompatible character
- Caret moves
- Mouse click occurs
- Selection changes
- Undo occurs

### Backspace Correction (Critical Feature)

When user backspaces through a misspelled or incorrect word, the system detects hesitation and infers intended correction:

- **Incorrect word:** Greyed out with red strikethrough
- **Suggested correction:** Green inline replacement
- **Tab:** Accepts corrected word instantly
- **ESC:** Rejects correction suggestion
- **Continued typing:** Dismisses correction state immediately

### Prediction Hierarchy

The system should prioritize:
1. Local sentence completion (most important)
2. Current paragraph context
3. Writing style continuity
4. Global semantic reasoning (least important)

### UI Stability Rules

The UI must NEVER:
- Jump vertically
- Resize while typing
- Shift layout
- Animate predictions heavily
- Introduce modal interruptions

Predictive typing is peripheral cognition. Anything flashy destroys flow state.

### Cancellation Behavior

Every new keystroke must:
- Immediately cancel current inference
- Immediately begin next prediction cycle

No queued generations. Stale predictions are worse than missing predictions.

### Model Behavior Priorities

The model should optimize for:
1. Speed
2. Stability
3. Predictability
4. Low hallucination
5. Low creativity
6. Intelligence

Temperature should be: 0.1–0.3, conservative top-p. Avoid creative branching, surprising phrasing, long speculative completions.

### Context Window Strategy

Only recent text should dominate prediction:
- Last sentence = highest priority
- Last paragraph = medium priority
- Entire document = weak influence

Overly large context causes latency, semantic drift, and weird stylistic overreach.

### Trust Model

The assistant succeeds when users:
- Stop consciously reading predictions
- Develop muscle memory around Tab
- Feel "supported" rather than interrupted

The moment users begin evaluating suggestions intellectually, flow is lost.

### Engineering North Star

If forced to choose, always choose:
- Faster
- Simpler
- More stable

Over:
- Smarter
- Larger
- More creative

Because predictive typing is fundamentally a motor-control experience, not a conversational AI experience.

---

## Project Structure

```
Keybreeze/
├── App/              KeybreezeApp.swift, AppKit lifecycle, termination cleanup
├── Core/             AppState, ModelRegistry, PredictionEngine, Scheduler, History, ShadowPredictor
├── LLM/              5 files: LLMProvider protocol, LLMBackend enum + LLMConfig,
│                     OllamaLLMService, LlamaCppService, PromptBuilder
├── UI/               MenuBarContentView, PredictionSessionViewModel, SettingsView, TypingLab/ (5 views)
├── Utils/            WordLimiter, Debouncer, LatencyLogger
```

The LLM layer is intentionally minimal — no infrastructure-style layering, no over-separated config objects, no duplicated backend-specific logic.

---

## Backend Architecture

| Backend | Service | Protocol | Model Source |
|---------|---------|----------|-------------|
| Ollama (primary) | `OllamaLLMService` | SSE `/api/generate` | `OllamaLLMService.fetchInstalledTags(baseURL:)` from `GET /api/tags` |
| llama.cpp (experimental) | `LlamaCppService` | Non-streaming `POST /completion` | `LlamaCppService.scanModels(directory:)` scans GGUF directory |

Both conform to the shared `LLMProvider` protocol (13 lines). Configuration is a single flat `LLMConfig` struct — no fragmented sub-configs.

Backend selected via segmented control in the menu bar. Swapping backends auto-manages the llama.cpp server lifecycle internally (no external process manager abstraction).

---

## Key Components

- **PredictionScheduler** — debounced midType (150ms) / pause (450ms) loop. Cancels stale jobs, passes runtime prompt overrides.
- **PredictionEngine** — single active stream, word cap, cooperative cancellation.
- **Typing Lab** — permanent dev environment: live playground, diagnostics panel, prediction history (ring buffer, 200 records), runtime prompt editing, parameter sliders, behaviour presets.
- **ShadowPredictor** — silent background predictions for quality evaluation.
- **ModelRegistry/ModelOption** — per-model presets (verbosity, strictness, temperature, topP, repeatPenalty, etc.). GGUF models get sensible defaults.
- **LlamaCppService** — owns the full `llama-server` lifecycle internally (spawn, health-check via `/health`, SIGTERM→SIGKILL). Exposes `serverState` for UI readiness but keeps all process management private. Also provides static `scanModels()` for the GGUF catalog.

---

## Design Decisions

- **LLM layer is deliberately thin.** No `LlamaCppProcessManager`, `OllamaConfiguration`, or `LLMConfiguration` files exist as top-level abstractions. Process management and model catalog scanning are internalized within the services.
- **Ollama is the primary backend.** It solves model management, process lifecycle, loading, serving, caching, and compatibility — we leverage this rather than rebuilding infrastructure ourselves.
- **llama.cpp is secondary/experimental.** Its lifecycle complexity is internalised within `LlamaCppService` so it doesn't shape the app architecture.
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
| 3 — App Integration for all Mac apps | ✅ |
| 4 — Ghost Overlay in External Apps | ✅ |
| 5 — Tab Accept System (word-by-word via Tab) | ✅ |
| 6+ — Polish, Style Memory, Expansion | Later |

**Current issues:**
1. Settings window close still intermittently crashes (ViewBridge error, re-entrancy during teardown)
2. ~~Ghost text only shows in Typing Lab playground — not in third-party apps~~ → ✅ Resolved. Floating transparent overlay (`SuggestionOverlayWindowController`) positioned at the caret via AX API now shows ghost predictions in the focused third-party app.
3. ~~System-wide text insertion works via keyboard event synthesis but lacks visual prediction display in external apps~~ → ✅ Resolved. Ghost overlay appears automatically when a suggestion arrives, positioned directly after the caret.

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

This philosophy is guided by the detailed behavioral specifications outlined above, ensuring that every aspect of the system—from keystroke response timing to prediction display and acceptance behavior—works in service of an invisible, immediate, and non-intrusive typing experience.