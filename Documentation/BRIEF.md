# 🧠 KEYBREEZE PROJECT BRIEF: Typing Cognition Engine

This document lives in the repo at `Documentation/BRIEF.md` (alongside `Documentation/PHASE-PLAN.md` and `Documentation/ARCHITECTURE.md`). The shipping macOS target is **Keybreeze**.

## 0. Product Definition (Non-Negotiable)

A local-first macOS app that:

* Runs in the **menu bar**
* Provides **inline ghost-text continuation** inside supported editors
* Uses **Tab to accept ONE word at a time**
* Runs **fully offline**
* Uses **Ollama (and eventually llama.cpp + GGUF models)**
* Prioritises **latency and feel over raw intelligence**

### Core promise:

> Continuously predicts the next words the user was already about to type, without interrupting typing flow.

### What Keybreeze is NOT:

Keybreeze is NOT primarily an app integration project.

It is a **real-time typing cognition and prediction engine**.

The central challenge is not Obsidian integration, Accessibility APIs, overlays, or ghost text rendering. The central challenge is:

* prediction timing
* cancellation behaviour
* text cadence
* responsiveness
* latency stability
* interruption handling
* confidence gating
* continuation quality
* live editing behaviour
* suggestion restraint
* acceptance psychology
* typing flow

The app must feel invisible, fluid, and trustworthy.

The user should feel:

> "I am writing better and faster"
> NOT:
> "An AI is trying to write for me."

---

## 0.5 Strategic Principle

**External app integration is an interface problem. Typing feel is the product. The engine experience must be solved first.**

Keybreeze succeeds or fails based on **whether typing feels better**. Not whether predictions are technically impressive.

The project goal is not:

> "Generate intelligent text."

The project goal is:

> **"Create uninterrupted writing flow."**

---

# 🧱 1. SYSTEM ARCHITECTURE OVERVIEW

```text id="arch1"
┌──────────────────────────────────┐
│      macOS Menu Bar App          │
│  (SwiftUI / AppKit hybrid)       │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  ┌────────────────────────────┐  │
│  │      TYPING LAB            │  │
│  │  (Permanent Dev Env)       │  │
│  │  - Typing Playground       │  │
│  │  - Diagnostics Panel       │  │
│  │  - Prediction History      │  │
│  │  - Runtime Prompt Editing  │  │
│  │  - Model Params Controls   │  │
│  │  - Behaviour Presets       │  │
│  │  - Shadow Prediction Mode  │  │
│  └────────────────────────────┘  │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Input Capture Layer             │
│  (Supported editor text fields)  │
│  - Accessibility API hooks       │
│  - Active window detection       │
│  - Cursor + text state           │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Context Builder                 │
│  - last N characters             │
│  - current sentence              │
│  - previous sentence             │
│  - lightweight style memory      │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Prediction Scheduler            │
│  - debounce engine               │
│  - mid-type / pause modes        │
│  - cancellation of stale jobs    │
│  - runtime prompt overrides      │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Inference Engine                │
│  LLMProvider (swappable)         │
│  - Ollama today (HTTP stream)    │
│  - llama.cpp + GGUF (target)     │
│  - cancellable requests          │
│  - custom prompt passthrough     │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Post-Processor                  │
│  - trims completion              │
│  - enforces word boundaries      │
│  - confidence filtering          │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  UI Overlay Layer                │
│  - inline ghost text             │
│  - no animation                  │
│  - text insertion via Tab        │
└──────────────────────────────────┘
```

---

# 🧩 2. APP STRUCTURE (SWIFT PROJECT)

## Target

macOS App (Menu Bar only)

### Current implementation layout (after Typing Lab phase):

```text
Keybreeze/
├── App/                          # KeybreezeApp, AppKit lifecycle (menu bar agent)
│   ├── KeybreezeApp.swift
│   └── AppKitLifecycle.swift
│
├── Core/                         # Engine: state, prediction, context, history, shadow mode
│   ├── AppState.swift
│   ├── EditorState.swift
│   ├── ModelRegistry.swift
│   ├── ContextBuilder.swift
│   ├── PredictionMode.swift
│   ├── PredictionEngine.swift
│   ├── PredictionScheduler.swift
│   ├── PredictionHistory.swift       # 🆕 Ring buffer + record struct
│   └── ShadowPredictor.swift         # 🆕 Invisible prediction mode
│
├── LLM/                          # Inference abstractions + Ollama HTTP client
│   ├── LLMProvider.swift
│   ├── OllamaLLMService.swift
│   ├── OllamaConfiguration.swift
│   ├── OllamaModelCatalog.swift
│   └── PromptBuilder.swift           # Extended with custom prompt overrides
│
├── UI/                           # SwiftUI views
│   ├── MenuBarContentView.swift      # Redesigned with Typing Lab toggle
│   ├── PredictionTestViewModel.swift
│   ├── PredictionSessionViewModel.swift  # Extended: params, presets, history
│   └── TypingLab/                    # 🆕 Permanent internal dev environment
│       ├── TypingLabRootView.swift
│       ├── DiagnosticsPanelView.swift
│       ├── ParameterControlsView.swift
│       ├── PromptEditorView.swift
│       └── PredictionHistoryView.swift
│
├── Utils/
│   ├── WordLimiter.swift
│   ├── KeybreezeLatencyLogger.swift
│   └── Debouncer.swift
│
└── Resources/
    ├── Assets.xcassets
    └── Keybreeze.entitlements
```

**Model control:** `ModelRegistry` lists available local models (display name + Ollama tag + per-model `maxWords`). `AppState.selectedModel` drives the next request. **Runtime parameters:** `ModelOption` now includes `temperature`, `topP`, `repeatPenalty`, `confidenceThreshold` with sensible defaults. **Latency:** each run logs TTFT and total wall time under `[KeybreezeLatency]` for later tuning. **Ghost text:** rendered as an overlay on a plain-style TextField inside the menu bar window. **Runtime tuning:** sliders for verbosity, continuation strictness, instruction adherence, temperature, top-P, repeat penalty, and confidence threshold. **Aggression presets:** Conservative, Balanced, Aggressive modes. **Prediction history:** ring buffer with timeline UI and filter. **Shadow prediction:** invisible background predictions for quality evaluation. **Runtime prompt editing:** editable system and continuation prompts at runtime.

---

# 🔬 2A. TYPING LAB (PERMANENT DEVELOPMENT ENVIRONMENT) — IMPLEMENTED

## Purpose

The Typing Lab is a controlled environment for rapidly iterating on the core typing experience without external integration friction. It replaces the temporary test harness concept and becomes a permanent fixture in the application.

## Components (all implemented)

### 1. Persistent Typing Playground ✅

Multi-line editor with ghost overlay. Supports long-form typing, rapid edits, cursor movement, mid-sentence editing, deletions, punctuation handling. Toggleable between compact mode and full Typing Lab.

### 2. Live Engine Diagnostics Panel ✅

Real-time metrics: model, mode (midType/pause), average TTFT, average total time, cancellation count, accepted/ignored counts, acceptance rate, context size, prediction word count.

### 3. Prediction History / Replay System ✅

Ring buffer (max 200 records) with: typed context, generated continuation, TTFT, total time, resolution (accepted/ignored/cancelled/invalidated/rejected), model, mode, parameters. Scrolling timeline UI with resolution filter.

### 4. Runtime Prompt Editing ✅

System and continuation prompts editable at runtime. Empty overrides = use built-in defaults. No rebuild required.

### 5. Runtime Model Parameter Controls ✅

Live sliders: temperature (0.0–1.5), top-P (0.0–1.0), repeat penalty (0.5–2.0), confidence threshold (0.0–1.0), verbosity bias (0.0–1.0), continuation bias (0.0–1.0), instruction strictness (0.0–1.0), max words (2–20 or model default).

### 6. Aggression / Behaviour Presets ✅

Three modes: Conservative (restrained), Balanced (moderate), Aggressive (speculative). Each preset adjusts all parameters.

### 7. Thinking Suppression ⚠️

Declared as design principle. Ollama API-level thinking suppression TBD.

### 8. Shadow Prediction Mode ✅

`ShadowPredictor` runs invisible predictions. Compares against actual user typing for quality evaluation without UX interference.

### 9. Editing Stability Requirements ⚠️

Architecture supports stable editing. Non-linear editing patterns are being tuned.

## Architecture Clarification

The prediction engine remains fully decoupled from overlays, accessibility APIs, app integrations, and rendering systems. The Typing Lab UI is a client of the engine, not part of the engine itself.

---

# ⚙️ 3. INPUT CAPTURE LAYER (DEFERRED — PHASE 3)

## Goal:

Extract text + cursor position from supported editors.

### Approach:

Use:

* macOS Accessibility API (`AXUIElement`)
* Focus detection (frontmost app = supported editor)
* Text field extraction

### Rules:

* Only activate if frontmost app is a supported editor (e.g. Obsidian)
* Only track active text area, caret position, current line + paragraph

### Output:

```swift id="input1"
struct EditorState {
    let fullText: String
    let cursorIndex: Int
    let currentLine: String
    let previousLine: String
}
```

---

# 🧠 4. CONTEXT BUILDER (CRITICAL)

This is where "feel" is created.

### Input:

EditorState

### Output:

LLM prompt context

### Rules:

Only include:

* last ~300–800 characters max
* current sentence
* previous sentence
* optional heading context

### Example:

```text id="ctx1"
Context:
You are completing text written by a novelist.

Text:
"...the room was quiet except for the hum of the heater. He turned and noticed tha"
```

---

# ⚡ 5. PREDICTION SCHEDULER (VERY IMPORTANT)

This is the "heartbeat system".

### Responsibilities:

* debounce keystrokes
* cancel stale requests
* manage mid-typing vs pause prediction modes
* support runtime prompt overrides

---

## Modes:

### A. Mid-type mode (fast, reactive)

Triggered every:

* 120–200ms after keystroke

Rules:

* short predictions
* low latency priority
* allow partial instability

---

### B. Pause mode (high confidence)

Triggered after:

* 300–600ms silence

Rules:

* longer predictions (5–12 words)
* higher confidence threshold

---

## Implementation logic:

```text id="sched1"
onKeyPress():
    cancel previous prediction job
    schedule new prediction job (120ms debounce)

onPauseDetected():
    trigger high-confidence prediction
```

---

# 🧠 6. LLM ENGINE

## Integration:

Use:

* Ollama HTTP streaming (`/api/generate`) for rapid UX iteration
* **llama.cpp + GGUF** remains the long-term target behind the same `LLMProvider` boundary

### Model choice:

Start with:

* Gemma 4 E2B (quantized 4-bit) via Ollama

Fallback tests:

* Qwen small
* Phi small

---

## Prompt format (default):

```text id="prompt1"
You are a predictive writing assistant.

Continue the text naturally in the same style.

Rules:
- Do not be verbose
- Output only continuation text
- 2–12 words ideal

Text:
{context}
```

Prompt format is overridable at runtime via the Typing Lab's Prompt Editor.

---

## Output handling:

* stream tokens
* stop on punctuation OR word limit
* enforce word boundary trimming

---

# ✂️ 7. POST PROCESSOR

### Responsibilities:

* enforce max 12 words
* ensure clean word boundaries
* strip hallucinated formatting
* reject low-confidence outputs

---

## Rule set:

* if < `confidenceThreshold` confidence → discard
* if repeats input → discard
* if too long → cut at last full word

---

# 🪄 8. GHOST TEXT RENDERING

## Implementation:

Overlay inside supported editor text field.

### Requirements:

* inline rendering only
* no flicker
* no animation
* matches font exactly

### Behaviour:

```text id="ui1"
User types:
"The forest was"

Ghost:
"silent except for distant birds"
```

Rendered as low-opacity inline text.

---

# ⌨️ 9. TAB ACCEPT ENGINE (DEFERRED — PHASE 4)

## Rule:

* Tab inserts ONLY next word
* updates suggestion buffer

Example:

```text id="tab1"
Ghost: "slowly across the valley"

Tab →
insert: "slowly"

Remaining:
"across the valley"
```

---

# 🧠 10. STYLE MEMORY (LIGHTWEIGHT v1 — DEFERRED)

Store:

```json id="style1"
{
  "common_words": [],
  "names": [],
  "phrases": [],
  "avg_sentence_length": 0
}
```

Use only to bias:

* vocabulary selection
* tone consistency

NOT full training.

---

# 🚨 11. FAILURE MODE DESIGN

If anything fails:

* show nothing
* do not interrupt typing
* silently retry later

No error UI.

No logs in production UI.

---

# ⚡ 12. PERFORMANCE TARGETS

Critical:

* keystroke → UI update: <10ms
* prediction scheduling: <50ms overhead
* inference start: <100ms perceived
* total latency goal: 30–60ms feel

---

# 🧭 13. OBSIDIAN-FIRST STRATEGY (NOW LATER IN ROADMAP)

## Why Obsidian Still Matters

Obsidian gives you:

* stable text area
* markdown consistency
* predictable interaction model
* fewer edge cases

## Why It Moves Later

The typing experience itself is now recognised as the primary product risk and primary product differentiator. External integrations are implementation layers built on top of a solved interaction engine.

---

# 🌐 FUTURE EXTENSION: EXPANSION

Yes — Keybreeze is absolutely extendable.

## Phase strategy:

1. **Typing Lab** — feel engineering, prompt tuning, diagnostics — ✅ IMPLEMENTED
2. Obsidian (native macOS app) — 🔜 NEXT
3. VSCode / Scrivener (maybe)
4. Brave browser extension
5. Google Docs extension (last — hard mode)

The core engine stays identical:

> Input → Context → LLM → Overlay → Tab engine

Only input/output layer changes.

---

# 🧩 FINAL SUMMARY (WHAT YOU ARE ACTUALLY BUILDING)

You are building:

> A real-time predictive language layer that sits between thought and text entry, optimized for creative flow.

Not AI writing.

Not autocomplete.

But:

> cognitive acceleration through anticipatory language completion.

---

# 📚 PHILOSOPHY STATEMENT

Keybreeze should feel like:

* assisted momentum
* cognitive flow support
* lightweight continuation
* invisible collaboration

NOT:

* autocomplete spam
* sentence hijacking
* intrusive co-writing
* aggressive AI authorship

The system should bias toward:

* restraint
* brevity
* timing precision
* confidence
* low interruption

The user must always feel in control.

Every architectural decision, every tuning parameter, every scheduling heuristic — all serve one master goal: **the user feels like they are writing better and faster, not like an AI is writing for them.**