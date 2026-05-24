# Keybreeze — Project Brief

*The purpose of this document is to outline the high-level vision, mission, and "soul" of Keybreeze. It serves as the primary reference for the project's philosophy, with pointers to the detailed technical and behavioral specifications. Any developer or AI agent working on Keybreeze should consult this document to understand the "why" behind the project, ensuring all new features and technical decisions align with our core goal of creating an invisible, non-intrusive cognitive flow amplifier.*

*For the full behavioral specification (including the implementation status of every feature), see **[BEHAVIOR.md](./BEHAVIOR.md)**. For technical architecture, file-by-file ground truth, and AI agent rules, see **[ARCHITECTURE.md](./ARCHITECTURE.md)**.*

---

## Product Definition

*Local-first macOS menu bar app. Continuously predicts the next words you were already about to type, without interrupting flow.*

A menu bar app that:
- Runs fully offline (Ollama primary, llama.cpp optional)
- Provides inline ghost-text continuation
- Tab accepts one word at a time
- Prioritises latency and feel over raw intelligence

**Core promise:** *Create uninterrupted writing flow.* Not autocomplete spam. Not AI authorship. Cognitive acceleration through anticipatory language completion.

The soul of Keybreeze is: **Keybreeze is a local-first cognitive flow amplifier that predicts and removes low-friction language work without stealing authorship or interrupting momentum. It removes friction between thought and typing.**

---

## Behavioral Summary

For the complete behavioral specification (17 sections covering prediction lifecycle, keystroke timing, display rules, acceptance behavior, prediction invalidation, backspace correction, prediction hierarchy, UI stability, streaming behavior, cancellation, model priorities, context strategy, performance targets, and the full trust model), refer to **[BEHAVIOR.md](./BEHAVIOR.md)**.

Key principles summarized:

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

## Current Implementation Status

For a full itemised checklist of all 19 desired behaviour outcomes (with per-feature status: ✅, 🔄 Partial, ❌ Not Implemented), see the **Desired Behavior Outcomes** table in **[BEHAVIOR.md](./BEHAVIOR.md)**.

In summary:
- **Tab acceptance, prediction invalidation, latency monitoring, and acceptance history** are the most mature features.
- **System-wide prediction, ghost overlay, app gating, and IME safety** are implemented but have known bugs.
- **Backspace correction** and **Right Arrow word-by-word acceptance** are not yet implemented.
- **Many features** are marked "Implemented but buggy" — the core pipeline works but edge cases remain.

---

## Project Structure (Current)

```
Keybreeze/
├── App/               KeybreezeApp.swift, AppKit lifecycle, termination cleanup
├── Core/              AppState, CompletionController, SystemWidePredictor,
│                      PredictionHistory, AccessibilityManager, InputSourceMonitor
├── LLM/               LLMClient (HTTP client for Ollama + llama.cpp), PromptBuilder
├── UI/                MenuBarContentView, SessionViewModel, SettingsView, GhostTextModifier,
│                      SuggestionOverlayWindow (floating overlay for 3rd-party apps),
│                      TypingLab/ (playground, diagnostics, gating panel)
├── Utils/             KeybreezeLatencyLogger
```

The LLM layer is intentionally minimal — a single `LLMClient` class that speaks the OpenAI `/v1/chat/completions` API format to both Ollama and llama.cpp. No infrastructure-style layering, no over-separated config objects, no duplicated backend-specific logic.

---

## Backend Architecture

| Backend | Service | Protocol | Model Source |
|---------|---------|----------|-------------|
| Ollama (primary) | `LLMClient` | SSE `/v1/chat/completions` | `GET /api/tags` |
| llama.cpp (experimental) | `LLMClient` | Non-streaming `POST /completion` | Scans GGUF directory |

Both backends are served by a single `LLMClient` class. Configuration is a single flat `LLMConfig` struct — no fragmented sub-configs. Backend selected via segmented control in the menu bar.

---

## Key Components (Current)

- **CompletionController** (`@MainActor`) — prediction orchestrator. Takes `EditorState`, invokes `PromptBuilder` → `LLMClient` → streams tokens. Handles cancellation, debouncing (45ms), and latency tracking (TTFT + total time).
- **SystemWidePredictor** — bridges AX context (via `AccessibilityManager`) into `CompletionController` for global prediction. Uses `CGEventTap` (instant) and 500ms idle poll (fallback). Owns `SuggestionOverlayWindowController`. Respects app gating and IME safety.
- **SessionViewModel** — bridge between UI and prediction engine. Holds `@Published` state for editor, prediction, tuning, gating, and diagnostics. Supports Playground (Lab) and System-wide modes.
- **GhostTextModifier** — SwiftUI `ViewModifier` for Typing Lab. Overlays grey/translucent ghost text.
- **SuggestionOverlayWindowController** — borderless transparent `NSWindow` at `popUpMenu` level for ghost overlay in external apps. Click-through, no focus steal.
- **PredictionHistory** — ring buffer (200 records) with full metadata per prediction.
- **Typing Lab** — permanent dev environment: live playground, diagnostics panel, prediction history, runtime prompt editing, parameter sliders, app gating panel.

---

## Design Decisions

- **LLM layer is deliberately thin.** Single `LLMClient` class handles both Ollama and llama.cpp. Process management for llama.cpp is encapsulated within `LLMClient`.
- **Ollama is the primary backend.** It solves model management, process lifecycle, loading, serving, caching, and compatibility — we leverage this rather than rebuilding infrastructure ourselves.
- **llama.cpp is secondary/experimental.** Its lifecycle complexity is internalised within `LLMClient` so it doesn't shape the app architecture.
- **Sandbox disabled** — needed for file access to GGUF directory and `Process()` spawning.
- **Non-streaming for llama.cpp** — SSE never sends a terminating event, causing hangs. Non-streaming delivers full response in one HTTP exchange.
- **Runtime tuning** — all parameters overridable via sliders. Aggression presets for quick iteration.
- **Prediction history** — every prediction (accepted/ignored/cancelled) recorded with TTFT, total time, parameters.
- **No animation** — ghost text is static overlay. No flicker, no transitions.

---

## Philosophy

Keybreeze should feel like *assisted momentum* — not autocomplete, not AI co-writing. The system biases toward restraint, brevity, timing precision, and low interruption. The user must always feel in control.

Every architectural decision serves one goal: **the user feels like they are writing better and faster, not like an AI is writing for them.**

This philosophy is guided by the detailed behavioral specifications in **[BEHAVIOR.md](./BEHAVIOR.md)** and the technical architecture in **[ARCHITECTURE.md](./ARCHITECTURE.md)**.