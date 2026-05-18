# 🧠 KEYBREEZE PROJECT BLUEPRINT: “Ghostwriter” (working name)

This document lives in the repo at `Documentation/BRIEF.md` (alongside `Documentation/PHASE-PLAN.md`). The shipping macOS target is **Keybreeze**.

## 0. Product Definition (Non-Negotiable)

A local-first macOS app that:

* Runs in the **menu bar**
* Only activates inside **Obsidian (v1)**
* Provides **inline ghost-text autocomplete**
* Uses **Tab to accept ONE word at a time**
* Runs **fully offline**
* Uses **llama.cpp + GGUF models**
* Prioritises **latency over intelligence**

### Core promise:

> Continuously predicts the next words the user was already about to type, without interrupting typing flow.

---

# 🧱 1. SYSTEM ARCHITECTURE OVERVIEW

```text id="arch1"
┌──────────────────────────────┐
│     macOS Menu Bar App       │
│ (SwiftUI / AppKit hybrid)    │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  Input Capture Layer         │
│ (Obsidian text field only)   │
│ - Accessibility API hooks    │
│ - Active window detection    │
│ - Cursor + text state        │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  Context Builder             │
│ - last N characters          │
│ - current sentence           │
│ - previous sentence          │
│ - lightweight style memory   │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  Prediction Scheduler        │
│ - debounce engine            │
│ - mid-type / pause modes     │
│ - cancellation of stale jobs │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  Inference Engine            │
│  LLMProvider (swappable)     │
│ - Ollama today (HTTP stream) │
│ - llama.cpp + GGUF (target)  │
│ - cancellable requests       │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  Post-Processor              │
│ - trims completion           │
│ - enforces word boundaries   │
│ - confidence filtering       │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  UI Overlay Layer            │
│ - inline ghost text          │
│ - no animation               │
│ - Obsidian text insertion    │
└──────────────────────────────┘
```

---

# 🧩 2. APP STRUCTURE (SWIFT PROJECT)

## Target

macOS App (Menu Bar only)

### Suggested structure:

```text
Ghostwriter/
│
├── App/
│   ├── GhostwriterApp.swift
│   ├── AppDelegate.swift
│
├── UI/
│   ├── MenuBarController.swift
│   ├── SettingsWindow.swift
│
├── Input/
│   ├── ObsidianWatcher.swift
│   ├── AccessibilityHook.swift
│   ├── TextStateTracker.swift
│
├── Core/
│   ├── ContextBuilder.swift
│   ├── PredictionScheduler.swift
│   ├── StyleMemory.swift
│
├── LLM/
│   ├── LlamaRunner.swift
│   ├── ModelLoader.swift
│   ├── PromptBuilder.swift
│
├── Rendering/
│   ├── GhostTextOverlay.swift
│   ├── TextInsertionEngine.swift
│
├── Utils/
│   ├── Debouncer.swift
│   ├── Logger.swift
│   ├── PerformanceMonitor.swift
│
└── Resources/
    ├── models/
    └── config.json
```

### Keybreeze — implemented layout (Phase 2.5)

This is the **actual** module tree in the Xcode target today (live typing, ghost text, runtime tuning):

```text
Keybreeze/
├── App/                 # KeybreezeApp, AppKit lifecycle (menu bar agent)
├── Core/                # EditorState, AppState, ModelRegistry, ContextBuilder,
│                        # PredictionMode, PredictionEngine, PredictionScheduler
├── LLM/                 # LLMProvider, OllamaLLMService, OllamaConfiguration,
│                        # OllamaModelCatalog, PromptBuilder
├── UI/                  # MenuBarContentView, PredictionSessionViewModel
└── Utils/               # WordLimiter, Debouncer, KeybreezeLatencyLogger
```

**Model control:** `ModelRegistry` lists available local models (display name + Ollama tag + per-model `maxWords`). `AppState.selectedModel` drives the next request. **Latency:** each run logs TTFT and total wall time under `[KeybreezeLatency]` for later tuning. **Ghost text:** rendered as an overlay on a plain-style TextField inside the menu bar window. **Runtime tuning:** sliders for verbosity, continuation strictness, and instruction adherence override model presets on the fly.

---

# ⚙️ 3. INPUT CAPTURE LAYER (OBSIDIAN ONLY)

## Goal:

Extract text + cursor position from Obsidian editor.

### Approach:

Use:

* macOS Accessibility API (`AXUIElement`)
* Focus detection (frontmost app = Obsidian)
* Text field extraction

### Rules:

* Only activate if:

```text
frontmostApp == "Obsidian"
```

* Only track:

  * active text area
  * caret position
  * current line + paragraph

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

This is where “feel” is created.

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

This is the “heartbeat system”.

### Responsibilities:

* debounce keystrokes
* cancel stale requests
* manage mid-typing vs pause prediction modes

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

# 🧠 6. LLM ENGINE (llama.cpp)

## Integration:

Use:

* GGUF model
* streaming token output

### Model choice:

Start with:

* Gemma 4 E2B (quantized 4-bit)

Fallback tests:

* Qwen small
* Phi small

---

## Prompt format:

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

* if < 0.25 confidence → discard
* if repeats input → discard
* if too long → cut at last full word

---

# 🪄 8. GHOST TEXT RENDERING

## Implementation:

Overlay inside Obsidian editor.

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

# ⌨️ 9. TAB ACCEPT ENGINE

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

# 🧠 10. STYLE MEMORY (LIGHTWEIGHT v1)

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

# 🧭 13. OBISIDIAN-FIRST STRATEGY

Why this matters:

Obsidian gives you:

* stable text area
* markdown consistency
* predictable DOM
* fewer edge cases

This is your **training ground for UX perfection**

---

# 🌐 FUTURE EXTENSION: GOOGLE DOCS

Yes — this is absolutely extendable.

But important truth:

## Google Docs is HARD MODE

You’ll need:

* Chrome extension
* DOM mutation tracking
* iframe handling
* contenteditable hacks
* race condition protection

So:

### Phase strategy:

1. Obsidian (native macOS app)
2. VSCode / Scrivener (maybe)
3. Brave browser extension
4. Google Docs extension (last)

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