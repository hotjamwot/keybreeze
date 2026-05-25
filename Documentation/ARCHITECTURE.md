# Keybreeze — Architecture
Last updated: 26 May 2026

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
              • Ollama (raw: false): prompt = context + "\n\nContinue with the next few words only:\n"
              • llama.cpp (raw: true): prompt = context + trailing space (if not already present)
                — No system prompt, no chat template tokens, no instructions
          → LLMClient.streamCompletion(prompt, systemPrompt, model)
            → Branch on backend:
              • Ollama: POST /v1/chat/completions (SSE stream)
                — systemPrompt sent as "system" message in messages array
              • llama.cpp: POST /completion (SSE stream)
                — prompt is bare context text
                — stop tokens: ["<"] (prevents HTML, not \n which kills mid-word output)
                — repeat_penalty sent per-request
            → tokens arrive via onToken closure
            → STREAMING GATE: mid-word shows immediately, between-words waits for full word
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
- Temperature, top_p, and repeat_penalty are set **per-request** via `CompletionController` (not server flags).
- **Streaming:** Uses SSE streaming to the raw `/completion` endpoint.
- **Flag compatibility (v9310):** `--no-chat-template` was removed upstream. Now uses `--no-jinja` to disable the jinja chat template engine.

**Termination:**
- `terminateAllSync()` is the authoritative teardown path (via `AppKitLifecycle.willTerminateNotification`). Never rely on `deinit`.

---

## Prompt Strategy

### `PromptBuilder` (`Keybreeze/LLM/PromptBuilder.swift`)
Two prompt modes, selected automatically by backend:

| Backend | Mode | Prompt Format | System Prompt |
|---------|------|--------------|---------------|
| Ollama | Chat (`raw: false`) | `{context}\n\nContinue with the next few words only:\n` | Sent as system message in messages array |
| llama.cpp | Raw (`raw: true`) | `{context}` + trailing space if not already present | Not sent (`systemPromptOverride` is ignored in raw mode) |

**Why bare text for llama.cpp:** After extensive testing, wrapping prompts in Gemma's `<start_of_turn>` chat template tokens (D12) forced the instruct model into chatbot mode — producing empty mid-word responses, safety refusals ("I'm sorry, I can't..."), and system prompt leakage. Bare text at low temperature with repeat_penalty produces the most likely natural language continuation. A trailing space is appended for mid-word contexts to prevent the model from struggling with partial-word inputs.

### `ModelOption` — Single Source of Truth
**`Keybreeze/Core/ModelOption.swift`** holds all inference parameter defaults:
- `defaultTemperature: 0.1`
- `defaultTopP: 0.85`
- `defaultRepeatPenalty: 1.15`
- `defaultConfidenceThreshold: 0.25`

All components (`CompletionController`, `SessionViewModel`, `AggressionPreset`) reference these static values. No hardcoded defaults elsewhere.

---

## Architecture Rules for AI Agents

### DO:
- Use `PromptBuilder` for ALL prompt construction.
- Reference `ModelOption.default*` for ALL inference parameter defaults — never hardcode.
- Use `Task { @MainActor in }` for cross-actor UI updates.
- Keep ghost text visual constants in `GhostTextStyle` — never duplicate.
- Use `BackendManager` for all process lifecycle.
- Verify binary version support for flags before updating server configurations.
- Use `<` as stop token for llama.cpp: prevents HTML output without killing mid-word completions.
- DO NOT use `\n` as a stop token: it causes empty mid-word outputs (the model hesitates with newlines).

### DO NOT:
- Create new LLM provider files.
- Add animations to ghost text.
- Modify `NSApplication` lifecycle outside of `AppKitLifecycle.swift`.
- Hardcode inference parameter defaults anywhere except `ModelOption`.
- Use `<start_of_turn>` or `[INST]` chat template tokens in llama.cpp prompts.
- Add instructions/commands like "Continue with..." to llama.cpp raw prompts.

---

## Diagnostic Snapshot

- **Streaming:** llama.cpp and Ollama both use SSE streaming.
- **Streaming Gate:** Context-sensitive: mid-word shows immediately, between-words waits for full word or 10+ chars.
- **Issue #26 (Upgrade requirement):** RESOLVED. Minimum version verified.
- **Issue #27 (Chatbot refusals):** RESOLVED. Switched from chat template tokens to bare text with trailing space.
- **Issue #28 (Empty mid-word outputs):** RESOLVED. Removed `\n` stop token; added trailing space to raw prompt.
- **Issue #29 (Word repetition):** RESOLVED. Default repeat_penalty changed from 1.02 to 1.15.
- **Issue #30 (Parameter fragmentation):** RESOLVED. All defaults centralized in `ModelOption`.