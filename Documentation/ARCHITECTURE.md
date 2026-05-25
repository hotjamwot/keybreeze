# Keybreeze — Architecture
Last updated: 25 May 2026

*This document serves as the technical log for Keybreeze. It outlines the application's structure, the engineering decisions made, and the "how" of the project. When you make any changes to the app, please ask the user to test the app first before you update any of the documentation.*

---

## What Keybreeze Is

A macOS menu bar app providing local, low-latency text continuation (autocomplete). Uses Ollama (primary) or llama.cpp (secondary) over HTTP.

**Core promise:** *Create uninterrupted writing flow.*

---

## Data Flow (How Predictions Happen)

```
User types in TextField
  → sessionVM.handleDraftChanged()
    → CompletionController.editorStateChanged()
      → cancelAll()
      → 45ms debounce
        → runPrediction()
          → PromptBuilder.continuationPrompt()
            → Branch on backend:
              • Ollama: prompt = context + "\n\nContinue with the next few words only:\n"
              • llama.cpp: prompt = raw context only (no instruction boilerplate)
          → LLMClient.streamCompletion(prompt, systemPrompt, model)
            → Branch on backend:
              • Ollama: POST /v1/chat/completions (SSE stream)
              • llama.cpp: POST /completion (SSE stream)
            → tokens arrive via onToken closure
            → STREAMING GATE: only update suggestion after first complete word
              → GhostTextModifier renders grey inline ghost text
```

---

## Backend Lifecycle

### `BackendManager` (`Keybreeze/Core/BackendManager.swift`)
A `@MainActor` class managing the full lifecycle of LLM backend processes.

**Ollama:**
- Health-checks `localhost:11434`. If unreachable, spawns `ollama serve`. Tracks ownership for cleanup.

**llama.cpp:**
- Spawns `llama-server` via `Process()`. Server flags: `--model`, `--host`, `--port`, `--ctx-size 512`, `--threads 4`, `--ubatch-size 256`, `--flash-attn on`, `--no-jinja`.
- Temperature and top_p are set **per-request** via `CompletionController` (not server flags). Defaults: temp 0.35, top_p 0.85.
- **Streaming:** Uses SSE streaming to the raw `/completion` endpoint.
- **Flag compatibility (v9310):** `--no-chat-template` was removed upstream. Now uses `--no-jinja` to disable the jinja chat template engine. `--temp` and `--top-p` server flags removed — these are per-request parameters set by `CompletionController`.

**Termination:**
- `terminateAllSync()` is the authoritative teardown path (via `AppKitLifecycle.willTerminateNotification`). Never rely on `deinit`.

---

## Prompt Strategy

### `PromptBuilder` (`Keybreeze/LLM/PromptBuilder.swift`)
Two prompt modes, selected automatically by backend:

| Backend | Mode | Prompt Format | System Prompt |
|---------|------|--------------|---------------|
| Ollama | Chat (`raw: false`) | `{context}\n\nContinue with the next few words only:\n` | Sent as system message in messages array |
| llama.cpp | Raw (`raw: true`) | `{context}` (no instruction text) | Not applicable — `/completion` endpoint has no system prompt concept |

**Why raw mode for llama.cpp:** The `/completion` endpoint has no chat template (especially with `--no-jinja`). Any instruction text appended to the prompt is treated as text to continue — causing models (especially instruct-tuned ones like Gemma) to generate narrative fiction, HTML markup, or code instead of plain continuation text. Raw mode gives the model only the user's typed text, letting the completion endpoint naturally continue.

---

## Architecture Rules for AI Agents

### DO:
- Use `PromptBuilder` for ALL prompt construction.
- Use `Task { @MainActor in }` for cross-actor UI updates.
- Keep ghost text visual constants in `GhostTextStyle` — never duplicate.
- Use `BackendManager` for all process lifecycle.
- Verify binary version support for flags before updating server configurations.

### DO NOT:
- Create new LLM provider files.
- Add animations to ghost text.
- Modify `NSApplication` lifecycle outside of `AppKitLifecycle.swift`.

---

## Diagnostic Snapshot

- **Streaming:** llama.cpp and Ollama both use SSE streaming.
- **Streaming Gate:** Implemented; suggestions only update after the first complete word to prevent "dancing" text.
- **Issue #26:** RESOLVED: Upgraded via Homebrew. Minimum version requirement verified.
