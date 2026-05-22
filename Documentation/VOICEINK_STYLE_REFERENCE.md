# VoiceInk Settings — Design Reference Guide

> **Purpose:** Document the visual design system, component patterns, and coding conventions used in VoiceInk's Settings views and shared UI components. Use this as the style-reference baseline when standardising Keybreeze's settings panel.

---

## 1. Foundations

### Container Layout

| Layer | Modifier / Pattern |
|-------|-------------------|
| **Base layout** | `Form { … }` with `.formStyle(.grouped)` |
| **Transparent background** | `.scrollContentBackground(.hidden)` + `.background(Color(NSColor.controlBackgroundColor))` |
| **Window background** | `.background(Color(NSColor.windowBackgroundColor))` |
| **Control background** | `Color(NSColor.controlBackgroundColor)` — used per-component |
| **Separator override** | `.overlay(Divider().opacity(0.5), alignment: .bottom)` on section headers |

### Root Form

```swift
Form {
    Section { … } header: { Text("…") }
    // …
}
.formStyle(.grouped)
.scrollContentBackground(.hidden)
.background(Color(NSColor.controlBackgroundColor))
```

Every major grouping uses an explicit `Section` header. Custom header HStacks are used to inject buttons into section headers (e.g. settings gear icon inline with the title).

---

## 2. Spacing & Layout

Sizes are implicit — VoiceInk relies on SwiftUI's semantic spacing primitives rather than a single numeric scale. Patterns extracted from the codebase:

| Context | Value |
|---------|-------|
| VStack between vertical sections | `spacing: 40` (page-level section), `spacing: 20` (sub-group), `spacing: 12` (card list), `spacing: 8` (labels/inputs) |
| HStack between aligning label + control | `spacing: 12` |
| HStack between close icon + label | `spacing: 4` |
| Toggle label inner HStack | `spacing: 4` |
| Section expanded content indented by | `padding(.leading, 4)` |
| Section expanded content offset from toggle | `padding(.top, 12)` before sub-rows, `padding(.top, 8)` for secondary content |
| Card/Panel horizontal padding | `padding(.horizontal, 20…32)` depending on context |
| Card/Panel vertical padding | `padding(.vertical, 16…40)` depending on context |
| Icon + title in CompactHeroSection | `spacing: 16` vertically, `spacing: 6` between title/description |
| `Label("…", systemImage: "…")` label-image gap | Default (no custom override) |
| Card inner row spacing | `spacing: 8` |

**Rule:** `spacing` values come in a small discrete set: 4, 6, 8, 12, 16, 20, 32, 40. There is no continuous scale.

---

## 3. Typography

### Size Tokens (seen in `Font.system(size:)` calls)

| Name | Size | Weight | Design | Usage |
|------|------|--------|--------|-------|
| Display title | 22 | `.bold` | Default | Hero section title (`CompactHeroSection`) |
| Hero icon | 28 | Default | `.hierarchical` | Icons above hero title |
| Section heading | `.title2` (21) | `.semibold` | Default | Sub-group header (`Audio Input`, `Prioritized Devices`, etc.) |
| Panel header | `.headline` (17) | `.semibold` | Default | Card/sheet/popover titles |
| Body text | Default / `.body` | Default | Default | Toggle labels, button labels |
| Description / caption | 12–14 | Default | Default | `.settingsDescription()` helper = 12pt secondary |
| Subheadline secondary | `.subheadline` (13) / 14 | Default | Default | Helper text under card titles |
| Settings description (extension) | 12 | Default | Default | `.settingsDescription()` on `Text` |
| Key chip label | 12 | `.medium` | `.monospaced` | Keyboard shortcut chip |
| Badge / badge label | 10 | `.semibold` | Default | `ProBadge` PRO badge text |
| Caption / helper meta row | 11 | `.medium` / `.regular` | `.monospaced` | Metadata rows, AI request text |
| Body mono-digit stats | `.body.monospacedDigit()` | — | — | Statistics counters |

### Helper Extension

```swift
extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
```

Used consistently for secondary/helper text under section headers or inside rows.

### Font declarations

All fonts use `font(.system(size: N, weight: X, design: Y))` — no named font families. System `.default` design is the standard; `.monospaced` for code/keys; `.rounded` for keycap visuals (on `ShortcutPreviewView`).

---

## 4. Color

### Adaptive colors via NSColor aliases

VoiceInk uses `Color(NSColor.…)` wrappers for auto-adaptivity across light and dark appearances:

| Role | Value |
|------|-------|
| Card background / surface | `Color(NSColor.windowBackgroundColor)` |
| Control / input background | `Color(NSColor.controlBackgroundColor)` |
| Separator/subtle border | `Color(NSColor.separatorColor).opacity(0.5)` |
| Tertiary/dimmed label | `Color(NSColor.quaternaryLabelColor).opacity(0.3…0.5)` |
| Shadow | `Color(NSColor.shadowColor).opacity(0.1)` |

### Semantic colors

| Role | Usage |
|------|-------|
| `.primary` | Main text |
| `.secondary` | Subtitles, helper text, disabled chevrons |
| `.tertiary` | Loading/empty status |
| `.accentColor` | Active indicator, speech bars, selected badge, primary tint |
| `.blue` | Selected mode icon, primary action buttons |
| `.green` / `.green.opacity(0.1)` + `Capsule` background | "Active" status pill |
| `.orange` / `.orange.opacity(0.1)` + `Capsule` background | Warning states |
| `.red` / `.red.opacity(0.1)` | Error, destructive actions |
| `.white` on `.blue.opacity(0.8)` | `ProBadge` label background |

### Gradient usage

Only the `StyleConstants` card banking uses gradients:
- `cardGradient` / `cardGradientSelected` — multi-stop `LinearGradient` from window background colour with 0.55–0.6 top → 0.3 bottom opacity
- `cardBorder` — `LinearGradient` of `quaternaryLabelColor`
- `cardBorderSelected` — fade from `.accentColor.opacity(0.4)` to `.accentColor.opacity(0.2)`

All gradients are `topLeading → bottomTrailing`.

---

## 5. Component Library

### `Form` + Section (primary settings pattern)

```swift
Form {
    Section {
        // rows
    } header: {
        Text("Section Title")
    } footer: {
        Text("Optional helper text.")
    }
}
.formStyle(.grouped)
.scrollContentBackground(.hidden)
```

Section headers are always a plain `Text`. Custom header content (e.g. inline gear button) uses `HStack { Text("…"); Spacer(); Button(…) }`.

### `LabeledContent` (name-value rows)

The standard for label-aligned key-value pairs inside a Form section. The label goes as the first argument; the value/control goes in the trailing closure:

```swift
LabeledContent("Export Settings") {
    Button("Export") { … }
}
```

Key tables in `SettingsView` and `EnhancementSettingsView` use this for label-on-left, control-on-right layout entirely through the system Form layout.

### `Toggle` (switch row)

```swift
Toggle("Label text") {
    HStack(spacing: 4) {
        Text("Label")
        InfoTip("Helper text.")
    }
}
.toggleStyle(.switch)
```

Pairs with `InfoTip` inline when additional context is needed. The true toggle layout label must be a `HStack(spacing: 4)` if it wraps an `InfoTip`.

### `ExpandableSettingsRow` (disclosure-style expand/collapse)

```swift
struct ExpandableSettingsRow<Content: View>: View { … }
```

Key pattern for parent-child settings:
- Entire row is tappable via `.contentShape(Rectangle())` + `.onTapGesture`
- Chevron rotates 90° when expanded; dimmed (opacity 0.4) when disabled
- Animation: `.easeInOut(duration: 0.2)` on both expansion transitions
- Expanded content uses `.opacity.combined(with: .move(edge: .top))` transition
- When the toggle is enabled for the first time, row auto-expands

```swift
ExpandableSettingsRow(
    isExpanded: $isExpanded,
    isEnabled: $isFeatureEnabled,
    label: "Feature Name"
) {
    // sub-controls: Picker, Toggle, TextField, etc.
}
```

Used in: `SettingsView`, `EnhancementSettingsPanel`, `AudioCleanupSettingsView`.

**Important:** This is the only re-usable expandable-row component in VoiceInk. `AudioCleanupSettingsView` duplicates the pattern inline rather than importing `ExpandableSettingsRow` from `SettingsView` — a mild inconsistency in the codebase.

### `CardBackground` (frosted-glass panel for non-form screens)

```swift
CardBackground(isSelected: true/false)
```

- `RoundedRectangle` with `cornerRadius: 16`
- Multi-stop gradient fill simulating frosted glass (55% → 30% opacity window bg colour)
- Gradient border from `quaternaryLabelColor`
- Shadow: radius 10 / y 5 default, radius 15 / y 8 when selected
- Border thickness: 1.5pt

Primarily used in `AudioInputSettingsView` for device selection cards.

### `Card` buttons (device selection / mode selection)

All card-style buttons follow the same pattern:

```swift
Button(action: { … }) {
    VStack(alignment: .leading, spacing: 12) {
        Image(systemName: icon)           // 28pt, .hierarchical
            .font(.system(size: 28))
        VStack(alignment: .leading, spacing: 4) {
            Text("Mode Name")              // .headline
            Text("Description")            // .subheadline, .secondary
        }
    }
    .padding()
    .background(CardBackground(isSelected: isSelected))
}
.buttonStyle(.plain)
```

### `InfoTip` (inline information popover)

```swift
InfoTip(
    "Helper text.",
    learnMoreURL: "https://…"   // optional
)
```

Defaults:
- Icon: `info.circle.fill`, `.medium` scale, `.primary` color
- Popover width: 280pt, padding: 14pt
- Callout font, secondary colour
- "Learn more" link: accent colour — rendered as separate `Text` concatenated with `+`
- Padding hit area: 5pt all around

Used inline inside `HStack(spacing: 4)` next to `Text` labels.

### `CompactHeroSection` (intro banner)

```swift
CompactHeroSection(
    icon: "waveform",
    title: "Audio Input",
    description: "Configure your microphone preferences"
)
```

Layout: `VStack(spacing: 16)` → 28pt icon → `VStack(spacing: 6)` title/description. Padding: 20pt vertical, full-width frame.

### `LabeledContent` inside Group (sub-views)

The `AudioCleanupSettingsView` and `CustomSoundSettingsView` use `Group { LabeledContent { … } label: { … } }` — no outer `Section`. These patterns fall out of inline embedding and form their own visual row.

### `ProBadge`

```swift
ProBadge()
```

- `Text("PRO")`, 10pt semibold, white text
- `RoundedRectangle(cornerRadius: 4)` fill: `.blue.opacity(0.8)`
- Padding: horizontal 6pt, vertical 2pt
- Used inline in the label position of a row

### `KeyChip` (internal to `EnhancementShortcutsView`)

```swift
KeyChip(label: "⌘")
```

- `Text(label)`, 12pt medium monospaced, `.contiguous` default
- `RoundedRectangle(cornerRadius: 4).fill(controlBackgroundColor)`
- Border: `separatorColor.opacity(0.5)`, 0.5pt strokeBorder

### `FillerWordChip`

```swift
FillerWordChip(word: "um", onDelete: { … })
```

- `RoundedRectangle(cornerRadius: 6)`, `.windowBackgroundColor.opacity(0.4)` fill
- Border: `secondary.opacity(0.2)`, 1pt
- Padding: horizontal 8pt, vertical 4pt
- X button: `xmark.circle.fill`, turns red on hover
- Hover animation: `.easeInOut(duration: 0.2)`

### `FlowLayout`

Custom `Layout` struct placing subviews in rows, wrapping at available width. Used exclusively for tag/chip grids (`FillerWordChip`, prompt grid). `spacing: 6` default.

### `SlidingPanel` (side drawer)

```swift
.slidingPanel(isPresented: $isPanelOpen, width: 400) {
    // panel content
}
```

- Semi-transparent `Color.black.opacity(0.1)` overlay with dismiss tap
- Slide from off-screen via `.transition(.offset(x: panelWidth))`
- Panel background: `NSColor.windowBackgroundColor`
- Leading stroke divider, left shadow
- Animation: `.smooth(duration: 0.3)`

### `KeyCapView` (physical key rendering for shortcut display)

```swift
KeyCapView(text: "⌘")
```

- 25pt semibold rounded font
- Multi-layered: surface gradient → highlight gradient → border stroke → shadow → bottom-edge shadow → inner glow
- Press state: `.scaleEffect(0.95)` with `spring(response: 0.2, dampingFraction: 0.6)`

### `TrialMessageView`

```swift
TrialMessageView(message: "...", type: .warning)
```

- HStack icon (20pt) + title (`.headline`) + message (`.subheadline`, `.secondary`) + action buttons
- Coloured tinted background (`orange.opacity(0.1)`, `red.opacity(0.1)`, `blue.opacity(0.1)`)
- Buttons: `.bordered` and `.borderedProminent` style
- Corner radius: 12

### Status Pill (`Capsule`)

```swift
Label("Active", systemImage: "wave.3.right")
    .font(.caption)
    .foregroundStyle(.green)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(Capsule().fill(.green.opacity(0.1)))
```

Repeated consistently across device selection, priority cards.

### Section Row Button (icon)

```swift
Button {
    …
} label: {
    Image(systemName: "gear")
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(isShowing ? .accentColor : .secondary)
}
.buttonStyle(.plain)
.help("…")
```

Icon size: 16pt medium. `.plain` style to prevent extra button chrome. `.help` for tooltips.

---

## 6. Buttons

| Style | Modulation | Usage |
|-------|-----------|-------|
| `.bordered` | Default (tinted by `.tint()`) | Secondary action inside banner |
| `.borderedProminent` | Filled accent colour | Primary action inside banner |
| `.borderless` | Inline icon button (`.font(.system(size: 12))`) | Toolbar actions inside rows |
| `.plain` | No chrome | All icon-only buttons, card buttons, disclosure chevrons |
| `.controlSize(.small)` | For `ShortcutRecorder` | Shortcut capture field |

Button hit areas in rows are 28×28pt circles used as circular icon buttons (copy/save buttons use `.frame(width: 28, height: 28)` + `.clipShape(Circle())`).

---

## 7. Toggles

```swift
Toggle(isOn: $binding) {
    HStack(spacing: 4) {
        Text("Label name")
        InfoTip("Explanation.")
    }
}
.toggleStyle(.switch)
```

- Label is always inline to support the `InfoTip`. Never only a `Text` label on the outer Toggle.
- `.toggleStyle(.switch)` is the explicit style everywhere.
- `.labelsHidden()` when the label is mirrored into a custom `HStack` (seen in `ShortcutPreviewView`).

---

## 8. Pickers

```swift
Picker("Label text", selection: $binding) {
    ForEach(options) { option in
        Text("Display").tag(option)
    }
}
.pickerStyle(.segmented)   // inline two-or-three option
.pickerStyle(.menu)        // dropdown (≥5 options)
```

Default: no explicit `.pickerStyle()` → system-selected (inline segmented for ≤3, popup menu for >3). Explicit styles used as shown.

---

## 9. Picker (enum in radio list)

```swift
Picker("", selection: $mode) {
    ForEach(RecordingShortcutManager.Mode.allCases, id: \.self) { mode in
        Text(mode.displayName).tag(mode)
    }
}
.labelsHidden()
.fixedSize()
```

Used for mode switches inside HStacks where the picker label is provided by a surrounding `LabeledContent`.

---

## 10. Animations

| Pattern | Duration / Spring |
|---------|-----------------|
| Expand / collapse | `.easeInOut(duration: 0.2)` |
| Sliding panel open / close | `.smooth(duration: 0.3)` |
| Hover on chip | `.easeInOut(duration: 0.2)` |
| Drag preview scale | `.easeInOut(duration: 0.15)` |
| Prompt tap selection | `.spring(response: 0.3, dampingFraction: 0.7)` |
| Key cap press | `.spring(response: 0.2, dampingFraction: 0.6)` |
| Toggle → auto-expand delay | `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` |
| Edit sheet dismiss | `.smooth(duration: 0.3)` |
| Copied / saved feedback | default implicit animation (~0.25s) |

---

## 11. Iconography

| Convention | Detail |
|-----------|--------|
| Size (large hero) | `.system(size: 28)`, `.hierarchical` rendering |
| Size (section icon) | `.system(size: 20)` |
| Size (status / badge) | `.system(size: 11)` |
| Size (key chip) | `.system(size: 12)`, `.medium`, `.monospaced` |
| Size (keycap) | `.system(size: 25)`, `.semibold`, `.rounded` |
| Size (inline action icon) | `.system(size: 16)`, `.medium` |
| Size (badge text) | `.system(size: 10)`, `.semibold` |
| Hierarchical rendering | `.symbolRenderingMode(.hierarchical)` — default for SF Symbols |
| Coloured rainbow override | `.foregroundStyle(.blue)` on hero icon, `.blue` on status badges |
| Semantic SF Symbols | `chevron.right`, `info.circle.fill`, `plus.circle.fill`, `minus.circle.fill`, `xmark`, `arrow.clockwise`, `play.fill`, `mic.slash.circle.fill` |

---

## 12. Alerts

```swift
.alert("Alert Title", isPresented: $show) {
    Button("Cancel", role: .cancel) { }
    Button("Destructive", role: .destructive) { … }
} message: {
    Text("Detail text.")
}
```

All alerts use the same pattern. Destructive buttons must use `role: .destructive`. Confirmations use role `.cancel`.

---

## 13. Data Binding

- **State settings** in `SettingsView` are `@State` (expand/collapse flags).
- **Shared singletons** use `@ObservedObject` or `@EnvironmentObject` (e.g. `SoundManager.shared`, `PlaybackController.shared`).
- **User preferences** use `@AppStorage` — one per key (no wrapper struct).
- **Sheet / panel state**: `@State private var isShowing… = false`, with `Binding(get:set:)` when sheet closes need coordination.
- **Text input**: inline `TextField("", value: $value, …, formatter: NumberFormatter())` pattern for numeric pickers — binds to `Double` through a `NumberFormatter` rather than a string intermediate.

---

## 14. Design Principles Summary

1. **Form-first layout**. The settings view is always a `Form` with `.grouped` style. Card-style layouts only appear on standalone pages like audio input.
2. **Expandable disclosure** is the master interaction model for feature groups — controlled only by `ExpandableSettingsRow`.
3. **NSColor wrappers** everywhere. Never a bare `Color(.white)` or `Color(.black)`. Always `Color(NSColor.…)` for adaptive theming.
4. **No hard-coded margins except HStack spacing**. Padding is applied at the component level, never globally.
5. **InfoTip always inline** — sparingly, only when the user-facing label would otherwise be cryptic.
6. **Glassmorphism is optional, not required**. Card gradient applies only to non-form card layouts (Audio Input page). Settings panels themselves are flat system controls.
7. **Gradients and shadows are exclusive to CardBackground.** Form-internal rows use flat surfaces from system colours. Multistop gradients (corner aspect: large-radius card) are a device-card aesthetic, not the settings look.
8. **Keybreeze SettingsView** to consider as a reference target has already been implemented with plain SwiftUI Form pattern — it currently uses:
   - `TabView` between "General" and "Typing Lab"
   - plain `Form`/`.grouped`/`.scrollContentBackground(.hidden)`
   - no background colour override (defaults to system)
   - no `StyleConstants` or `CardBackground` usage
   - no `InfoTip` or `ExpandableSettingsRow`
