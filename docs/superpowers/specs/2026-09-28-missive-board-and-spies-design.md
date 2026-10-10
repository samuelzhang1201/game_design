# Missive board and spy couriers (sub-project B of the missive system) — design

Sub-project B of the owner's missive system (2026-09-27). **A courier core**
is merged (`2026-09-27-courier-core-design.md`: couriers ride the road
network, army orders take effect on delivery, regional weather). **C
interception** is deferred with enemy AI. **D art** is pending: the courier
paintings and 3D riders.

B makes information a resource:
- a **fog of knowledge** over land the crown does not control;
- **spy couriers** sent to any point of the map, who report what they saw
  with honest uncertainty;
- the **Missive board**: every letter the crown receives, pinned in four
  credibility columns.

## Owner rulings (2026-09-28)

- **Four columns:**
  - **Ground truth**: the steward's monthly report on the provinces the crown
    controls.
  - **Highly credible**: an army order's delivery receipt, and spy reports of
    good quality.
  - **Worth consulting**: reserved for C's intercepted letters; empty in B.
  - **Rumour**: spy reports of poor quality.
- **An ordinary courier's report is a delivery receipt plus the regiment's
  state**, written on the day he delivers. He still never rides back (A's
  ruling).
- **Cards show the latest intelligence.** A map card shows the newest
  report's estimate with its source, date and credibility; the board holds
  the letters themselves.
- **Interruptions:**
  - a spy's arrival pauses the clock and opens a report dialog, which seals
    into a wax-sealed envelope that flies, spinning, into the Missive tab;
  - receipts and monthly reports never interrupt: a small envelope flies from
    the news bar into the tab.
- **Accuracy** is one roll per mission from the engine's seeded RNG,
  adjusted by the place:
  - harder abroad, behind walls and in bad weather;
  - easier at home.

  Quality decides both the column and how wide and how biased the estimates
  are.
- **Board layout B:** four columns on the left two-thirds, and a reading desk
  on the right third holding the open letter and a **Show on map** button.
- **Sending a spy:** a right click on the ground ("Send a spy here…"), or a
  **Send a spy** button on any manor, province or town card. Both issue one
  order.
- **Approach 1:** a single knowledge gate, `Intel`, that every panel asks.

## 1. Engine

All engine code is pure `RefCounted` and headless-testable. It uses no
wall-clock, and state holds whole numbers only.

### Missives

`GameState.missives` is an Array of Dictionaries, saved whole, with
`GameState.next_missive_id`. Each missive holds:

```
id        int, monotonic
kind      "receipt" | "monthly" | "spy"
column    "truth" | "credible" | "consult" | "rumour"
day       absolute day it arrived
subject   {kind: "manor"|"province"|"burg"|"regiment"|"point", code_or_cell, x, y (pack px, whole)}
title     short, e.g. "Spy report — Greystone manor"
facts     Array of {key, label, exact: int} or {key, label, lo: int, hi: int} or {key, label, text}
read      bool
```

- **Sorting and the cap.** The board lists missives newest first, and each
  column is capped at `missive_keep_per_column` (40): the oldest leaves when a
  41st arrives.
- **The only writer.** `MissiveLog.add(repo, state, missive) -> int` writes
  missives, applies the cap and returns the id.
- **Fact keys** come from `data/intel_facts.csv`:

  | key | label | tier words (low → high) |
  |---|---|---|
  | `people` | People | — |
  | `tax` | Tax a month | — |
  | `output` | Chief good | — |
  | `wealth` | Wealth | poor, middling, rich |
  | `troops_own` | Our troops nearby | — |
  | `troops_foreign` | Foreign troops nearby | — |
  | `holder` | Held by | — |
  | `stance` | Stance | — |

- **Rounding estimates.** `data/intel_facts.csv` also sets how an estimate is
  rounded, `round_to`, so a range reads "2,800–3,200" and never
  "2,837–3,151".

### The three sources

**Receipt (`credible`).**
- `CourierSystem._deliver` (A) now also calls `MissiveLog.add`.
- It records that the order arrived, and the regiment's morale, supplies,
  wounded, ground (`ArmySystem.terrain_of`) and weather that day, all exact.
- A stale order (A's supersession rule) writes a receipt that says so.

**Monthly report (`truth`).**
- `TickEngine.advance`, after the month's settlement, writes one missive
  titled "Steward's report — <month>".
- It covers each controlled province's tax, strategic and civil goods, and
  people, exactly, plus the month's change against the previous report.
- It has no subject point, and its "Show on map" opens the home province.

**Spy report (`credible` or `rumour`).**
- A spy is a courier of `kind = "spy"`.
- A's ride is reused whole: the road network, the tier, the weather, and his
  daily ride.
- The difference is his `target`: a point `{x_m, y_m}`, not a regiment. His
  path is set once at dispatch, with no re-aim.
- On arrival `SpySystem.observe(repo, state, courier)` builds the missive and
  returns an event `{type: "spy_report", missive: id}`. The courier is then
  removed.

### What a spy sees (`SpySystem.observe`)

He looks at the point his path ends at:

- **the manor under it** (`MapEconomy.cell_at` → `MapManors`): people, tax a
  month (`RealmEconomy.line_of`), chief good and its units, holder;
- **its province**: the wealth tier (below);
- **troops within `spy_radius_km`** of the point, summed headcount, split into
  our regiments (live positions) and foreign regiments (the pack's rows, which
  stand still until enemy AI exists);
- **the stance**: the kingdom holding the point, as the player realm's stance
  toward it in `diplomacy.csv` ("Neutral", "Suspicion", …), or "our realm".

At sea he sees only troops.

### Accuracy

1. **The roll.** `q = rng.randi_range(0, 999)` from `GameState.rng`. This is
   the engine's one seeded stream, so it is deterministic and saved.
2. **The adjustments.** `q` is then shifted by the `data/spy_difficulty.csv`
   rows that apply, each an integer per-mille shift:
   - `foreign` −150;
   - `walled` −100 (a town with walls or a citadel in that cell);
   - `weather_<kind>` (rain −50, snow −100, blizzard −200);
   - `home` +150 (the player's own realm).
3. **The column.** `q >= spy_credible_threshold` (500) is `credible`; lower is
   `rumour`.
4. **Each numeric fact** gets its own range from the true value `v`:
   - **half-width** = `v × lerp(spy_width_best, spy_width_worst, 1 − q/1000)`,
     per mille, from 100‰ to 450‰;
   - **bias**, only when `q < spy_credible_threshold`: one extra roll gives a
     shift of ± up to `spy_bias_max` (300‰) of `v`, the same sign for every
     fact in that report ("it all looked bigger than it was");
   - **rounding**: `lo` and `hi` go out to the fact's `round_to`, `lo ≥ 0`.
5. **Text facts** (holder, stance, chief good) are reported exactly when
   `q >= spy_text_threshold` (300), else as "unclear".
6. **Two spies to the same place draw different rolls**, so their reports
   differ. This is intended.

### The `Intel` gate

`Intel` (`scripts/engine/intel.gd`) is the only place that decides what the
player knows.

- **`Intel.level(repo, state, subject) -> "full" | "general" | "basic"`:**
  - `full`: a manor, town or province in a province the crown controls
    (`MapManors.controlled_provinces`), and the player's own regiments;
  - `general`: the rest of the player's realm;
  - `basic`: every foreign subject.
- **`Intel.fact(repo, state, subject, key) -> {text, source, day, column}`:**
  - `full` → the exact value, source "own records";
  - otherwise the newest missive carrying that key for that subject (matched
    by manor cell, then province, then within `intel_match_km` of the point)
    → its range as text ("≈ 2,800–3,200"), with its source, day and column;
  - else `general` → the tier word from `intel_facts.csv` (wealth by the
    province's tax per person against the realm's terciles; people and troops
    as "hundreds / thousands / many thousands" by `intel_magnitude_*`
    thresholds);
  - else `basic` → "—", except `holder`, `stance` and `wealth`, which are
    always given in words.
- **`Intel.wealth_tier(repo, state, province)`** is the realm-independent
  rich / middling / poor tier, from tax per person against every province's
  terciles (cached per month).

### Closing the leaks

Every panel that shows a number about land or troops asks `Intel` instead of
reading the ledger. Each leak point below becomes an `Intel` reader:

- **The cards.**
  - `MapObjects.province_card` and `manor_card` read `Intel`; their `known`
    becomes `Intel.level`.
  - `burg_card` today is always `full`; population, wealth and treasury now
    come through `Intel`.
- **`MapObjects._kingdom_lines` / `CountryPanel`.** A foreign kingdom shows
  its capital, neighbours, stance and wealth tier; population, provinces and
  towns become magnitude words.
- **`MilitaryPanel`'s "Neighbours" chart.** It shows `Intel`'s troop words or
  the latest estimates, never pack totals.
- **`ManorMasterPanel`.** The "all realms" scope and non-controlled rows show
  `Intel` text; sorting uses exact values only where `level == full`.
- **The MANORS theme's output badges** are drawn only on manors at
  `level == full`.
- **`army_card`** for a foreign regiment, which only appears in dev mode:
  `Intel` magnitude words.

**DEV MODE bypasses the gate** (`Intel` returns `full` everywhere when the
pause menu's dev switch is on), so the owner can still inspect.

A test scans those panel scripts for direct reads of the fog-sensitive ledger
paths and `world_row("economy"…)`, and fails on any read that does not go
through `Intel`.

### Orders and money

- **`SPY_SEND {x, y}`** is an ordinary action:
  - its row is in `action_signatures.csv` and its cost in `order_costs.csv`
    (gold, reasoned);
  - it validates that the point is on the map and that the chest holds
    fee + cost (A's rule);
  - it executes `CourierSystem.dispatch_spy`, which records a point target.
  - The spy row in `courier_kinds.csv` is `spy, 900, 8, 1`.
- **Missives cost nothing** and change no metric, so they carry no ledger
  line. Their creation is logged in the missive itself.

### Determinism and saves

- The only randomness is `GameState.rng`, drawn in a fixed order: a spy's
  quality roll, then his bias roll, at his delivery, with couriers in id
  order.
- `missives` and `next_missive_id` save and load exactly. An old save has
  none.

## 2. Presentation

**The Missive tab.**
- `BottomBar.TABS` gains `MISSIVE` after `RELATIONSHIP`, with the count of
  letters not yet SEEN drawn on the button (`BottomBar.set_badge(tab, n)`;
  none, just "MISSIVE"). Owner 2026-10-10 ("玩家看过了信息就不算新的了，括号的
  数字只显示玩家没看过的"): `GameState.missives_seen_id` (saved; an old save
  takes `next_missive_id`, every letter seen) is the highest id seen and
  `MissiveLog.unseen` counts the letters above it not marked `seen` alone.
  `Game.mark_missives_seen()` sees them all whenever a board is in front of
  the player — the overlay shown, the WAR ROOM's easel faced — and again as
  letters land while it is; a spy's report opened in its dialog is seen alone
  (`mark_missives_seen(id)`). `read` stays the note's own gold edge, set only
  by selecting it.
- `GameRoot` opens and closes `MissiveScreen` like the relations screen,
  stacked in `_switch_to`.

**`MissiveScreen`** is `scenes/missive_screen.tscn` with
`scripts/ui/missive_screen.gd`: an authored scene, full rect, dimmed behind a
wooden frame, with CLOSE top-right.
- **Left 2/3, the board.** Four `MissiveColumn`s, each a carved header plaque
  over a vertical scroll of `MissiveNote`s:
  - a note is a pinned parchment slip with the title, the place and the date;
  - an unread note wears a gold edge;
  - there is no dragging between columns: the column is the letter's source
    and quality.
- **Right 1/3, the reading desk: `MissiveLetter`.**
  - the selected letter at full size: title, date, credibility, and the fact
    list (exact values, or "≈ lo–hi");
  - **Show on map** closes the board, centres the 3D view on the subject and
    opens its card in the left column;
  - selecting a letter marks it read.
- **Empty states.** An empty column reads, faintly, what arrives there. The
  desk with nothing selected reads "Choose a letter".

**The spy report dialog, `MissiveReportPopup`.**
- It is a scene centred over the map panel, in the audience window's style:
  - the spy's painting on the left (D's courier art; hidden until installed);
  - the report on the right;
  - a **Seal** button.
- `GameRoot` stops the clock and opens it on a `spy_report` event. Closing it
  plays the envelope flight.
- **It never restarts the clock** (A's principle): play resumes only by the
  player's hand.

**`EnvelopeFlight`** is a reusable node and the project's first Tween. It
animates a snapshot rectangle:
1. it shrinks toward an envelope texture over `missive_seal_s`;
2. it follows a quadratic arc to `BottomBar.button("MISSIVE")`'s rect over
   `missive_fly_s`, turning `missive_fly_turns` times;
3. the tab pulses and its badge increments at the end.

For receipts and monthly reports the flight starts, small, from the news
bar's position, and there is no dialog.

**Sending a spy.**
- **A right click on the ground.** `Map3DView` gains the signal
  `ground_menu_requested(pack_px, at)`, raised by `right_click` when nothing
  is under the cursor. That costs view forwarder lines only; raise the shape
  cap to match, with its comment.
- `SpyOrderMenu` (`scripts/ui/`, `%SpyOrders` in `court.tscn` and
  `conversation.tscn`, following `ArmyOrderMenu.follow`) offers one row:
  "Send a spy here — ≈N days · F gold".
- **The cards.** Manor, province and town cards gain a **Send a spy** button
  (`MapDetailPanel`), targeting the card's `center`.
- **On the map, a spy** rides in A's courier layer. His card reads "Spy bound
  for <place>".

**Cards under the fog.**
- A number known by estimate shows "≈ lo–hi" with a small tag, coloured by
  column (`political_palette` `intel_<column>`), e.g. "spy · Spring 12".
- A number not known at all shows "—", with **Send a spy** close by.

**News.** A spy's arrival reads "The spy at <place> reports." Receipts and
monthly reports keep A's lines; the steward's report is "The steward's report
for <month> is in."

## 3. Art (the Flux hand-drawn pipeline, prompts shown to the owner before any run)

New library entries on the UI chapter, in the game's v2 colour style:
- a wooden frame (nine-sliced);
- a cork board ground;
- a parchment note and a parchment letter;
- a wax-sealed envelope;
- a pin;
- four column plaques, which can be one plaque with the text drawn over it.

`install_map_art.py missive` sizes each file for its use (the
`asset-resolution-per-use` rule). Until they are installed, `UiPalette`'s flat
dark styles stand in; the art is referenced from a
`data/missive_art.csv` table, so installing needs no code change.

## 4. Data

| File | Contents |
|---|---|
| `data/intel_facts.csv` | `key, label, round_to, tiers` |
| `data/spy_difficulty.csv` | `key, permille, notes` |
| `data/missive_art.csv` | `key, texture, notes` |
| `courier_kinds.csv` | + the `spy` row |
| `order_costs.csv` / `action_signatures.csv` | + `SPY_SEND` |
| `balance.csv` | `missive_keep_per_column` 40, `spy_radius_km` 25, `spy_credible_threshold` 500, `spy_text_threshold` 300, `spy_width_best` 100, `spy_width_worst` 450, `spy_bias_max` 300, `intel_match_km` 10, `intel_magnitude_*`, `missive_seal_s`, `missive_fly_s`, `missive_fly_turns` |
| `political_palette.csv` | `intel_truth`, `intel_credible`, `intel_consult`, `intel_rumour` |

## 5. Tests (GUT, written first)

- **`MissiveLog`:** ids, the per-column cap, save round-trip.
- **Receipts:**
  - a delivery writes one `credible` receipt with exact regiment state;
  - a stale order's receipt says so.
- **Monthly report:** one `truth` missive a month, exact against
  `RealmEconomy`.
- **`SpySystem.observe`**, by hand, with forced rolls (a test seam passes `q`
  and the bias):
  - the column at the threshold;
  - the half-width and bias arithmetic;
  - rounding;
  - text facts below `spy_text_threshold`;
  - troops within the radius, own vs foreign;
  - a report at sea.
  - Two spies with different rolls report differently.
- **`Intel`:**
  - the three levels;
  - the newest missive wins;
  - matching by manor, then province, then distance;
  - the magnitude words;
  - the wealth tier;
  - dev mode reads `full`.
- **Leak scan:** the listed panels never read fog-sensitive data around
  `Intel`.
- **UI, through real input:**
  - the board builds from state;
  - selecting marks read;
  - Show on map raises the view signal;
  - a spy report pauses and opens the popup, and Seal ends with the badge
    incremented;
  - a right click on the ground offers the spy row, and the card button issues
    `SPY_SEND`.
- **Real-window shots** through the visual-review loop:
  - the board with letters in all used columns;
  - the popup and the envelope in flight;
  - a foreign card before and after a spy.

## 6. Out of scope for B

- Interception and the "worth consulting" column's content (C).
- Enemy AI, so foreign troops stay where the pack put them.
- The secret courier in the UI (C).
- The courier and spy art: paintings and 3D models (D).
- Dragging notes between columns, filters and search on the board.
- Letters that expire by age: they only leave by the per-column cap.
- Spies being caught.
