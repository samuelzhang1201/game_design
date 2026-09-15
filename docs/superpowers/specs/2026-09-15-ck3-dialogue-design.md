# CK3-style audience window and the dark theme — design

Owner request 2026-09-15: "optimise the character dialogue screen, in the
style of Crusader Kings III". Decisions taken in chat the same day:

- **Layout:** a centred *audience window* over the map while someone holds
  the stage (the recommended option). It replaces the dossier-over-the-talk
  arrangement of the right column (owner ruling 2026-09-10).
- **Tone:** the WHOLE UI goes back to dark — leather, dark wood and gold —
  reversing the bright modern theme of 2026-09-13. The map is not the UI and
  keeps its look.
- **No art generation** was asked for. The window's backdrop is drawn in code;
  a `backdrop` column on `data/locations.csv` is the slot for a painting later.

## 1. The dark palette

`UiPalette` stays the single source. Its constants flip to a CK3 register —
each keeps its bright predecessor in a comment, as the bright ones kept the
parchment values:

| constant | dark | role |
|---|---|---|
| `BG_SCREEN` | `#0f0d0b` | the desk behind the panels |
| `PANEL_BG` | `#1f1a15` | card body — dark leather |
| `CHIP_BG` | `#2d251d` | buttons, chips |
| `CHIP_HOVER` / `CHIP_PRESSED` (new) | `#3a2f24` / `#46382a` | the states that were literal light blues |
| `INPUT_BG` (new) | `#15110d` | text inputs (were white) |
| `TROUGH` (new) | `#14110d` | the empty part of a bar |
| `GOLD` (accent) | `#e0bb6a` | headers, names — gold again, not royal blue |
| `BORDER_GOLD` | `#a88a4c` | trim |
| `TEXT_SOFT` / `TEXT_MUTED` / `TEXT_DIM` | `#eee3cb` / `#bfae8f` / `#8a7d68` | ink, light on dark |
| `POSITIVE` / `NEGATIVE` | `#7fcf6e` / `#ec6f5e` | readable on dark |
| `EDGE` | `#4b3e30` | the quiet edge |
| `ORNAMENT_TINT` (new) | `#c9a45a` | the panel ornament's ink |

Skill and tool colours, `chart_palette.csv`, the location kind tints, the
speaker name colours and the map card's work-box overlay are brightened or
darkened to match. `VellumPanelStyle` gains a `tint`: the ornament plate is
dark ink on clear, invisible on a dark card, so it is drawn in gold.

A test pins the contrast: the panel is dark, the ink light, and the accent
readable on the panel.

## 2. The audience window

`scenes/conversation.tscn` gains `%AudienceLayer`, placed exactly over the
map panel, holding a faint dim and a centred `%AudienceWindow` (a
`PanelContainer`, at most 780×540 design px, never larger than the map less a
margin). The window holds, like a CK3 interaction:

- **Header banner** `%AudienceTitle`: where the scene takes place (the
  location's label), or the event's title.
- **Left — the person.** `%PortraitFrame`: an `AudienceBackdrop` (a vertical
  wash in the location kind's tint into near-black, a warm floor glow and a
  vignette; a `backdrop` painting cover-cropped when the location names one)
  with `%PortraitBox` over it, the full art cropped head to waist. Under it,
  `%DossierHead` — only for a person: the name plate (`%MinisterName`,
  `%MinisterTitle`), opinion (`%OpinionBar`, `%OpinionValue`, whose tooltip
  lists the last five opinion changes WITH their reasons — invariant 4 made
  visible), `%TraitChips` (tooltip: the trait's notes) and `%SkillBadges`
  (five short coloured badges, tooltip the skill's name).
- **Right — the words.** `%NameLabel` (the speaker), `%TabsRow`
  (BIO / SKILLS / TIES), `%SpeechScroll` holding `%SpeechLabel` — this beat's
  exchange only: the speaker's line, your replies, the Herald's outcome and the
  ledger — or `%DossierPages` in its place while a page is open;
  `%RepliesBox` (CK3 option buttons: dark, a gold edge on hover, the
  suggestion's trade-off and gold cost as the tooltip); and the talk row,
  `%FreeText` and `%ContinueButton`.

Events and the opening narration use the SAME window (CK3's events and
interactions share a frame): an event shows the council medallion, its title
in the banner, the authored scene in the speech, the choices as options; the
narration hides the portrait side. `event_popup()` returns the window. The
MOVE list keeps the small centred popup (`%EventPopup`, renamed in role only).

## 3. The right column

`%DialoguePanel` keeps LEAVE, the room (location, occupants, MOVE) and the
**full transcript** (`%DialogueScroll` / `%TextLabel`), filtered by the
selection as before. Its width on this screen is `ScreenLayout.TALK_WIDTH`
(320): the talk moved into the window, so the map — and the window over it —
gets the room back. The court keeps `RIGHT_WIDTH`.

## 4. What does not change

The beat queue, every Game call, the selection rules, the stale-callback
guards, the staggered reveal and every test seam's meaning. No engine file is
touched.

## 5. Testing

- Existing `test_conversation_scene.gd` and `test_ui_rework.gd` keep passing;
  the one test that asserted the dossier stands in the right column is
  rewritten to the new ruling (inside the window, over the map).
- New: the window is up on a minister beat and inside the map's rect; the
  opinion tooltip carries a logged reason; an event beat uses the window with
  its choices inside it; a suggestion's option carries its trade-off; the
  palette contrast test.
- `tools/snapshot_screen.gd --resolution` at 1280×720 and 2560×1600.
