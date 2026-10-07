# WAR ROOM P2 — the tactical layer: marks on the sheet and hazards that come and go — design

Status: written 2026-10-07 at the owner's request ("开始做P2，写spec"), the
owner having said for the night "不要问我问题，按照你的推荐做": every choice
below is the recommended one, and §0 lists them so a ruling can overturn any
single one. Builds on `2026-10-07-war-room-scale-hover-design.md` (P1: the
10° sheet, fine print, the hover slip `WarGround`, the near-zoom patch).

## 0. The request, the survey and the recommended rulings

P1's survey of the Azgaar export named P2 as the tactical layer: the
export's **zones** (invasion, rebels, plague, eruption, avalanche, fault,
flood, tsunami, proselytism) and **markers** (brigands, pirates, bridges,
battlefields, mines, inns, lighthouses, ruins, …), inked on the war table
and read in the slip; zones "a starting state or an event's hook, never a
permanent mark".

What the code has today:

- `society/zones.csv` (13 rows on beria) is read in one place: the
  province card lists every zone touching a province as a permanent
  "Hazard" line (`MapObjects.province_card`). No state, no effect, no end.
  The importer keeps a zone's cell COUNT, not its cells, so its extent
  cannot be drawn.
- `geography/markers.csv` (57 rows, filtered by `data/marker_types.csv`,
  the owner's 2026-09-12 ruling: medieval and hard — no monsters, no
  magic) is drawn on the 3D map as points of interest; nothing in the
  engine reads it.
- The supply line loses `army_supply_loss_permille_per_100km` by length
  only (`SupplySystem.loss_of`); a regiment's monthly attrition is wounds
  and recovery only (`ArmySystem.settle_month`).

**Recommended rulings** (each can be overturned on its own):

1. **Two sub-projects, A then B, one spec.** **A — marks**: the markers
   on the sheet and in the slip, and the two that bite (brigands, pirates)
   as a supply-line hazard. **B — hazards**: zones become STATE with a
   start, an end and effects. A is small and self-contained; B touches the
   month's settlement and the save, so it lands second.
2. **Markers are public geography** (they are on every map in the realm):
   inked on every sheet, foreign or not, no intel gate.
3. **Only brigands and pirates have an effect in P2**: a supply line
   passing within their reach loses more on the way. Every other mark is
   information (a mine, an inn, a battlefield, a ruin, a lighthouse) or
   fine print (springs, monuments, groves, fairs). Mines and inns feed P3.
4. **Zones are hazards in `GameState.hazards`**, seeded at a new campaign
   from the pack's zones, each with an end month by its kind
   (`data/hazard_kinds.csv`); an old save gets them seeded once. Events
   may add or end hazards later (the state carries a `source`); P2 adds
   no event.
5. **Effects by kind, first draft numbers in data** (owner to tune):
   disease wounds a regiment standing in it each month; rebels and
   invasion add loss to a supply line through them and sap the morale of
   a regiment standing in them; flood, avalanche and eruption slow a march
   through them; fault, tsunami and proselytism have NO military effect
   (a fault and a past tsunami are geology and history; proselytism is the
   religion system's, post-MVP). A kind with no effect draws no hatch: its
   name is fine print at its centre, and the slip names it.
6. **What is known abroad**: in the crown's own realm every hazard is
   known. Abroad, the natural ones (disease, flood, avalanche, eruption)
   are news and are shown; the human ones (rebels, invasion, proselytism)
   are a force or a faith and stay hidden until intel P2's reports
   (`WarRoom.believed_hosts`) — never inferred here.
7. **The province card reads the state**: its "Hazard" line shows only a
   hazard that is active and known, with the months left.
8. **The 3D map is not touched** in P2: its markers stay as they are; a
   hazard's look on the 3D map is a later art question.

## 1. Sub-project A — marks

### 1.1 Data

- **`data/war_marks.csv`** (new): `type, glyph, layer, note`.
  - `type`: a `marker_types.csv` type; a type absent here is not inked.
  - `glyph`: the painter's mark — `crossed_swords` (brigands),
    `sabre_wave` (pirates), `pick` (mines), `tankard` (inns),
    `crossed_flags` (battlefields), `broken_column` (ruins), `tower_light`
    (lighthouses), `dot` (anything else inked).
  - `layer`: `sheet` (inked with the ink, seen at every distance — brigands,
    pirates, mines, battlefields, lighthouses) or `fine` (the fine print,
    seen leaning in — inns, ruins, springs, monuments, groves, fairs, caves,
    necropolises, waterfalls).
  - `note`: the slip's words for the type ("a gang of forest bandits").
- **`data/war_mark_hazards.csv`** (new, the only rule in A): `type,
  reach_km, supply_loss_permille, notes` — brigands 8 km / +40‰, pirates
  12 km / +60‰ (first draft). Columns, not code, so a re-tune is data.

### 1.2 The rule (engine)

- **`SupplySystem`**: a line's loss is its length's (`loss_of`) plus, for
  each brigand or pirate mark whose reach the line's route passes through,
  that mark's `supply_loss_permille` — each mark counted once per line,
  the total capped by `army_supply_loss_cap_permille` as today. A pure
  `SupplySystem.mark_loss(repo, route_px) -> {permille, marks}` reads the
  route already computed (`route_px`), so the line's existing callers and
  its `loss_permille` field carry the new loss with no change of shape.
  Pirates bite only where the route runs by water (a route point within
  reach that is a coastal or sea cell).
- **Determinism**: a fixed function of the route and the marks (sorted by
  code); no draw, no wall clock.
- **Supply lines**: the loss (marks and hazards alike) now applies to the
  town→regiment supply line, read daily on its road (spec
  2026-10-07-army-supply-lines), not the monthly capital route.
- **Readable causality**: the line's dictionary gains `hazards: Array` of
  `{code, label, permille}`, which the folio's supply section and the
  intel ink's supply road read ("8% lost — 4% to the Brackwood brigands").

### 1.3 Presentation

- **Ink**: `WarSheetInk.strokes` gains `marks` (sheet layer) and
  `WarFinePrint.strokes` gains `marks` (fine layer), each `{at, glyph,
  label}` in texture px; the painter draws each glyph in the sheet's ink
  at `war_mark_px` (fine: `war_fine_mark_px`) and the mark's NAME beside a
  sheet-layer mark only in the fine print. A brigand or pirate mark is
  drawn in `rubric` with its reach as a faint dotted ring
  (`war_mark_reach_alpha`), so the danger reads at the opening view.
- **The key slip** gains the sheet-layer glyphs (brigands, pirates, mine,
  battlefield, lighthouse).
- **The hover slip**: `WarGround.reading` gains `marks`: every mark within
  `war_mark_hover_km` of the point, nearest first (at most
  `war_mark_hover_max`), each `{label, note, legend, distance_km}`;
  `lines` writes "Brackwood brigands, 3 km — a gang of forest bandits;
  supply lines within 8 km lose 4%" (the hazard clause only for brigands
  and pirates). The marker's own `legend` (from the export's notes) is
  the slip's last line for the nearest mark, cut to `war_mark_legend_chars`.

## 2. Sub-project B — hazards

### 2.1 Import

- `tools/import_azgaar.gd` writes `society/zones.csv`'s `cells` as the
  zone's cell ids (`|`-joined, de-duplicated — the export repeats some),
  not their count. The column keeps its name; `DataRepository` reads it
  as `PackedInt32Array`. The province card's current use (provinces only)
  is unaffected.

### 2.2 State

- **`data/hazard_kinds.csv`** (new): `kind` (the export's zone `type`:
  Invasion, Rebels, Disease, Flood, Avalanche, Eruption, Fault, Tsunami,
  Proselytism), `label`, `months` (how long a seeded one lasts; 0 = it
  never ends of itself), `public` (1: known abroad), `wounds_permille`
  (a month, on a regiment standing in it), `morale` (a month, likewise),
  `supply_loss_permille` (once, on a supply line through it),
  `pace_permille` (on a march through it), `ink` (the hatch kind:
  `plague`, `unrest`, `water`, `rock`, `none`), `notes`. First draft:
  Disease 12 mo, 15‰ wounds; Rebels 24 mo, −3 morale, +50‰ supply loss;
  Invasion 6 mo, −2 morale, +80‰; Flood 3 mo, pace 600‰; Avalanche 4 mo,
  pace 500‰; Eruption 6 mo, pace 700‰; Fault / Tsunami / Proselytism no
  effect, ink `none`.
- **`GameState.hazards`**: `{id: {kind, label, cells: Array[int], start,
  end, source}}`, whole numbers only (ticks), saved whole with the state.
  `GameState.new_campaign` seeds one per pack zone (`source` "pack",
  `start` 0, `end` `months` or -1); an old save without the key is seeded
  once on load (as `Intel.ensure_wealth_tiers` does). A pure
  `Hazards` (`scripts/engine/hazards.gd`): `active(state, tick)`,
  `at_cell(repo, state, cell) -> Array`, `known(repo, state, id) -> bool`
  (ruling 6), `months_left`, `settle_month(repo, state)` (ends the expired
  with a news line), `add(state, …)` / `end(state, id, reason)` for the
  event system later.

### 2.3 Effects (the month and the march)

- **Wounds and morale**: `ArmySystem.settle_month` applies, to each crown
  regiment standing in an active hazard's cells, the kind's
  `wounds_permille` of its fit heads (whole heads, rounded down, never
  below 0 fit) and its `morale`, and reports it as a news line with its
  reason, as an arrival is ("The 1st (Axbrigh) Regiment loses 18 to the
  Unknown Plague").
- **Supply**: `SupplySystem` adds a hazard's `supply_loss_permille` for
  each active hazard whose cells the line's route crosses (once each, the
  same cap) and lists it in the line's `hazards` (1.2).
- **Pace**: `ArmySystem.ground_permille` multiplies in the
  `pace_permille` of every active hazard holding the point (the march,
  `day_march_at`, the slip and the arrow's days all read it, so they
  agree).
- Only the crown's regiments carry state today; foreign regiments are
  untouched as they are by every other monthly rule.

### 2.4 Presentation

- **The intelligence ink** (`WarIntelInk`, "what we know") draws each
  KNOWN active hazard whose kind has an `ink` other than `none` as a
  hatched area over its cells in `intel_ink`, the hatch
  by the kind's `ink` (`plague`: fine dots, `unrest`: crossed hatching,
  `water`: wavy lines, `rock`: broken hatching), its outline dashed, its
  name and months left at its centre in the fine print; the intel key
  turns on the hazards' ids and ends, so a hazard ending redraws it.
- **The key slip** gains the four hatches.
- **The hover slip**: `WarGround.reading` gains `hazards` (known active
  hazards holding the point); `lines` writes "The Unknown Plague — 7 months
  left: regiments here lose about 1.5% a month", and with a regiment
  chosen its pace and power lines already include the effects (2.3).
- **The province card**: its "Hazard" line is the state's known active
  hazards with months left (ruling 7).

## 3. Tests

- A: the marks' strokes (sheet vs fine layer, foreign sheets too), the
  glyph table covers every inked type, `mark_loss` by hand (a route
  passing one brigand mark gains exactly its permille, a route passing
  none gains 0, two passes of one mark count once, pirates only by water,
  the cap holds), the slip's mark lines and their order.
- B: the importer writes cell ids (de-duplicated) and `DataRepository`
  reads them; seeding at a new campaign and once on an old save; the end
  month; `settle_month` ends the expired with news; wounds and morale by
  hand on a fixture regiment in a fixture hazard (with the reason
  string); supply and pace by hand; `known` abroad by kind; the intel
  key turns when a hazard ends; the save round-trips hazards whole
  (`SuiteData.campaign` goes through the save format already).
- Determinism: two campaigns from one seed settle the same hazards and
  wounds over 24 months.
- Real-window shots (`visual-review`): a sheet with brigands and a
  plague at 1.6 / 0.5 / 0.12 m, the slip over each, the folio's supply
  section naming a hazard; an independent critic.

## 4. Order of work

A (data → rule → ink → slip → key) lands on its own; then B (import →
state → effects → ink → slip → card). Each is a plan of its own.

## 5. Not in P2

- An event that starts or ends a hazard (the state is ready for it), a
  council concern raised by a hazard in the realm (`ConcernScanner`), the
  3D map's look of a hazard, foreign forces and rebels abroad (intel P2),
  mines / inns / markets as economy (P3), proselytism's effect on faith
  (the religion system, post-MVP).

## 6. Engine rules (moved from `scripts/engine/CLAUDE.md`)

`Hazards` are STATE: `GameState.hazards` (id → kind, label, cells, start, end, source), seeded once from the pack's zones (`seed_pack`, `hazards_seeded`), saved whole; `hazards_rev` (not saved) bumps on every change for the caches. What a kind does is `data/hazard_kinds.csv` (months, public, wounds, morale, supply loss, pace, ink). In the crown's realm every hazard is known; abroad only a `public` kind (`known`). The month's end runs `settle_regiments` after `ArmySystem.settle_month` and `settle_month` (endings, news only for a known one) after the day turns; a march's pace multiplies by `pace_permille`, a supply line's road loses its share, sampled every `war_hazard_sample_km` (`SupplySystem.hazard_loss`; an unknown one is "trouble on the road").
