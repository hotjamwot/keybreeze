# Keybreeze Style Guide (Based on VoiceInk Design Reference)

## Foundations

### Container Layout
- Use `Form { ... }` with `.formStyle(.grouped)`
- Window background: `.background(Color(NSColor.windowBackgroundColor))`
- Settings background: `.scrollContentBackground(.hidden)` + `.background(Color(NSColor.controlBackgroundColor))`
- Separator override: `.overlay(Divider().opacity(0.5), alignment: .bottom)` on section headers

### Component Hierarchy (The "VoiceInk" Pattern)
- **Settings Groups**: Prefer `ExpandableSettingsRow` over nested sections for related feature toggles and their sub-settings.
- **Data Rows**: Use `LabeledContent` for simple key-value settings (e.g., shortcuts, paths).
- **Surface**: Rely on `Color(NSColor.controlBackgroundColor)` for primary form/setting backgrounds.

## Spacing & Layout
Discrete spacing values: 4, 6, 8, 12, 16, 20, 32, 40

| Context | Value |
|---------|-------|
| VStack between vertical sections | `spacing: 40` (page-level), `spacing: 20` (sub-group) |
| HStack between label + control | `spacing: 12` |
| Section expanded content offset | `padding(.top, 12)` before sub-rows, `padding(.leading, 4)` |
| Card/Panel horizontal padding | `padding(.horizontal, 20...32)` |
| Card/Panel vertical padding | `padding(.vertical, 16...40)` |

## Typography

### Size Tokens
| Name | Size | Weight | Design | Usage |
|------|------|--------|--------|-------|
| Display title | 22 | `.bold` | Default | Hero section title |
| Hero icon | 28 | Default | `.hierarchical` | Icons above hero title |
| Section heading | `.title2` (21) | `.semibold` | Default | Sub-group header |
| Panel header | `.headline` (17) | `.semibold` | Default | Card/sheet/popover titles |
| Body text | Default / `.body` | Default | Default | Toggle labels, button labels |
| Description / caption | 12–14 | Default | Default | `.settingsDescription()` helper = 12pt secondary |
| Subheadline secondary | `.subheadline` (13) / 14 | Default | Default | Helper text under card titles |
| Settings description | 12 | Default | Default | `.settingsDescription()` on `Text` |
| Key chip label | 12 | `.medium` | `.monospaced` | Keyboard shortcut chip |
| Badge / badge label | 10 | `.semibold` | Default | `ProBadge` PRO badge text |
| Caption / helper meta row | 11 | `.medium` / `.regular` | `.monospaced` | Metadata rows |
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

### Font Declarations
- All fonts use `font(.system(size: N, weight: X, design: Y))`
- System `.default` design is standard
- `.monospaced` for code/keys
- `.rounded` for keycap visuals

## Color

### Adaptive Colors via NSColor Aliases
| Role | Value |
|------|-------|
| Card background / surface | `Color(NSColor.windowBackgroundColor)` |
| Control / input background | `Color(NSColor.controlBackgroundColor)` |
| Separator/subtle border | `Color(NSColor.separatorColor).opacity(0.5)` |
| Tertiary/dimmed label | `Color(NSColor.quaternaryLabelColor).opacity(0.3...0.5)` |
| Shadow | `Color(NSColor.shadowColor).opacity(0.1)` |

### Semantic Colors
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

### Gradient Usage
- Only in `StyleConstants` card banking (multi-stop `LinearGradient`)
- `topLeading → bottomTrailing`

## Component Library

### Form + Section (Primary Settings Pattern)
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
- Section headers: plain `Text`
- Custom header content: `HStack { Text("..."); Spacer(); Button(...) }`

### LabeledContent (Name-Value Rows)
```swift
LabeledContent("Export Settings") {
    Button("Export") { ... }
}
```
- Label as first argument, value/control in trailing closure


### Toggle (Switch Row)
```swift
Toggle("Label text", isOn: $binding)
.toggleStyle(.switch)
```
- Label must be `Text` or `Label`

### ExpandableSettingsRow (Disclosure-Style Expand/Collapse)
```swift
ExpandableSettingsRow(
    isExpanded: $isExpanded,
    isEnabled: $isFeatureEnabled,
    label: "Feature Name"
) {
    // sub-controls: Picker, Toggle, TextField, etc.
}
```
- Entire row tappable via `.contentShape(Rectangle())` + `.onTapGesture`
- Chevron rotates 90° when expanded; dimmed (opacity 0.4) when disabled
- Animation: `.easeInOut(duration: 0.2)` on expansion transitions
- Expanded content: `.opacity.combined(with: .move(edge: .top))` transition
- Auto-expands when toggle enabled first time

### CardBackground (Frosted-Glass Panel)
```swift
CardBackground(isSelected: true/false)
```
- `RoundedRectangle` with `cornerRadius: 16`
- Multi-stop gradient fill (55% → 30% opacity window bg colour)
- Gradient border from `quaternaryLabelColor`
- Shadow: radius 10 / y 5 default, radius 15 / y 8 when selected
- Border thickness: 1.5pt

### Card Buttons (Device/Mode Selection)
```swift
Button(action: { ... }) {
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


### InfoTip (Inline Information Popover)

*Removed — InfoTip components are deprecated.*


### CompactHeroSection (Intro Banner)
```swift
CompactHeroSection(
    icon: "waveform",
    title: "Audio Input",
    description: "Configure your microphone preferences"
)
```
- Layout: `VStack(spacing: 16)` → 28pt icon → `VStack(spacing: 6)` title/description
- Padding: 20pt vertical, full-width frame

### ProBadge
```swift
ProBadge()
```
- `Text("PRO")`, 10pt semibold, white text
- `RoundedRectangle(cornerRadius: 4)` fill: `.blue.opacity(0.8)`
- Padding: horizontal 6pt, vertical 2pt
- Used inline in label position of a row

### KeyChip (Internal to EnhancementShortcutsView)
```swift
KeyChip(label: "⌘")
```
- `Text(label)`, 12pt medium monospaced, `.contiguous` default
- `RoundedRectangle(cornerRadius: 4).fill(controlBackgroundColor)`
- Border: `separatorColor.opacity(0.5)`, 0.5pt strokeBorder

### FillerWordChip
```swift
FillerWordChip(word: "um", onDelete: { ... })
```
- `RoundedRectangle(cornerRadius: 6)`, `.windowBackgroundColor.opacity(0.4)` fill
- Border: `secondary.opacity(0.2)`, 1pt
- Padding: horizontal 8pt, vertical 4pt
- X button: `xmark.circle.fill`, turns red on hover
- Hover animation: `.easeInOut(duration: 0.2)`

### FlowLayout
- Custom `Layout` struct placing subviews in rows, wrapping at available width
- Used for tag/chip grids (`FillerWordChip`, prompt grid)
- `spacing: 6` default

### SlidingPanel (Side Drawer)
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

### KeyCapView (Physical Key Rendering for Shortcut Display)
```swift
KeyCapView(text: "⌘")
```
- 25pt semibold rounded font
- Multi-layered: surface gradient → highlight gradient → border stroke → shadow → bottom-edge shadow → inner glow
- Press state: `.scaleEffect(0.95)` with `spring(response: 0.2, dampingFraction: 0.6)`

### TrialMessageView
```swift
TrialMessageView(message: "...", type: .warning)
```
- HStack icon (20pt) + title (`.headline`) + message (`.subheadline`, `.secondary`) + action buttons
- Coloured tinted background (`orange.opacity(0.1)`, `red.opacity(0.1)`, `blue.opacity(0.1)`)
- Buttons: `.bordered` and `.borderedProminent` style
- Corner radius: 12

### Status Pill (Capsule)
```swift
Label("Active", systemImage: "wave.3.right")
    .font(.caption)
    .foregroundStyle(.green)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(Capsule().fill(.green.opacity(0.1)))
```
- Repeated across device selection, priority cards

### Section Row Button (Icon)
```swift
Button {
    ...
} label: {
    Image(systemName: "gear")
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(isShowing ? .accentColor : .secondary)
}
.buttonStyle(.plain)
.help("...")
```
- Icon size: 16pt medium
- `.plain` style to prevent extra button chrome
- `.help` for tooltips

## Buttons
| Style | Modulation | Usage |
|-------|-----------|-------|
| `.bordered` | Default (tinted by `.tint()`) | Secondary action inside banner |
| `.borderedProminent` | Filled accent colour | Primary action inside banner |
| `.borderless` | Inline icon button (`.font(.system(size: 12))`) | Toolbar actions inside rows |
| `.plain` | No chrome | All icon-only buttons, card buttons, disclosure chevrons |
- Button hit areas in rows: 28×28pt circles (`.frame(width: 28, height: 28)` + `.clipShape(Circle())`)

## Toggles
```swift
Toggle(isOn: $binding) {
    HStack(spacing: 4) {
        Text("Label name")
        InfoTip("Explanation.")
    }
}
.toggleStyle(.switch)
```
- Label always inline to support `InfoTip`
- Never only a `Text` label on outer Toggle
- `.labelsHidden()` when label mirrored into custom `HStack` (seen in `ShortcutPreviewView`)

## Pickers
```swift
Picker("Label text", selection: $binding) {
    ForEach(options) { option in
        Text("Display").tag(option)
    }
}
```
- Default: no explicit `.pickerStyle()` → system-selected
- Explicit styles:
  - `.pickerStyle(.segmented)` for inline two-or-three option
  - `.pickerStyle(.menu)` for dropdown (≥5 options)

## Animations
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

## Iconography
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

## Alerts
```swift
.alert("Alert Title", isPresented: $show) {
    Button("Cancel", role: .cancel) { }
    Button("Destructive", role: .destructive) { … }
} message: {
    Text("Detail text.")
}
```
- Destructive buttons must use `role: .destructive`
- Confirmations use role `.cancel`

## Data Binding
- **State settings**: `@State` (expand/collapse flags)
- **Shared singletons**: `@ObservedObject` or `@EnvironmentObject` (e.g., `SoundManager.shared`, `PlaybackController.shared`)
- **User preferences**: `@AppStorage` — one per key (no wrapper struct)
- **Sheet / panel state**: `@State private var isShowing… = false`, with `Binding(get:set:)` when sheet closes need coordination
- **Text input**: inline `TextField("", value: $value, …, formatter: NumberFormatter())` pattern for numeric pickers — binds to `Double` through a `NumberFormatter`

## Design Principles Summary
1. **Form-first layout**: Settings view always a `Form` with `.grouped` style.
2. **Expandable disclosure**: Use `ExpandableSettingsRow` for hierarchical settings to reduce clutter in main views.
3. **Adaptive UI**: Use `NSColor` aliases for all background/surface colors to ensure correct Dark Mode contrast.
4. **Clean Rows**: Prefer `LabeledContent` for static settings.
5. **No hard-coded margins**: Padding at component level, not global.

