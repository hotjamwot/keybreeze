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
