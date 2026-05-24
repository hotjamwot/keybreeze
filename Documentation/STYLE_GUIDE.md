# Keybreeze Style Guide

> **Design philosophy**: Scandinavian-Japanese minimalism — clean, intentional, and restful. Dark tones, generous rounding, and clear hierarchy. Every element earns its place.

---

## 1. Visual Hierarchy

### Settings Window Layout
```
┌────────────────────────────────────────────────┐
│ Sidebar           │  Detail                    │
│ (150–220pt)       │  ┌──────────────────────┐  │
│ ┌──────────────┐  │  │ Status Section       │  │
│ │ General      │  │  │  ┌────────────────┐  │  │
│ │ Typing Lab   │  │  │  │ Toggle         │  │  │
│ └──────────────┘  │  │  │ Status pill    │  │  │
│                    │  │  └────────────────┘  │  │
│                    │  │ Statistics Card       │  │
│                    │  │ AI Settings Section   │  │
│                    │  │  ┌────────────────┐  │  │
│                    │  │  │ Picker         │  │  │
│                    │  │  │ ExpandableRow  │  │  │
│                    │  │  │  ┌ sub-ctrl ┐  │  │  │
│                    │  │  │  └──────────┘  │  │  │
│                    │  │  └────────────────┘  │  │
│                    │  └──────────────────────┘  │
└────────────────────────────────────────────────┘
```

### Hierarchy Levels (most prominent → least)
| Level | Element | Visual Weight |
|-------|---------|--------------|
| **1** | **Sidebar tab** (selected) | Accent background tint + bold label |
| **2** | **Section header** | `Text("Title").font(.title2).fontWeight(.semibold)` |
| **3** | **Card/Panel** | Rounded rect with subtle background fill |
| **4** | **Row label** | Standard body text, secondary for descriptions |
| **5** | **Expandable sub-content** | Indented, lower opacity transition |
| **6** | **Footer / metadata** | `.settingsDescription()` — 12pt secondary |

### Navigation Pattern
- **Sidebar tabs** (HSplitView + List) for top-level sections
- **Form Sections** for grouping related settings
- **ExpandableSettingsRow** for optional sub-settings under a toggle
- **Panels** (VStack with divider) for standalone configuration blocks

---

## 2. Colour Palette

### Dark-First Adaptive Colours (all via `NSColor` aliases)
| Token | NSColor Alias | Usage |
|-------|--------------|-------|
| `surfaceBackground` | `NSColor.windowBackgroundColor` | Card, panel, sliding drawer background |
| `controlBackground` | `NSColor.controlBackgroundColor` | Form rows, input fields |
| `separator` | `NSColor.separatorColor.opacity(0.5)` | Dividers between sections |
| `labelPrimary` | `NSColor.labelColor` | Primary text |
| `labelSecondary` | `NSColor.secondaryLabelColor` | Descriptions, subtitles |
| `labelTertiary` | `NSColor.tertiaryLabelColor` | Placeholder, empty state |
| `labelQuaternary` | `NSColor.quaternaryLabelColor` | Subtle borders, dimmed elements |
| `shadow` | `NSColor.shadowColor.opacity(0.1)` | Card shadows |

### Accent & Semantic Colours
| Role | Colour | Use |
|------|--------|-----|
| **Primary accent** | `.accentColor` | Active indicator, selected state, key stat |
| **Success** | `.green` — `.green.opacity(0.1)` capsule bg | "Active" / "Granted" status |
| **Warning** | `.orange` — `.orange.opacity(0.1)` capsule bg | "Required" / caution state |
| **Error / destructive** | `.red` / `.red.opacity(0.1)` | Deletion, error messages |
| **Inactive / neutral** | `.secondary` — `.secondary.opacity(0.1)` bg | Disabled chevrons, empty labels |

### Surface Convention
- Forms: `Color(NSColor.controlBackgroundColor)` full-background
- Cards: `Color(NSColor.windowBackgroundColor)` with rounded rect
- Never use hard-coded white/black — always adaptive

---

## 3. Spacing System

### Token Scale
```
base: 4     sm: 8    md: 12    lg: 16    xl: 20    2xl: 32    3xl: 40
```

### Layout Spacing Chart
| Context | Token |
|---------|-------|
| VStack between page-level sections | `spacing: 40` |
| VStack between sub-groups | `spacing: 20` |
| HStack between label + control | `spacing: 12` |
| Expanded content inset | `.padding(.top, 12)` + `.padding(.leading, 4)` |
| Card horizontal padding | `.padding(.horizontal, 20...32)` |
| Card vertical padding | `.padding(.vertical, 16...40)` |
| Stack between icon + text in card | `spacing: 12` |
| Stack between title + description | `spacing: 6` |
| Stack between toggle label + InfoTip | `spacing: 4` |

---

## 4. Typography

### Type Scale
| Token | Size | Weight | Design | Usage |
|-------|------|--------|--------|-------|
| Display title | 22 | `.bold` | `.default` | Hero/intro section title |
| Hero icon | 28 | — | `.hierarchical` rendering | Icon above hero title |
| Section heading | `.title2` (21) | `.semibold` | `.default` | Form section header |
| Panel header | `.headline` (17) | `.semibold` | `.default` | Card/sheet/popover title |
| Body | `.body` / default | `.regular` | `.default` | Toggle labels, button text |
| Subheadline | `.subheadline` (13) | `.regular` | `.default` | Helper text under card titles |
| Description | 12 | `.regular` | `.default` | `.settingsDescription()` helper |
| Key chip label | 12 | `.medium` | `.monospaced` | Keyboard shortcut chips |
| Badge text | 10 | `.semibold` | `.default` | PRO badge, status badges |
| Caption / meta | 11 | `.medium` | `.monospaced` | Metadata rows |
| Stat counter | `.body.monospacedDigit()` | — | — | Numeric statistics |

### Helper
```swift
extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
```

### Font Declaration Pattern
```swift
.font(.system(size: N, weight: X, design: Y))
```
- Default design: `.default`
- Monospaced: `.monospaced` (keyboard keys, code)
- Rounded: `.rounded` (keycap visuals)

---

## 5. Corner Radii

| Element | Radius | Shape |
|---------|--------|-------|
| Card / panel background | `16` | `.RoundedRectangle` |
| Statistics card | `10` | `.RoundedRectangle` |
| Key chip | `4` | `.RoundedRectangle` |
| Filler word chip | `6` | `.RoundedRectangle` |
| Trial message banner | `12` | `.RoundedRectangle` |
| Pro badge | `4` | `.RoundedRectangle` |
| Status pill | Capsule | `.Capsule()` |
| Button hit area (icon) | `28×28` circle | `.clipShape(Circle())` |

---

## 6. Component Patterns

### 6.1 Form (Primary Settings Container)
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
.background(Color(NSColor.controlBackgroundColor))
```
- **Section headers**: plain `Text` only
- **Section footers**: optional `.settingsDescription()` text
- Each `Section` is a distinct group in the settings hierarchy

### 6.2 Sidebar (Navigation)
```swift
List {
    ForEach(Tab.allCases) { tab in
        Button { selection = tab } label: {
            Label(tab.rawValue, systemImage: tab.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selection == tab
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
    }
}
.listStyle(.sidebar)
.frame(minWidth: 150, idealWidth: 170, maxWidth: 220)
```

### 6.3 ExpandableSettingsRow (Sub-Hierarchy)
```swift
ExpandableSettingsRow(
    isExpanded: $isExpanded,
    isEnabled: $isFeatureEnabled,
    label: "Feature Name"
) {
    // sub-controls: Picker, Toggle, TextField, etc.
}
```
- **Entire row tappable** via `.contentShape(Rectangle())` + `.onTapGesture`
- **Chevron**: rotates 90° when expanded; opacity 0.4 when disabled
- **Animation**: `.easeInOut(duration: 0.2)`
- **Transition**: `.opacity.combined(with: .move(edge: .top))`
- **Auto-expand**: when toggle is enabled for first time

### 6.4 LabeledContent (Name-Value Rows)
```swift
LabeledContent("Label") {
    // trailing value / control
}
```
- Use for simple key-value settings (shortcuts, paths, export buttons)
- Label as first argument, control in trailing closure

### 6.5 Card / Panel
```swift
RoundedRectangle(cornerRadius: 10)
    .fill(Color.accentColor.opacity(0.08))
```
- Statistics cards, info panels
- Prefer subtle opacity fills over heavy borders
- Generous padding inside: `.padding(xl)`

### 6.6 Status Pill (Capsule)
```swift
Text("Active")
    .font(.caption)
    .fontWeight(.medium)
    .foregroundStyle(.green)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(Capsule().fill(.green.opacity(0.1)))
```
- Status indicators: Active, Granted, Required, Disabled
- Semantic colours: green (success), orange (warning), red (error)

### 6.7 Sliding Panel (Side Drawer)
```swift
.slidingPanel(isPresented: $isPanelOpen, width: 400) {
    // panel content
}
```
- Semi-transparent `Color.black.opacity(0.1)` overlay with dismiss tap
- Slide from off-screen via `.transition(.offset(x: panelWidth))`
- Panel background: `NSColor.windowBackgroundColor`
- Leading stroke divider + left shadow
- Animation: `.smooth(duration: 0.3)`

### 6.8 Button Styles
| Style | Modulation | Usage |
|-------|-----------|-------|
| `.bordered` | Default (tinted by `.tint()`) | Secondary action inside banner |
| `.borderedProminent` | Filled accent colour | Primary action inside banner |
| `.borderless` | Inline icon (12pt) | Toolbar actions inside rows |
| `.plain` | No chrome | Icon-only buttons, card buttons, chevrons |

---

## 7. Toggles

```swift
Toggle(isOn: $binding) {
    HStack(spacing: 4) {
        Text("Label")
        InfoTip("Explanation.")
    }
}
.toggleStyle(.switch)
```
- Label always inline to support `InfoTip`
- Never bare `Text` as outer label — wrap in HStack

---

## 8. Pickers

```swift
Picker("Label", selection: $binding) {
    ForEach(options) { option in
        Text("Display").tag(option)
    }
}
```
- Default: system-selected style (let macOS decide)
- Explicit `.pickerStyle(.segmented)` for 2–3 inline options
- Explicit `.pickerStyle(.menu)` for 5+ dropdown options
- Use `.labelsHidden()` when label shown via custom HStack

---

## 9. Animations

| Context | Duration / Spring |
|---------|------------------|
| Expand / collapse | `.easeInOut(duration: 0.2)` |
| Sliding panel | `.smooth(duration: 0.3)` |
| Hover (chips) | `.easeInOut(duration: 0.2)` |
| Keycap press | `.spring(response: 0.2, dampingFraction: 0.6)` |
| Toggle → auto-expand delay | `DispatchQueue.main.asyncAfter(0.1)` |
| Copied / saved feedback | Default implicit (~0.25s) |

---

## 10. Iconography

| Context | Size | Details |
|---------|------|---------|
| Hero / display icon | 28pt | `.hierarchical` rendering |
| Section icon | 20pt | Standard SF Symbol |
| Inline action icon | 16pt `.medium` | Gear, close, plus/minus |
| Status / badge | 11pt | System default weight |
| Key chip | 12pt `.medium` `.monospaced` | ⌘, ⌥, ⇧ |
| Keycap | 25pt `.semibold` `.rounded` | Physical key rendering |
| Badge text | 10pt `.semibold` | PRO label |

**SF Symbol conventions:**
- `chevron.right` — disclosure indicator
- `info.circle.fill` — InfoTip
- `xmark.circle.fill` — remove / delete
- `gearshape` — settings
- `arrow.clockwise` — reset / refresh

---

## 11. Design Principles

1. **Form-first layout** — Settings always use `Form` with `.grouped` style.
2. **Sidebar navigation** — Top-level sections via sidebar tabs; sub-settings via `ExpandableSettingsRow`.
3. **Dark-adaptive** — All colours via `NSColor` aliases. Never hard-code white/black.
4. **Minimal chrome** — No unnecessary borders, strokes, or gradients. Let spacing and rounding define groups.
5. **Generous rounding** — Corner radii of 10–16pt for all surfaces. Softer is better.
6. **Restrained hierarchy** — Section header → Row → Expandable sub-content. Three levels max.
7. **Intentional spacing** — Use the token scale. Never arbitrary values.
8. **Consistent type** — System fonts only. No custom typefaces.