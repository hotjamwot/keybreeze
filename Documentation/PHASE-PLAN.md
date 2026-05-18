# 🧭 KEYBREEZE BUILD PLAN (PHASED + STRICT DEPENDENCY ORDER)

This file lives in the repo at `Documentation/PHASE-PLAN.md` (see also `Documentation/BRIEF.md`).

You’re building in layers. Each phase must be *fully working* before the next exists.

Think:

> “Can I trust this layer alone before adding intelligence?”

---

# 🧱 PHASE 0 — PROJECT SKELETON (NO AI YET)

## Goal:

A running macOS menu bar app with stable lifecycle and a place to hang shared app state.

### Deliverables:

* macOS menu bar app (“Keybreeze”)
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

* button: **“Test Prediction”**
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

**Status: complete.** The one-shot test harness has been removed in Phase 2.5; the pattern is subsumed by the live typing harness.

---

## IMPORTANT:

We do NOT optimize yet.

We just confirm:

> “This engine works and is fast enough.”

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
* system feels “alive” in logs

**Status: complete.** `PredictionScheduler`, `ContextBuilder`, `PredictionEngine`, and the live typing harness in the menu bar window are implemented. Cancellation of superseded midType jobs is expected; logs treat URLSession `-999` as silent cancel.

---

# 👻 PHASE 2.5 — GHOST TEXT HARNESS + TUNING (COMPLETE)

## Goal:

Validate **presentation and feel** inside the menu bar app before Obsidian. Same engine; new overlay and controls.

This de-risks Phase 3 — Obsidian becomes an input swap, not a combined “first ghost text + first external app” leap.

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

* Phase 1 one-shot test harness removed (subsumed by live typing)
* `PredictionTestViewModel` no longer used

---

## Success criteria:

* ghost text feels natural while typing in the harness
* tuning sliders visibly change suggestion style
* Tab accept **not required yet** (Phase 4)
* no Obsidian or Accessibility hooks yet

**Status: complete.**

---

# ✍️ PHASE 3 — OBSIDIAN INTEGRATION

## Goal:

Inject ghost text into Obsidian ONLY — reusing the engine, scheduler, and overlay patterns proven in Phase 2.5.

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
* typing feels “assisted but controlled”

---

# 🧩 PHASE 5 — POLISH LOOP (FEEL ENGINEERING)

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

1. App exists (no AI risk)
2. AI works (no UI risk)
3. prediction logic works (no integration risk)
4. ghost text + tuning work in harness (no external app risk)
5. Obsidian hook works (no interaction risk)
6. UX refinement (no structural risk)
7. style learning (highest complexity last)

This avoids the classic failure mode:

> “beautiful AI demo that collapses when integrated”