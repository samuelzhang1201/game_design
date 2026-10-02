# Editor-native UI — pilot (court screen + top bar)

Owner 2026-10-02: "你为什么放着原本godot做美术的功能不用，要动态导入game arts？…
导致所有场景都是空的？…为什么把所有素材的对应关系写在csv里" — then "ok" to the
proposal: the look lives in scenes and resources the editor opens, not in code
and CSV path columns. This pilot converts ONE screen and its top bar so the
owner can judge the pattern before it is carried to the rest.

**Goal:** open `scenes/court.tscn` and `scenes/top_bar.tscn` in the editor and
see the game's real look — fonts, buttons, the oak table, the map's vellum
sheet, the steward's report, the brass dial and studs, the tally board with
its icons — and edit it there; the running game draws exactly what the
editor shows (the runtime shot is unchanged).

## Rules this pilot sets

- **A look is a resource or a scene**, edited in the inspector: a Theme `.tres`
  for the game (the project's `gui/theme/custom`, so the editor uses it too),
  role fonts as `FontVariation` `.tres`, panel looks as StyleBox `.tres`
  (the custom styles `@tool` with `@export`ed fields), static art assigned
  on the node in the `.tscn`.
- **A key → art table is a typed Resource**, not a CSV `res://` column
  (`ResourceIconSet`: `Dictionary[String, Texture2D]`, UID-safe, picked in the
  inspector). Words (labels, tooltips) and tuning numbers stay in CSVs.
- **Scripts fill and drive** what the scene holds (values, signals, the
  leather fallback under `ui_war_table` 0); they no longer build static
  trees.
- A value moved into a `.tres` leaves `balance.csv` / `ui_table_palette.csv`
  when nothing else reads it; a value still shared with an unconverted piece
  stays there for it until that piece converts.

## Steps

1. `@tool` + `@export` on the look classes (`PaperStyle`, `BrassStyle`,
   `BoardStyle`, `VellumPanelStyle`, `BrassDial`, `WarTableBackdrop`,
   `ResourceIcon`, `HeraldicShield`, `TableCompass`), every `Game` read
   guarded for the editor.
2. Role fonts → `assets/fonts/roles/<role>.tres`; the theme →
   `assets/2D/ui/theme/game_theme.tres` with header / title / section type
   variations; `project.godot gui/theme/custom`; `UiPalette.role_font` reads
   the role files; `build_theme()` returns the saved theme.
3. `resource_icons.csv`'s `texture` column → `assets/2D/icons/resources/resource_icons.tres`.
4. Top bar: its runtime tree packed once into `top_bar.tscn` (exact parity),
   embedded looks swapped for the shared `.tres`; `top_bar.gd` keeps only
   filling and wiring.
5. Court: the table backdrop, the sheet and report styles, the compass in
   `court.tscn`; `court_screen.gd` stops dressing them in code.
6. Verify: suite, a runtime shot against the before shot, editor screenshots.
7. CLAUDE.md ruling; carry to the other screens only after the owner looks.
