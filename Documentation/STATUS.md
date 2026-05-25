# Keybreeze — Live Status

This is the single source of truth for what is currently working, broken, or in progress. It is updated at the end of every development session.

AI agents must read this file before starting any work. Do not assume something is working unless it is marked ✅ here. Do not assume something is not implemented unless it is marked ❌ here.

## Status Key
- ✅ Working — implemented and confirmed working in current build
- ⚠️ Broken — implemented but has known bugs (see notes)
- 🔄 Partial — partially implemented, some cases work
- ❌ Not started — not yet implemented
- 🚫 Blocked — cannot proceed until a dependency is resolved

Last updated: 25 May 2026

## Backends

| # | Backend | Status | Notes |
|---|---------|--------|-------|
| A | Ollama | ✅ | Working end-to-end. |
| B | llama.cpp (v9310) | ⚠️ | Server boots (`--no-jinja` flag fixed). Prompt quality needs tuning — generates bogus responses (HTML tags, code, creative fiction) with instruct-tuned models like Gemma. Raw prompt mode active (no instruction text) to avoid chat template interference. Temperature 0.35, top_p 0.85 set per-request. |

## Features

| # | Outcome | Status | Notes |
|---|---------|--------|-------|
| 1 | Invisible ghost text overlay | ⚠️ | Works in Typing Lab; external overlay has positioning quirks. Keybreeze's own overlay suppressed (Typing Lab uses inline GhostTextModifier instead). |
| 2 | Streaming prediction display | ⚠️ | Streaming works; threshold gating is pending. |
| 3 | Tab accepts word-by-word | ✅ | |
| 4 | Full prediction acceptance (Backtick key) | ❌ | Future work. |
| 5 | Prediction invalidation | 🔄 | Partial: manual triggers work; external mouse/select not detected. |
| 6 | Backspace correction | ❌ | Detection logic/UI wiring missing. |
| 7 | Corrected word acceptance | ❌ | No correction state processing. |
| 8 | Keystroke response < 8ms | ⚠️ | Debounce works; performance depends on backend. |
| 9 | Prediction appears within 40-140ms | 🔄 | Depends on model/backend performance. Avg TTFT 75ms with llama.cpp + Gemma 4. |
| 10 | System-wide prediction | ⚠️ | Works, but requires full AX permissions and reliable cursor tracking. |
| 11 | Tab acceptance in external apps | ⚠️ | Uses keyboard synthesis; needs stability improvements. |
| 12 | App gating | ⚠️ | Logic exists, needs comprehensive testing. |
| 13 | Stable UI | ⚠️ | Mostly stable, occasional edge-case flicker. |
| 14 | IME safety | ⚠️ | Needs verification with different input sources. |
| 15 | Latency monitoring | ⚠️ | Implemented but requires validation. |
| 16 | Acceptance history | ⚠️ | Implemented, requires usage review. |
| 17 | Dock + Cmd+Tab behavior | ⚠️ | Intermittent ViewBridge errors. |
| 18 | Settings window close stability | 🔄 | Mitigated, still rare intermittency. |
| 19 | Ghost overlay for third-party apps | ⚠️ | Implemented; positioning is the primary bug. Overlay correctly suppressed when Keybreeze itself is focused. |