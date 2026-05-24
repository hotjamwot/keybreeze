# Keybreeze Behavioral Specification

## Real-Time Predictive Typing Assistant

### Core UX Philosophy

The assistant must feel:

* Invisible
* Immediate
* Non-intrusive
* Forgiving
* Cognitively lightweight
* Always one thought ahead
* Never “thinking”

The user should feel like:

> “The computer already knows what I’m trying to say.”

Latency is the primary feature.

Not intelligence.

A slightly worse model with instant response feels dramatically better than a smarter model with hesitation.

---

# 1. Typing Prediction Lifecycle

## Idle State

When the user is not typing:

* No visible prediction
* Caret behaves normally
* No UI flicker
* No loading indicators

System remains silently warm and ready.

---

# 2. Keystroke Response Timing

## On Keypress

Every keypress immediately:

1. Updates local text buffer
2. Cancels previous prediction generation
3. Starts debounce timer

### Debounce Timing

Recommended:

* `35–60ms` debounce after final keystroke
* Sweet spot target: `~45ms`

Longer than ~80ms begins to feel sluggish.

Shorter than ~25ms causes excessive flicker and wasted inference calls.

---

# 3. Prediction Generation Timing

## Prediction Must Appear Within:

Ideal:

* `40–90ms`

Acceptable:

* `100–140ms`

Bad:

* `>180ms`

At ~250ms the user consciously notices delay.

At ~400ms the illusion breaks completely.

---

# 4. Prediction Display Rules

## Inline Ghost Text

Predictions appear:

* Inline
* Immediately after caret
* Same baseline as text
* No popup by default

### Visual Style

Prediction text should be:

* Grey
* Slightly translucent
* Lower contrast than committed text
* Non-distracting

Example:

```text
I think we should probably go to the
                                   cinema tonight
```

Where:

* Left side = committed text
* Right side = ghost prediction

---

# 5. Acceptance Behavior

## TAB Key

Primary accept key:

* `Tab`

Behavior:

* Accepts full visible prediction
* Inserts prediction instantly
* Moves caret to end

Must feel:

* Zero latency
* Native
* Mechanical

---

## Word-by-Word Acceptance (Optional but Powerful)

### Right Arrow

Accepts:

* Next predicted word only

This creates:

* High trust
* Fine-grained control
* Lower cognitive risk

Example:

Ghost text:

```text
cinema tonight because
```

Right arrow inserts:

```text
cinema
```

Remaining ghost:

```text
 tonight because
```

This is one of the hidden “magic” features that makes predictive typing addictive.

---

# 6. Prediction Invalidation

Predictions disappear instantly when:

* User types incompatible character
* Caret moves
* Mouse click occurs
* Selection changes
* Undo occurs

No fade animation.

Hard replace only.

Why?

Because fade delays make the UI feel sticky.

---

# 7. Backspace Correction Behavior

## (Critical Feature)

This is one of the most important behaviors psychologically.

When user backspaces through a misspelled or incorrect word:

### System Detects:

* User hesitation
* Intent correction
* Partial deletion pattern

Example:

```text
I absolutley
```

User backspaces:

```text
I absolutl
```

System infers intended correction:

```text
absolutely
```

---

## Visual Correction State

### Incorrect Word

Display:

* Greyed out
* Red strikethrough

### Suggested Correction

Display:

* Green
* Inline replacement

Example:

```text
absolutley  →  absolutely
```

Visualized as:

~~absolutley~~ absolutely

---

## Correction Acceptance

### TAB

Accepts corrected word instantly.

### ESC

Rejects correction suggestion.

### Continued typing

Dismisses correction state immediately.

---

# 8. Prediction Hierarchy

The system should prioritize:

## 1. Local sentence completion

Most important.

## 2. Current paragraph context

## 3. Writing style continuity

## 4. Global semantic reasoning

Least important.

This is why tiny fast models often outperform large smart models in UX.

The user cares more about:

* phrase rhythm
* sentence continuation
* predictable wording

than abstract intelligence.

---

# 9. UI Stability Rules

The UI must NEVER:

* Jump vertically
* Resize while typing
* Shift layout
* Animate predictions heavily
* Introduce modal interruptions

Predictive typing is peripheral cognition.

Anything flashy destroys flow state.

---

# 10. Streaming Behavior

Predictions should ideally stream token-by-token.

BUT:

Only display once:

* Minimum confidence threshold reached
  OR
* First full word completed

Otherwise users see unstable “dancing” predictions.

---

# 11. Cancellation Behavior

Every new keystroke must:

* Immediately cancel current inference
* Immediately begin next prediction cycle

No queued generations.

Stale predictions are worse than missing predictions.

---

# 12. Model Behavior Priorities

The model should optimize for:

1. Speed
2. Stability
3. Predictability
4. Low hallucination
5. Low creativity
6. Intelligence

This is counterintuitive but essential.

A predictive typing engine is not ChatGPT.

It is a continuation engine.

Temperature should likely be:

* `0.1–0.3`

Top-p:

* Conservative

Avoid:

* Creative branching
* Surprising phrasing
* Long speculative completions

---

# 13. Context Window Strategy

Only recent text should dominate prediction.

Ideal weighting:

* Last sentence = highest priority
* Last paragraph = medium
* Entire document = weak influence

Overly large context causes:

* latency
* semantic drift
* weird stylistic overreach

---

# 14. Performance Targets

## Perceived UX Targets

### First token latency

Target:

* `<50ms`

### Full prediction latency

Target:

* `<120ms`

### UI frame rate

Target:

* `60fps`

### Keystroke processing

Target:

* `<8ms`

---

# 15. Trust Model

The assistant succeeds when users:

* Stop consciously reading predictions
* Develop muscle memory around TAB
* Feel “supported” rather than interrupted

The moment users begin evaluating suggestions intellectually, flow is lost.

---

# 16. Hidden UX Truth

The  magic is NOT:

* superior AI
* superior prompting
* superior reasoning

It’s likely:

* ultra-low latency
* careful debounce tuning
* deterministic generation
* aggressive cancellation
* visual restraint
* local-context prioritization
* excellent correction UX

That’s why recreating it is difficult.

You are not rebuilding an AI model.

You are rebuilding typing rhythm.

---

# 17. Engineering North Star

If forced to choose:

Choose:

* Faster
* Simpler
* More stable

Over:

* Smarter
* Larger
* More creative

Every single time.

Because predictive typing is fundamentally a motor-control experience, not a conversational AI experience.

---

# Desired Behavior Outcomes (TODO List)

The following is the definitive checklist of features and behaviors the app must support, derived from the behavioral specification above. Status reflects current implementation state.

| # | Outcome | Section | Status | Notes |
|---|---------|---------|--------|-------|
| 1 | **Invisible ghost text overlay** — ghost text appears inline after caret, same baseline, grey/translucent, no popup | §4 Prediction Display | ❌ Implemented but buggy | Works in Typing Lab playground (GhostTextModifier) AND third-party apps via `SuggestionOverlayWindowController` floating overlay |
| 2 | **Streaming prediction display** — only show after first full word or confidence threshold, avoid "dancing" | §10 Streaming Behavior | ❌ Implemented but buggy | Streaming works in CompletionController, but threshold gating is not implemented — all tokens display immediately |
| 3 | **Tab accepts full prediction** — inserts instantly, moves caret to end, zero-latency feel | §5 Tab Accept | ✅ | Implemented in SessionViewModel.acceptSuggestion() and global/local event monitors |
| 4 | **Word-by-word acceptance (Right Arrow)** — accept next word only, remaining ghost stays | §5 Right Arrow | ❌ Implemented but buggy | Only Tab acceptance (full suggestion) is implemented. Right Arrow acceptance is future work |
| 5 | **Prediction invalidation** — disappear instantly on incompatible keypress, caret move, click, selection change, undo. No fade | §6 Invalidation | 🔄 Partial | CompletionController handles cancellation on new input. Mouse clicks and selection changes in external apps are not detected |
| 6 | **Backspace correction** — detect misspelling + hesitation, show strikethrough + green suggestion | §7 Correction | ❌ Not implemented | CorrectionState struct exists in PredictionHistory but no detection logic or UI wiring is present |
| 7 | **Corrected word acceptance (Tab/ESC)** — Tab accepts correction, ESC rejects, continued typing dismisses | §7 Correction | ❌ Not implemented | No correction state processing in SessionViewModel |
| 8 | **Keystroke response < 8ms** — every keypress must debounce, cancel previous, start new prediction | §2 Timing | ❌ Implemented but buggy | 45ms debounce in CompletionController, aggressive cancellation |
| 9 | **Prediction appears within 40-140ms** — TTFT + total time targets | §3 Generation Timing | 🔄 Partial | Latency tracking is implemented (TTFT, total latency) but whether targets are met depends on the model and backend |
| 10 | **System-wide prediction** — read text from any focused app's text field via AX API | §1 Lifecycle | ❌ Implemented but buggy | SystemWidePredictor reads context via AccessibilityManager. Predictions feed into CompletionController. Ghost overlay appears in the focused app via SuggestionOverlayWindowController |
| 11 | **Tab acceptance in any app** — insert accepted prediction into external app's text field | §5 Tab Accept | ❌ Implemented but buggy | Via global event monitor + AccessibilityManager.insertText(). Uses keyboard event synthesis to preserve formatting |
| 12 | **App gating** — exclude/manual-only lists respected during system-wide prediction | §1 Lifecycle | ❌ Implemented but buggy | excludedBundleIDs + manualOnlyBundleIDs logic in SystemWidePredictor.shouldProcessApp() |
| 13 | **Stable UI — no jumps, resizes, animations, or modals** | §9 UI Stability | ❌ Implemented but buggy | GhostTextModifier is pure overlay, no animations. Menu bar is static. |
| 14 | **IME safety** — pause predictions during non-ASCII input source composition | §1 Lifecycle | ❌ Implemented but buggy | InputSourceMonitor.isASCIICompatible gate in SystemWidePredictor |
| 15 | **Latency monitoring** — TTFT and total time tracked per prediction, displayed in diagnostics | §14 Performance | ❌ Implemented but buggy | CompletionController tracks both. DiagnosticsPanelView displays averages |
| 16 | **Acceptance history** — every prediction recorded with resolution, TTFT, total time | §5 Behavior | ❌ Implemented but buggy | PredictionHistory ring buffer (200 records) with full metadata |
| 17 | **Dock + Cmd+Tab when settings window is open** — regular activation policy while window visible | — | ❌ Implemented but buggy | AppKitLifecycle.showInDockAndCmdTab()/restoreToAccessory() |
| 18 | **Settings window close does not hang** — closing window must not cancel predictions or crash | — | 🔄 Partial | Mitigated (deferred restoreToAccessory, removed onReceive subscribers) but ViewBridge error still occurs intermittently |
| 19 | **Ghost overlay for third-party apps** — floating window positioned over external text field showing prediction | §4 Display | ❌ Implemented but buggy | Implemented via `SuggestionOverlayWindowController` — borderless transparent NSWindow at popUpMenu level, positioned via AX cursor rect, click-through, no focus steal |
