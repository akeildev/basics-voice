# Basics Voice — design & implementation contract

Binding for every agent working on the redesign. Deviations require a written reason in your report.

## The acceptance bar (Akeil's words)

A screen is DONE only when all three hold:
1. A Paper board exists for it (file `Basics Voice — App Redesign`, id `01KYZBZTMWVG81JSY1APNDV7WH`).
2. The real screen LOOKS like the board.
3. The real screen WORKS — every control wired to the real store/service. **Nothing faked,
   mocked, hard-coded, filler, or "just an image that doesn't do anything."** Sample data is
   allowed on Paper boards only; the shipped app shows real store data exclusively.

## Scope exclusions — do not touch

- `Sources/Fluid/NotchHUD/*` (Akeil's Tasks HUD) and `Sources/Fluid/Views/NotchContentViews.swift`
  + `NotchOverlayManager` mounting logic (the recording notch). Both stay EXACTLY as they are.
- `Sources/Fluid/Theme/AppTheme.swift` and `Sources/Fluid/Persistence/SettingsStore.swift` are
  FROZEN (already re-skinned). `BasicsTokens.swift` is append-only and only the overlays cluster
  may append (dark ramp).

## Design system (light pages)

Tokens live in `Sources/Fluid/Theme/BasicsTokens.swift` (code) and as Paper file tokens (design).
Surfaces: bg `#F9FAF9` · card `#FFFFFF` · sidebar/muted `#F1F4F2` · border `#E0E4E1` ·
borderStrong `#CDD3CF`. Ink: `#0E120F` / muted `#6D736F` / faint `#949A96`.
Accent: `#2F7A53` (green500); brandSoft = green500 @ 10%; hover green600 `#266645`.
Ramp g50–g950 available. Danger `#DF202E` destructive-only. Warning `#EA9602`.

Type roles — the split is by ROLE, not size:
- **Chillax Medium 500, tracking −5%** — EVERY label: nav, section titles, setting labels, stat
  numerals, chips. Code: `.basicsLabel(size)`.
- **Chillax Variable wght 450** — button labels. Code: `.basicsButtonLabel()`.
- **Uppercase micro-labels** — 11px, tracking +8%. Code: `.basicsMicroLabel()`.
- **Karma** — PROSE ONLY: helper sentences under settings, empty states, body copy. Code:
  `.basicsProse(size)`. Test: read it in Karma, scan it in Chillax.
- **JetBrains Mono** — shortcuts, model ids, byte sizes, durations, timestamps, hex. Code:
  `.basicsMono(size)`.

Layout language: settings sit directly on the surface, separated by 1px hairlines — cards only
for hero/grouped-emphasis moments (model list, provider card, shortcut hero). Radius 6/10/14/20.
Controls right-aligned in a lane; label+helper left, flex-grow. One green moment per region.
Toggle = 44×26 pill, brand when on, borderStrong when off, white 20px knob.
Chips: 19px tall, radius full, brandSoft fill + brand text (active) or muted fill + mutedForeground.

Dark (overlays cluster ONLY): ground `#0E120F`, card `#151A17`, border white@7%, text `#F1F4F2`,
muted `#949A96`, accent **g400 `#5BA47B`** (g500 fails contrast on dark), brandSoft g400@14%.

## Naming (Akeil chose his redesigned names)

Sidebar groups: **Dictation** (Home, Voice engine, AI enhancements) · **Modes** (Command mode,
Rewrite mode, Send to Instinct, Tasks) · **Library** (Dictionary, Meeting transcription, History,
Stats) · **App** (Preferences, Changelog, Feedback).
Renames vs code: welcome→"Home" · "AI Enhancement"→"AI enhancements" · "Edit Mode"→"Rewrite mode"
(UI strings only — enum cases/keys unchanged) · "File Transcription"→"Meeting transcription" ·
"Custom Dictionary"→"Dictionary" · "Settings"→"Preferences" · "Change logs"→"Changelog" ·
"Getting Started" content becomes the Home dashboard. Sentence case everywhere, no Title Case.

## Paper rules

- ALWAYS pass `fileId: "01KYZBZTMWVG81JSY1APNDV7WH"` on every Paper call (parallel agents).
- Call `get_guide({topic:"paper-mcp-instructions"})` once before other Paper calls.
- Reference boards for pattern DNA: `AS-0` (02 — Voice engine: settings rows), `JS-0`
  (03 — Send to Instinct: shortcut hero), `2V-0` (01 — Home), `1GV-0` (09 — History master-detail).
  Screenshot them before designing.
- Window frame: 1360×900, sidebar 264 fixed, main 1096 fixed `overflow:hidden`. Clone the sidebar
  from an existing board (`<x-paper-clone node-id="ER-0">` works) rather than rebuilding it.
- A board must cover EVERY control and EVERY state in its inventory slice — secondary states as
  additional artboards named `NN — <screen> · <state>`. No control left undesigned.
- Overlay boards use the dark palette above on a transparent/desktop-tinted ground.

## Implementation rules

- Wire to the REAL stores (`SettingsStore.shared`, `HistoryStore`, `TasksStore`, ASR services).
  Never invent a value; never leave a dead button. If a board shows a value, bind it.
- Use the `.basics*` modifiers and `theme.palette` — no raw hex, no `.system(size:)` in edited code.
- Keep enum cases, UserDefaults keys, and notification names unchanged — UI strings only.
- Do NOT run `xcodebuild` (a single build agent runs after all edits). Optional per-file syntax
  sanity: `swiftc -parse`.
- Only touch files your cluster owns (listed in your brief). Report any cross-file need instead
  of editing.
- Delete the 7 UNREACHABLE code regions listed in REDESIGN.md if they are in your files.

## Tracker

`REDESIGN.md` — flip `paper`/`code` cells only with evidence (board id / files+lines). The `proof`
column is flipped ONLY by the proof agent from a screenshot of the running app.
