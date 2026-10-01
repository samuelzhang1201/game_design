# The War Table — the main screen's chrome (design)

Owner 2026-10-01: after three rounds of mock-ups (A Chancery / B War Table / C
Chronicle, then four B and two C variants), the owner chose **B3 + C1's
bookmarks** — "就用这个，在游戏里做出来". The approved picture is
`B3C1_daylight_bookmarks` (the session's scratchpad `ui/round2/`); this spec
turns it into the game.

## What the player sees

The whole screen is a **pale oak table by daylight**. Everything on it is an
object lying on the table, lit from the upper left, casting its shadow down and
to the right, with one broad soft shaft of window light across it.

| Piece | Today | War Table |
|---|---|---|
| Behind everything | flat `BG_SCREEN` colour | tiled oak planks (`assets/2D/ui/war_table/table_oak.jpg`, Poly Haven `old_planks_02`, CC0) + a window-light shaft and a vignette |
| Map panel | flat leather card, 4 px margin | a **vellum sheet** with a deckled edge, a double ink rule round the map, a soft shadow; the scale label sits in the sheet's top margin |
| Top bar | leather bar: date, clock buttons, two purse rows, Menu | no bar: a **brass date dial** (the day) with the season and year beside it and the clock as four brass studs; the two purses on a **dark oak tally board** with brass nails, centred; Menu as plain small capitals on the wood |
| Left column | leather column, the realm dashboard | the **steward's report**: aged paper drawn a degree off square behind straight content, a brass pin at its head, dark ink, red rubrics (¶ headers); temper as **tally marks** (one per ten points, gated in fives) beside the number; the people as a sentence ("Of every hundred souls, N live in towns…"); the host as one line of counts. It **scrolls** (fixes today's overlap with the news bar) |
| Enter the Council | gold primary button in the map's corner | a **red wax seal** (the one primary action) with a paper tag under it naming the order |
| Bottom bar | row of flat word tabs | **silk bookmarks** hanging from under the sheet's lower edge, swallow-tailed; lenses in green on the left, screens on the right coloured by group (realm/war room red, families/laws blue, religion/ledger/missive brown) — colours are data, `data/ui_bookmarks.csv` |
| News ticker | translucent glass strip | a **paper slip** between the two bookmark groups |

What stays: the 3D map and everything drawn on it (compass, counters, names),
the audience window, the right council column's content, every card's content
and every order. No information is removed; the pie becomes a sentence with
the same two percentages, the host bars one line with the same counts.

## Rules

- Every number is `balance.csv` (`ui_table_*`); colours are `data/ui_table_palette.csv`
  and `data/ui_bookmarks.csv`; the art lives in `assets/2D/ui/war_table/`.
- `ui_war_table` 1 turns the look on; 0 keeps today's dark leather chrome
  untouched (the record and the fallback, like `ui_font_scheme` 0).
- Paper surfaces take **dark ink**: the column cards read their ink through
  `UiPalette.ink(role)` (soft / muted / dim / accent / rubric / track), which is
  the paper ink under the war table and today's constants otherwise; a paper
  column also gets a paper Theme so unstyled labels follow.
- Floating windows (audience window, events, menus, popups) stay dark leather:
  they are held up to the eye, not lying on the table.
- Shadows fall down-right (`ui_table_shadow_dx/dy`), one light for the table.
- Nothing is rotated that takes input: the report's PAPER is drawn rotated,
  its text and buttons stay square.
- The deckle is deterministic (a seed per surface), presentation only.

## Not in this round

- The compass stays in the map (its click turns the view north); moving it onto
  the table is a follow-up.
- The minister miniatures beside the seal wait for a real "who waits to be
  heard" source; the seal's tag says only the order.
- The conversation screen shares the table, sheet, top bar, report and
  bookmarks; its right-hand dialogue column stays dark leather this round.
