# Keybreeze — Build Plan

*Phased delivery. Each phase must be working before the next begins.*

---

## Phase 0 — Project Skeleton ✅
**Goal:** Running macOS menu bar app with stable lifecycle.
- SwiftUI + AppKit hybrid, `MenuBarExtra` (window style), shared `AppState`
- ✅ Launches reliably, no crashes, menu bar exists

---

## Phase 1 — LLM Pipeline ✅
**Goal:** Send context → get text back locally in <200–500ms.
- **Ollama:** `LLMProvider` protocol, `OllamaLLMService` (SSE `/api/generate`), `OllamaModelCatalog`
- **llama.cpp:** `LlamaCppService` (non-streaming `POST /completion`), `LlamaCppModelCatalog` (GGUF directory scanner), `LlamaCppProcessManager` (auto-launch/kill)
- **PromptBuilder:** `EditorState` → continuation prompt, model word cap
- **ModelRegistry/ModelOption:** display name, `ollamaId`/`ggufPath`, per-model presets (verbosity, strictness, temperature, etc.)
- **Backend switching:** segmented control, auto lifecycle management
- **KeybreezeLatencyLogger:** `[KeybreezeLatency]` blocks per prediction

---

## Phase 2 — Prediction Engine ✅
**Goal:** Turn LLM into a prediction service.
- `PredictionScheduler` — debounced loop: midType (150ms) / pause (450ms), cancels stale jobs
- `ContextBuilder` — trims to ~800 chars
- `PredictionEngine` — single stream, word cap, cooperative cancellation, runtime prompt passthrough
- Two-mode prediction: midType (fast, short) / pause (higher confidence, longer)

---

## Phase 2.5 — Ghost Text Harness + Tuning ✅
**Goal:** Validate presentation and feel inside the app before external editors.
- Inline ghost overlay: low-opacity continuation inside the live typing field
- Runtime tuning: verbosityBias, continuationBias, instructionStrictness, maxWords sliders
- Status line showing active mode with live indicator
- Phase 1 one-shot test harness removed

---

## Typing Lab / Feel Engineering ✅
**Goal:** Permanent internal dev environment for feel iteration.
- **Components:** Playground (multi-line + ghost, compact toggle), Diagnostics (real-time metrics grid), History (200-record ring buffer, filterable), Prompt Editor (system/continuation overrides), Parameter Controls (temperature, topP, repeatPenalty, confidence, biases, maxWords), Aggression Presets (Conservative/Balanced/Aggressive)
- **ShadowPredictor:** silent background predictions for quality evaluation
- **Architecture:** engine fully decoupled from UI; Typing Lab is a client, not part of the engine

---

## Phase 3 — Obsidian Integration 🔜 Next
**Goal:** Inject ghost text into Obsidian. Reuse engine, scheduler, and overlay patterns.
- App detection (only active when Obsidian is frontmost)
- Accessibility hook (`AXUIElement`) for text + cursor
- Overlay system for inline ghost text
- No inference rework needed — engine is backend-agnostic

---

## Phase 4 — Tab Accept System
- Tab inserts one word only; updates suggestion buffer
- Muscle memory emerges; typing feels "assisted but controlled"

---

## Phase 5+ — Polish, Style Memory, Expansion
- Latency refinement, confidence filtering, suggestion rhythm
- Lightweight style memory (phrase bias, cadence adaptation — no training)
- Brave extension, Scrivener support, Google Docs (hard mode)

---

## Key Architecture Principle

> The prediction engine must never depend on UI.
- UI can crash → engine continues
- Engine can restart → UI survives
- Prediction is stateless where possible

---

## Design Notes

- **Sandbox disabled** — required for GGUF file access and `llama-server` process spawning.
- **Non-streaming for llama.cpp** — SSE has no terminating event, causing hangs. Non-streaming delivers full response in one HTTP exchange.
- **PromptBuilder** produces strict continuation prompts (not chat). System/continuation prompts overridable at runtime.
- **ModelOption** carries runtime parameters, not just metadata. `ggufPath` for GGUF models, `ollamaId` for Ollama.