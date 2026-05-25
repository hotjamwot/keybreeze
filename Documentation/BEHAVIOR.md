# Keybreeze Behavioral Specification
Last updated: 25 May 2026

This document is the behavioral contract for Keybreeze. It contains NO implementation status. AI agents must treat every item here as a requirement, not a suggestion.

---

## Core UX Philosophy

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

Latency is the primary feature. Not intelligence. A slightly worse model with instant response feels dramatically better than a smarter model with hesitation.

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
* `35–60ms` debounce after final keystroke
* Sweet spot target: `~45ms`

---

# 3. Prediction Generation Timing

## Prediction Must Appear Within:
Ideal: `40–90ms`.
Acceptable: `100–140ms`.
Bad: `>180ms`.

At ~250ms the user consciously notices delay. At ~400ms the illusion breaks completely.

---

# 4. Prediction Display Rules

## Inline Ghost Text
Predictions appear:
* Inline
* Immediately after caret
* Same baseline as text
* No popup by default

### Visual Style
Prediction text must be:
* Grey
* Slightly translucent
* Lower contrast than committed text

---

# 5. Acceptance Behavior

## TAB Key
Accepts full visible prediction, inserts instantly, moves caret to end. Must feel zero-latency and native.

## Right Arrow
Accepts next predicted word only. This creates high trust and fine-grained control.

---

# 6. Prediction Invalidation
Predictions disappear instantly when:
* User types incompatible character
* Caret moves
* Mouse click occurs
* Selection changes
* Undo occurs

No fade animation. Hard replace only.

---

# 7. Backspace Correction Behavior

## Critical Feature
When user backspaces through a misspelled or incorrect word, the system detects hesitation and infers intended correction.

## Visual Correction State
* Incorrect word: Greyed out with red strikethrough.
* Suggested correction: Green inline replacement.

## Correction Acceptance
* TAB: Accepts corrected word instantly.
* ESC: Rejects correction suggestion.
* Continued typing: Dismisses correction state.

---

# 8. Prediction Hierarchy
1. Local sentence completion
2. Current paragraph context
3. Writing style continuity
4. Global semantic reasoning (Least important)

---

# 9. UI Stability Rules
The UI must NEVER:
* Jump vertically
* Resize while typing
* Shift layout
* Animate predictions heavily
* Introduce modal interruptions

---

# 10. Streaming Behavior
Predictions should stream token-by-token. Only display once:
* Minimum confidence threshold reached OR
* First full word completed.

---

# 11. Cancellation Behavior
Every new keystroke must:
* Immediately cancel current inference
* Immediately begin next prediction cycle

No queued generations. Stale predictions are worse than missing ones.

---

# 12. Model Behavior Priorities
Optimize for:
1. Speed
2. Stability
3. Predictability
4. Low hallucination
5. Low creativity
6. Intelligence

Production default temperature: 0.0 (for determinism). Sliders allow 0.1–0.3.

---

# 13. Context Window Strategy
Only recent text should dominate prediction.
* Last sentence = highest priority
* Last paragraph = medium
* Entire document = weak influence

---

# 14. Performance Targets
* First token latency: <50ms
* Full prediction latency: <120ms
* UI frame rate: 60fps
* Keystroke processing: <8ms

---

# 15. Trust Model
The assistant succeeds when users:
* Stop consciously reading predictions
* Develop muscle memory around TAB
* Feel “supported” rather than interrupted

---

# 16. Hidden UX Truth
The magic is NOT superior AI, prompting, or reasoning. It is:
* Ultra-low latency
* Careful debounce tuning
* Deterministic generation
* Aggressive cancellation
* Visual restraint

---

# 17. Engineering North Star
If forced to choose:
Choose Faster, Simpler, More stable.
Over Smarter, Larger, More creative.
