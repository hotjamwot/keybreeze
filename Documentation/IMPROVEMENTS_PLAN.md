# Keybreeze — Ghost Type-Inspired Improvements

**Source drawdown:** `GhostType-main` (`/Users/haydenjweal/Movies/PROJECTS/Code/GhostType-main`)
**Baseline:** GhostType codebase guide at `Documentation/GHOST_TYPE_CODEBASE_GUIDE.md`

---

## Guiding Principles

1. **Borrow patterns, not architecture.** GhostType is flat because its ambition requires one layer. Keybreeze is distributed because Typing Lab and dual-backend orchestration require more. Blurring that distinction by collapsing layers now would destroy work that is already paying rent.

2. **Feature-flag every new AX integration path.** Autocomplete systems are difficult to regression-test: failures are contextual, timing-sensitive, and app-specific. Feature flags enable staged rollout, A/B reliability comparison, and instant rollback without a binary release. Treat every new path as opt-in until it has proven stable in the wild.

3. **Avoid god objects through internal partition, not file splitting.** The new `AccessibilityManager` will accumulate text extraction, insertion, app-gating, focus resolution, element caching, tree walking, and fallback logic. Resist the urge to split into `TextReader` / `TextInserter` / `FocusResolver` / `AXElementWalker` files. Instead: keep one file, but mark strict boundaries with `// MARK:` and forbid cross-boundary method calls. One file per class is acceptable if the class is at most one tightly-partitioned object. If it crosses ~1,000 lines, reassess — but the partition discipline should let it stay well under that indefinitely.

4. **Insertion observability is a UX requirement, not a debug nicety.** The clipboard-fallback path introduces clipboard-history collisions, universal-clipboard flash side-effects, password-manager interference, and paste-format mismatches. Users cannot articulate these technically, but they destroy trust. Every insertion attempt — whether AX or clipboard — must log the strategy used and any failure reason.

---

## Win 1 — App Gating: Excluded Bundle IDs + Manual-Only List ✅ **COMPLETED**

**Re-prioritized to #1.** Wrong-context triggering (i.e. autocomplete firing in Xcode, Cursor, or a terminal) is fatal to trust — and far harder to recover from than a single failed insertion. Bad autocomplete in a coding app feels invasive. Clipboard fallback failures feel merely annoying. Gate first, refine later.

**Implementation Status:** Completed 2026-05-19.

**Changes made:**
- Created `Keybreeze/Core/AccessibilityManager.swift` with `focusedAppBundleID()` and default bundle ID lists
- Added `excludedBundleIDs` and `manualOnlyBundleIDs` properties to `PredictionSessionViewModel` with `UserDefaults` persistence
- Extended `PredictionScheduler.canPredict` gate to check excluded apps first using `AccessibilityManager.shared.focusedAppBundleID()`
- Added "Apps" tab to `TypingLabRootView` with `AppGatingPanelView` for managing app lists (view-only for now, no app picker)
- Fixed `AppState.swift` `presencePenalty` parameter issue discovered during implementation

**Why it matters.** Keybreeze today has no way to say "don't autocomplete in Xcode" or "only allow manual trigger in Mail." GhostType ships with ~30 pre-built excluded bundle IDs (IDEs, terminals) and a separate ~6-entry manual-only list (Mail, Outlook, Slack, Discord, Telegram, Messenger). The UI is a searchable `NSWorkspace`-powered app picker in Settings.

**What GhostType does.**
*(see GhostType for reference pattern)*

**How to bring it to Keybreeze.**
*(Implementation completed — see notes above)*

**Files touched.**
- `Keybreeze/Core/AccessibilityManager.swift` *(new — `focusedAppBundleID()`, default bundle ID lists)*
- `Keybreeze/UI/PredictionSessionViewModel.swift` *(exclusion fields, `isExcluded()`/`isManualOnly()`, gate logic, settings persistence)*
- `Keybreeze/UI/TypingLab/TypingLabRootView.swift` *(added Apps tab)*
- `Keybreeze/UI/TypingLab/AppGatingPanelView.swift` *(new — apps panel UI)*
- `Keybreeze/Core/AppState.swift` *(bug fix: `presencePenalty` parameter)*

---

## Win 2 — Two-Strategy AX Text Read (Browser / Web-App Saver)

**Why it matters.** Electron-bundled and web-hybrid apps (Slack, Discord, Cursor, Chrome, Brave, Arc) return an empty string for `kAXValueAttribute` — yet `AXStringForRange` against the same element returns the full surrounding text. If Keybreeze is ever wired to read text from any external app, this is the first reliability gap it will encounter.

**What GhostType does.**
`AccessibilityManager.getTextContext(maxChars:)` (line 67) runs strategy 1 (`AXValue` + `AXSelectedTextRange` on native/macOS apps) first. Returns immediately on success. Only if strategy 1 fails entirely does it try strategy 2 (`AXStringForRange` on the same element, which handles browsers, web content areas, and grouping containers). Both strategies produce the same `TextContext(prefix:suffix:cursorRect:)`, so the rest of the engine is agnostic.

**How to bring it to Keybreeze.**
1. In the new `AccessibilityManager`, `func getTextContext(maxChars: Int) -> TextContext?` runs both strategies in order, behind a **`UserDefaults.standard.bool(forKey: "UseAXContextReader")`** feature flag. Default: `true` (enabled). The flag exists *today* so a user experiencing a regression can toggle it off without a binary rollback.
2. Add `findBestTextElement()` from GhostType (`AccessibilityManager.swift:135`) — the AX tree walker that handles `AXWebArea`, `AXGroup`, focused-child descent (max depth 5), and a parent-walk escape hatch. ~70 lines, lives in the same `AccessibilityManager` and is referenced by both strategies.
3. `ContextBuilder` calls `AccessibilityManager.shared.getTextContext(maxChars:)` and already handles `nil`. No callers need to change on failure.

**Files touched.**
- `Keybreeze/Core/AccessibilityManager.swift` *(new, same file as Win1 — same feature-flag gate on the read path)*
- `Keybreeze/Core/ContextBuilder.swift` *(modify to call `AccessibilityManager.shared.getTextContext()` behind the feature flag)*

---

## Win 3 — Clipboard-Fallback Text Insertion

**Why it matters.** Some apps (password fields, secure widgets, fraud-detection-heightened surfaces) permit AX value *read* but reject AX value *mutation* via `AXUIElementSetAttributeValue`. GhostType detects the `.failure` or `.success != .success` result and falls through to a pasteboard-based insertion that is invisible to the user — including restoring the previous pasteboard contents after 0.5 s.

**UX edge cases this introduces** (important to log, not block):
- `clipboard-history` tools (Raycast, Alfred, PastePal, CopyClip) may record the completion text as an intentional paste even though it was a stealth insert.
- Password managers using the pasteboard as a shared credential bus can race against the restore-dispatch.
- Universal Clipboard (iPhone → Mac / Mac → iPhone) can flash the predicted text to another device before restore fires.
- Rich-text fields can misinterpret a plain-string pasteboard write as formatting noise.

These are observable side-effects, not bugs in the fallback logic. They are logged (not surfaced to the user), so a `ax_insert_strategy` counter plus any failures can be surfaced in the Typing Lab diagnostics panel alongside TTFT metrics.

**What GhostType does.**
```
AXUIElementSetAttributeValue → .success? → return
.fail / not .success  →  pasteboard save  →  paste new text  →  Cmd+V CGEvent
→  dispatch restore old contents after 0.5 s on .main queue
```

**How to bring it to Keybreeze.**
1. In `AccessibilityManager`, attach an `InsertionStrategy` enum to every insert call:

```swift
enum InsertionStrategy {
    case ax
    case clipboard
}
```

2. Add a `os_log` call at the start of every `insertText()`:

```swift
os_log("Insertion strategy: %{public}@, app: %{public}@",
       log: axLog,
       type: .debug,
       strategy == .ax ? "AX" : "clipboard",
       frontmostBundleID ?? "unknown")
```

3. The fallback path mirrors GhostType's pasteboard-restore exactly (0.5 s delay, restore old string). Disable the flag `"UseClipboardFallback"` by default until the first round of field-testing completes, then flip it on.

**Feature flag:** `UserDefaults.standard.bool(forKey: "UseClipboardFallback")` — default `false` until tested.

**Files touched.**
- `Keybreeze/Core/AccessibilityManager.swift` *(same file — same partition boundary as Win1/2)*

---

## Win 4 — InputSourceMonitor (IME Safety Gate)

**Why it matters.** A user mid-Japanese, Chinese, or Korean IME composition should not receive autocomplete. The result is broken input and instant trust loss. GhostType handles this with 79 lines of pure C/Foundation code.

**What GhostType does.**
`InputSourceMonitor.shared` self-starts on init, observing `kTISNotifySelectedKeyboardInputSourceChanged` via `CFNotificationCenterGetDistributedCenter`. On every observed change (or init), it reads two properties: `kTISTypeKeyboardLayout` (type is plain layout, not IME input mode) and `kTISPropertyInputSourceIsASCIICapable` (true). The single consumer is `guard inputSource.isASCIICompatible else { return }` in `CompletionController.scheduleAutoTrigger()`. No polling, no timers, ~µs cost per event.

**How to bring it to Keybreeze.**
1. Port `InputSourceMonitor.swift` verbatim into `Keybreeze/Core/InputSourceMonitor.swift`.
2.Extend `PredictionScheduler.canPredict` — this closure is *the* single decision-making choke point for when inference fires; it already gates on `appState.canRunPrediction`:

```swift
scheduler.canPredict = { [weak self] in
    guard let self else { return false }
    let frontmostID = AccessibilityManager.shared.focusedAppBundleID()
    if frontmostID.map(self.isExcluded) ?? false { return false }
    if !InputSourceMonitor.shared.isASCIICompatible { return false }
    return self.appState.canRunPrediction
}
```

3. Touch `InputSourceMonitor.shared` once in `PredictionSessionViewModel.init()` so the CFNotificationCenter observer is registered before the first debounce fires.

**Files touched.**
- `Keybreeze/Core/InputSourceMonitor.swift` *(new)*
- `Keybreeze/UI/PredictionSessionViewModel.swift` *(extend `canPredict` closure — same closure extended in Win1)*

---

## Win 5 — Settings Consolidation (Do Last)

**Why it matters, and why last.** `PredictionSessionViewModel` currently carries 18 flat `@Published` properties. GhostType's `AppSettings` (272 lines in one coherent file) is the aspirational target shape: nested structs for organization, single `save()` / `load()`, one `UserDefaults` contact point. This is the right direction, but it depends on Wins 1–4 landing cleanly first — otherwise the object graph shifts under you mid-refactor.

**Target shape.**

```swift
struct InferenceSettings: Codable {
    var temperature: Double
    var topP: Double
    var repeatPenalty: Double
    var presencePenalty: Double
    var confidenceThreshold: Double
    var maxWords: Int
}

struct TriggerSettings: Codable {
    var debounceMs: Int
    var enabled: Bool
}

final class PredictionSessionViewModel: ObservableObject {
    @Published var inference = InferenceSettings()
    @Published var ui = UISettings()
    @Published var tuning = TuningSettings()
}
```

**Do not start this until Wins 1–4 are merged to main.** It is a structural refactor with zero user-visible effect, and its only benefit is maintainability. Do it as an orthogonal PR with a clear "before state showed stable for N days" criterion.

---

## Anti-Patterns (Confirmed Against)

### Do NOT collapse `LLMProvider` into one `LLMClient`

GhostType's one-call elegance is real — but GhostType does not manage a daemon lifecycle, per-model tuning, KV-cache pre-warming, or speculative-decoding experiments. Keybreeze does. The protocol boundary is abstraction that pays rent. Keep it. If the goal is to reduce surface area, unify the *request contract* (`CompletionRequest` / `CompletionResponse` structs), not the backends.

### Do NOT maximize flatness at the expense of partition integrity

GhostType can get away with a 414-line `AccessibilityManager` because it stops at 414 lines. Keybreeze's version is accumulating text extraction, insertion, app-gating, the fallback partition, insertion logging, and eventually secure field detection — it needs the disciplined `// MARK:` internal structure even if it stays in one file. **One file per class is acceptable; one file for multiple concerns is not.** Internal partition discipline, not file splitting, is the remedy.

### Do NOT duplicate model catalog logic in the overlay

`AppState` owns model discovery. The only additions the overlay needs are app-gating exclusion signals — do not re-scrape bundle IDs from the LLM layer. Keep the two layers separated at the dependency boundary.

### Do NOT leave clipboard fallback unobserved

`InsertionStrategy` enum + `os_log` per insertion attempt. Every clipboard insert should be in the diagnostics panel. Never ship a fallback path with zero observability.

---

## Dependency Ordering

Wins are strictly ordered by **user-trust impact**, not implementation convenience:

| Order | Win | Estimated Change Size | Risk | Trust Impact | Status |
|-------|-----|-----------------------|------|-------------|--------|
| 1 | App gating | ~120 lines new, ~30 modified | Low | **High** — prevents invasive predictions before they happen | ✅ Done |
| 2 | `InputSourceMonitor` | 79 lines new | None | High — prevents broken CJK composition | Pending |
| 3 | Two-strategy AX read | ~130 lines new, ~10 modified | Low | Medium — unlocks browser support | Pending |
| 4 | Clipboard insertion fallback | ~30 lines new (same file) | Low (flagged) | Medium — last-resort recovery | Pending |
| 5 | Settings consolidation | ~200 lines refactor | None (functional) | Low — maintainability only | Pending |

**Wins 1, 2, 3, and 4 all center on `AccessibilityManager.swift` + the `canPredict` gate.** No win touches more than two production files, and no win requires changes to the LLM backend layer at all.
