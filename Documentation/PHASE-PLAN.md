# 🧭 KEYBREEZE BUILD PLAN (PHASED + STRICT DEPENDENCY ORDER)

This file lives in the repo at `Documentation/PHASE-PLAN.md` (see also `Documentation/BRIEF.md` and `Documentation/ARCHITECTURE.md`).

You're building in layers. Each phase must be *fully working* before the next exists.

Think:

> "Can I trust this layer alone before adding intelligence?"

---

# 🧱 PHASE 0 — PROJECT SKELETON (NO AI YET)

## Goal:

A running macOS menu bar app with stable lifecycle and a place to hang shared app state.

### Deliverables:

* macOS menu bar app ("Keybreeze")
* SwiftUI + AppKit hybrid (activation policy for agent-style menu bar)
* minimal in-app surface (Phase 1 adds the test harness UI)
* logs working
* no Obsidian integration yet
* no LLM yet

---

## What gets built:

### App container

* SwiftUI + AppKit hybrid
* Menu bar icon
* Shared `AppState` (model selection and future toggles)

### Core scaffolding:

```text
KeybreezeApp
├── MenuBarExtra (window style)
├── AppState
└── (dedicated Settings window — deferred)
```

---

## Success criteria:

* App launches reliably
* No crashes
* Menu bar exists
* Shared state object exists for later phases

**Status: complete.**

---

# ⚙️ PHASE 1 — LLM PIPELINE (NO UI INJECTION YET)

## Goal:

Prove you can:

> send context → get text back locally in <200–500ms

This is your **engine validation phase**

---

## Deliverables:

### 1. Local inference (Ollama first)

* **Ollama** HTTP streaming (`/api/generate`) for rapid UX iteration
* **`LLMProvider`** protocol: per-request `model` string, streaming `onToken`, cooperative `cancel()`
* **`OllamaLLMService`**: implements `LLMProvider`; model id is **not** hardcoded in the client (passed each call)
* **llama.cpp** remains the long-term target behind the same `LLMProvider` boundary

### 2. Prompt + model catalog

* **`PromptBuilder`**: `EditorState` → continuation prompt only (word cap passed in from caller / model)
* **`ModelRegistry`**: static list of `ModelOption` (display name, `ollamaId`, `maxWords`)
* **`AppState.selectedModel`**: runtime selection (not persisted yet); minimal menu picker in the menu bar UI

### 3. Test harness + observability

* button: **"Test Prediction"**
* streamed output in-window + `print` for tokens
* **`KeybreezeLatencyLogger`**: structured console block `[KeybreezeLatency]` with `model`, `timeToFirstToken`, `totalTime` per request

---

## Output format:

```text
Input:
"The room was silent and he noticed tha"

Output:
"the light flickering in the hallway"
```

---

## Success criteria:

* Ollama runs locally (with matching `ollama pull` tags for registry ids)
* Stable streaming + clean cancellation
* Model switch applies to the **next** request immediately
* Latency lines visible in Xcode / Console for TTFT and total time
* No ghost overlay and no Obsidian hooks yet

**Status: complete.** The one-shot test harness has been removed in Phase 2.5; the pattern is subsumed by the Typing Lab.

---

## IMPORTANT:

We do NOT optimize yet.

We just confirm:

> "This engine works and is fast enough."

Phase 1 intentionally establishes **model-controlled prediction plumbing** (`LLMProvider` + registry + `AppState`) so Phase 2+ can add schedulers and injection without rewiring inference.

---

# 🧠 PHASE 2 — PREDICTION ENGINE (STILL NO OBSIDIAN)

## Goal:

Turn LLM into a **prediction service**

This is where Keybreeze becomes real.

---

## Deliverables:

### Core system:

```text
PredictionScheduler
ContextBuilder
PredictionEngine
```

---

## Features:

### 1. Debounced prediction loop

* keystroke triggers prediction job
* cancels stale jobs

### 2. Two modes:

* mid-type (fast)
* pause (slightly longer)

### 3. Output processing:

* trim to 2–12 words
* word boundary enforcement

---

## Success criteria:

* predictions update continuously
* no lag spikes
* system feels "alive" in logs

**Status: complete.** `PredictionScheduler`, `ContextBuilder`, `PredictionEngine`, and the live typing harness in the menu bar window are implemented. Cancellation of superseded midType jobs is expected; logs treat URLSession `-999` as silent cancel.

---

# 👻 PHASE 2.5 — GHOST TEXT HARNESS + TUNING (COMPLETE)

## Goal:

Validate **presentation and feel** inside the menu bar app before Obsidian. Same engine; new overlay and controls.

This de-risks the ghost text leap — Obsidian becomes an input swap, not a combined "first ghost text + first external app" jump.

---

## Deliverables:

### 1. Inline ghost text (harness)

* render suggestion as low-opacity continuation **inside the live typing field**
* updates with scheduler output; clears on keystroke
* no flicker; matches field font

### 2. Runtime tuning controls (in-window, not Settings yet)

* sliders or steppers for **`verbosityBias`**, **`continuationBias`**, **`instructionStrictness`**
* optional: `maxWords` override
* changes apply to the **next** prediction immediately

### 3. Observability

* keep `[KeybreezeLatency]` for completed runs
* status line shows active mode (midType / pause) with live indicator
* console logs live suggestion text at debug level
* model selection logged when changed

### 4. Cleanup

* Phase 1 one-shot test harness removed (subsumed by Typing Lab)
* `PredictionTestViewModel` no longer used

---

## Success criteria:

* ghost text feels natural while typing in the harness
* tuning sliders visibly change suggestion style
* Tab accept **not required yet** (deferred)
* no Obsidian or Accessibility hooks yet

**Status: complete.**

---

# 🔬 PHASE: TYPING LAB / FEEL ENGINEERING (IMPLEMENTED)

## Why This Phase Exists

Keybreeze is NOT primarily an app integration project.

It is a **real-time typing cognition and prediction engine**.

The central challenge is not Obsidian integration, Accessibility APIs, overlays, or ghost text rendering.

The central challenge is:

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

**External app integration is an interface problem. Typing feel is the product. The engine experience must be solved first.**

---

## What the Typing Lab Is

The menu bar harness is no longer a temporary test window.

It is now a **permanent internal development environment** called the **Typing Lab**.

The Typing Lab becomes a core part of the application architecture and remains useful even after external integrations ship. It is a controlled environment for rapidly iterating on:

* latency
* prompt design
* model behaviour
* cancellation logic
* prediction cadence
* ghost text rhythm
* acceptance flow
* continuation quality
* confidence heuristics
* editing behaviour
* responsiveness under live typing

---

## Files Built

```
Keybreeze/UI/TypingLab/
├── TypingLabRootView.swift        # Main container (3-tab: Playground/Diagnostics/History)
├── DiagnosticsPanelView.swift     # Live metrics grid
├── ParameterControlsView.swift    # Runtime sliders (temperature, topP, penalties, biases)
├── PromptEditorView.swift         # Runtime prompt text editing
└── PredictionHistoryView.swift    # Scrolling timeline with filter

Keybreeze/Core/
├── PredictionHistory.swift        # PredictionRecord struct + ring buffer
└── ShadowPredictor.swift          # Invisible prediction mode
```

---

## Deliverables

### 1. Persistent Typing Playground ✅

Multi-line editor inside the app with ghost overlay. Supports long-form typing, rapid edits, cursor movement, mid-sentence editing, deletions. Toggleable between compact mode (simple playground) and full Typing Lab (diagnostics, params, prompts, presets, history).

**File:** `TypingLabRootView.swift`, `MenuBarContentView.swift`

### 2. Live Engine Diagnostics Panel ✅

Real-time grid showing: model name, active mode (midType/pause), average TTFT, average total time, cancellation count, accepted count, ignored count, acceptance rate, context size, prediction word count.

**File:** `DiagnosticsPanelView.swift`

### 3. Prediction History / Replay System ✅

Ring buffer of up to 200 prediction records. Each record stores: typed context, generated continuation, TTFT, total time, resolution (accepted/ignored/cancelled/invalidated/rejected), model used, mode, generation parameters. Accepts filter by resolution.

**File:** `PredictionHistory.swift`, `PredictionHistoryView.swift`

### 4. Runtime Prompt Editing ✅

System prompt and continuation prompt overrides editable at runtime. Empty overrides = use built-in `PromptBuilder` defaults. No rebuild required. Changes apply to the next prediction immediately.

**File:** `PromptEditorView.swift`, `PromptBuilder.swift` (extended), `PredictionEngine.swift` (extended)

### 5. Runtime Model Parameter Controls ✅

Live sliders for: temperature (0.0–1.5), top-P (0.0–1.0), repeat penalty (0.5–2.0), confidence threshold (0.0–1.0), verbosity bias (0.0–1.0), continuation bias (0.0–1.0), instruction strictness (0.0–1.0), and max words picker (2–20 or model default).

**File:** `ParameterControlsView.swift`

### 6. Aggression / Behaviour Presets ✅

Three UX-facing presets: **Conservative** (short predictions, high confidence, low temperature), **Balanced** (moderate), **Aggressive** (longer predictions, low confidence, high temperature). Selecting a preset applies all parameter changes and enables tuning mode.

**File:** `PredictionSessionViewModel.swift` (AggressionPreset enum + applyPreset method)

### 7. Thinking Suppression ⚠️

Declared as design principle. Explicitly disable reasoning/thinking modes at the Ollama API level still TBD (depends on model-specific API flags). The principle is documented.

### 8. Shadow Prediction Mode ✅

`ShadowPredictor` runs invisible predictions on keystroke. Compares generated predictions against actual user typing. Gathers evaluation data without UX interference. Callback delivers (context, continuation, TTFT, totalTime, mode) for recording.

**File:** `ShadowPredictor.swift`

### 9. Editing Stability Requirements ⚠️

Architecture supports stable editing behaviour (cursor movement doesn't crash, backspace triggers prediction recalculation). Multi-line editor with ghost overlay is stable during rapid edits. Further tuning of prediction behaviour during non-linear editing is ongoing.

---

## Architecture Clarification

The prediction engine remains **fully decoupled** from:

* overlays
* accessibility APIs
* app integrations
* rendering systems

The Typing Lab UI is a **client of the engine**, not part of the engine itself.

This preserves:

* stability
* debuggability
* portability
* future cross-app expansion

---

## Implementation Details

### Core changes

- `ModelOption` extended with `temperature`, `topP`, `repeatPenalty`, `confidenceThreshold`
- `PromptBuilder.continuationPrompt()` accepts optional `customSystemPrompt` and `customContinuationPrompt` overrides
- `PredictionEngine.predict()` passes custom prompts through to `PromptBuilder`
- `PredictionScheduler` has `updatePromptOverrides()` closure for runtime prompt wiring

### ViewModel

- `PredictionSessionViewModel` now owns: runtime model parameters, custom prompt strings, `AggressionPreset` selection, `PredictionHistory` ring buffer, `recordPrediction()` method, `applyPreset()` mapping function
- Prompt overrides wired via `scheduler.updatePromptOverrides { (customSystemPrompt, customContinuationPrompt) }`

### UI

- `MenuBarContentView` completely redesigned: header with engine status indicator, model selector, "Expand" toggle for compact vs full Typing Lab, compact playground retains ghost overlay
- `TypingLabRootView` has segmented tab bar (Playground, Diagnostics, History) and toggleable section buttons (Diag, Params, Prompts) in footer

---

## Success Criteria

- ✅ Typing playground supports real editing behaviour (backspace, cursor movement, mid-sentence edits) without prediction instability
- ✅ Diagnostics panel provides actionable data on latency, acceptance rate, and failure modes
- ✅ Prediction history enables identification of recurring failure patterns
- ✅ Runtime prompt editing enables prompt iteration without rebuilds
- ✅ Runtime parameter controls directly influence prediction feel
- ✅ Presets produce meaningfully different suggestion behaviour
- ✅ Shadow prediction provides quantifiable prediction quality metrics
- ⚠️ Editing stability under all non-linear patterns — ongoing tuning

---

## Strategic Note

The Typing Lab may ultimately become one of the most important parts of the entire project because it enables rapid iteration on the core writing experience without external integration friction.

Without this environment, iteration speed slows dramatically and UX progress becomes harder to measure.

---

# ✍️ PHASE 3 — OBSIDIAN INTEGRATION (NEXT)

## Goal:

Inject ghost text into Obsidian ONLY — reusing the engine, scheduler, and overlay patterns proven and refined in the Typing Lab.

This is where it becomes a product.

---

## Deliverables:

### 1. App detection

* only activate when Obsidian is frontmost

### 2. Accessibility hook

* read editor text
* get cursor position

### 3. Overlay system

* render ghost text inline

---

## Behaviour:

```text
User types: "The night was"

Ghost:      "quiet except for distant wind"
```

---

## Success criteria:

* ghost text appears
* updates in real time
* disappears when not confident
* does NOT interfere with typing

---

## Why This Phase Is Later Now

The typing experience itself is now recognised as the primary product risk and primary product differentiator.

External integrations are implementation layers built on top of a solved interaction engine.

---

# ⌨️ PHASE 4 — TAB ACCEPT SYSTEM

## Goal:

Make interaction feel magical.

---

## Deliverables:

* intercept Tab key
* insert ONE word only
* update suggestion buffer
* maintain continuity

---

## Key rule:

> Tab never inserts full sentences

Only word-by-word flow.

---

## Success criteria:

* muscle memory emerges
* typing feels "assisted but controlled"

---

# 🧩 PHASE 5 — POLISH LOOP (CONTINUOUS)

Now we tune:

### Improve:

* latency
* confidence filtering
* suggestion rhythm
* stability vs creativity balance

### Add:

* backspace correction mode
* silent failure handling
* prediction smoothing

---

## Success criteria:

> You stop noticing the tool — only the flow remains.

---

# 🧠 PHASE 6 — STYLE MEMORY (YOU SAID LATER — CORRECT)

Only after system is stable:

* lightweight phrase memory
* vocabulary biasing
* cadence adaptation

NO training, only memory bias.

---

# 🌐 PHASE 7 — EXPANSION LAYERS (IGNORE FOR NOW)

Only once Obsidian version is perfect:

* Brave extension
* Scrivener support
* Google Docs extension (hard mode)
* cross-app accessibility layer

---

# 🧭 KEY ARCHITECTURE PRINCIPLE

This is the most important thing in the entire system:

> The prediction engine must never depend on UI.

Meaning:

* UI can crash → engine continues
* engine can restart → UI survives
* prediction is stateless where possible

This keeps everything stable and debuggable.

---

# ⚡ WHY THIS ORDER WORKS

You are building in decreasing uncertainty order:

1. App exists (no AI risk) — ✅
2. AI works (no UI risk) — ✅
3. prediction logic works (no integration risk) — ✅
4. ghost text + tuning work in harness (no external app risk) — ✅
5. **Typing Lab tunes feel engineering (no integration complexity)** — ✅
6. Obsidian hook works (no interaction risk) — 🔜 NEXT
7. UX refinement (no structural risk) — later
8. style learning (highest complexity last) — last

This avoids the classic failure mode:

> "Beautiful AI demo that collapses when integrated."

---

# 🎯 FINAL STRATEGIC PRINCIPLE

Keybreeze succeeds or fails based on **whether typing feels better**.

Not whether predictions are technically impressive.

The project goal is not:

> "Generate intelligent text."

The project goal is:

> **"Create uninterrupted writing flow."**

---

# 📚 Philosophy Statement

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