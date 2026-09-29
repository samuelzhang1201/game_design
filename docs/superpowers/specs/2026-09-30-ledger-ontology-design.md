# The LEDGER — the realm's ontology — design

Owner request 2026-09-30: bring the idea of an ONTOLOGY into the game and let
it replace the RELATIONSHIP tab — grain converted into strategic stores,
stores supplying a regiment, the regiment garrisoning a stronghold and
attacking the enemy, peasants working the land, workers raising a market that
trades goods — organised so that it is interesting and playable.

This spec is the ontology's CHARTER (every object, link and action type; the
rules that make it play; the data and the architecture) and the full design
of its FIRST sub-project, **L0**, the LEDGER screen itself. Every mechanic the
charter names but the engine lacks (M1–M6, §8) gets its own spec and plan
when it starts.

## Owner rulings (2026-09-30)

1. **The graph is a desk AND a lever** (option B): it explains why the realm
   is as it is, and a click on a node or a link issues a real order.
2. **With a touch of C**: ministers GOVERN links (their skill, opinion and
   traits decide how well a flow runs), and the intelligence layer hides what
   the crown has not been told.
3. **The court's web moves in** (option A): characters are one object type,
   every `rel_type` (marriage, kin, rival, grudge…) is a link type, and "Court" is one lens of the one
   graph. `RelationshipGraphScreen` goes.
4. **Charter + a first buildable sub-project** (option A): L0 draws what the
   engine already has and shows every missing link as a grey "not yet built"
   line; each mechanic that lands lights its links.
5. **Type level first, drill down to an instance's ego network** (option C).
6. **A governing minister** (option B): skill sets the ceiling, opinion the
   cooperation, traits the quirks (a venal steward skims, hidden); the player
   may reassign who governs, at a cost. A FACTION may govern a whole subgraph
   later — the column is reserved now.
7. **Data-driven schema + resolvers** (approach 1): the ontology is CSV rows;
   an engine `Ledger` reads each link's live value from the real systems
   through a named resolver and simulates nothing itself.
8. **Intelligence is the core**: the graph is the player's BELIEF, not the
   truth. Every figure carries its provenance; **the one who governs a flow
   is usually the one who reports it.**
9. **The tab is LEDGER.**
10. **The view is 3D**: spheres for entities, links between them with a
    connection effect, the whole turned, dragged and zoomed.
11. **The whole MVP carries the whole game** ("整个mvp必须要有全部游戏体验"):
    M1–M6, including the raw-materials chain and the markets, are IN the
    MVP (§8, §10).
12. **L0 goes now, ahead of PRD Step 3** (confirmed at the spec review): it
    adds no mechanic and replaces the Step 4 web already built.
13. **The look is the realm's orrery** (confirmed): brass and glass spheres,
    gold-wire threads; variants for the owner through the visual-review loop.

## 1. The idea

The realm runs on FLOWS of things. People govern the flows. The same people
report on them. The player sees the realm only through those reports.

The LEDGER is that sentence drawn: an orrery of the realm in which each
sphere is a thing, a person or a piece of knowledge, and each thread a flow,
a tie or a report. It never shows the truth (DEV MODE and the debrief
excepted). It shows what the crown has been told, by whom, and when.

In this spec's terms (the usual ontology vocabulary):

- an **object type** is a kind of thing (Regiment); an **object** is one of
  them (the 3rd Regiment);
- a **property** is a value an object carries (supplies, morale) — drawn as
  a gauge INSIDE its sphere, never as a sphere of its own;
- a **link type** is a kind of relation between two object types
  (strategic stores —supply→ regiment); a **link** is one of them;
- an **action type** is an order the player may give on an object or a link;
  it is always a real `action_code` (invariant 1).

Two refinements of the owner's sketch follow from that vocabulary:

- **Morale is a property of the regiment, not a node.** "Strategic stores
  —affect→ morale —acts on→ regiment" becomes: stores —supply→ regiment
  (raising its `supplies`), and `supplies` drives `morale` through a function.
- **A flow that someone governs is an OBJECT** (reified): a *supply line*, a
  *war workshop* (civil goods into strategic), a *trade route*. Then "the
  steward governs the workshop" is an ordinary link between two objects.

## 2. The charter: object types

Three groups, drawn as three layers of the 3D view (§6): KNOW on top, PEOPLE
in the middle, THINGS at the bottom.

| Group | Object type | `type_id` | Key properties | Status |
|---|---|---|---|---|
| Things | Manor | `manor` | people, chief good, output, tax, holder | ✅ |
| | Province | `province` | people, wealth tier, controller | ✅ |
| | Town | `town` | people, tariff; where a garrison stands (M1: the `stronghold` type was dropped — a garrison stands in a town) | ✅ |
| | Market | `market` | goods traded, prices | ○ M6 |
| | Civil goods | `civil_goods` | stock, monthly flow (crown / lord purse) | ✅ |
| | Strategic goods | `strategic_goods` | stock, monthly flow | ✅ |
| | Gold | `gold` | treasury, lord's gold | ✅ |
| | Raw material | `raw_material` | stock of a named good | ○ M5 |
| | Building | `building` | produce, bonuses, slot | ✅ |
| | War workshop | `workshop` | ratio, efficiency, governor | ✅ M2 (`workshop:<cell>`, `WorkshopSystem.plan`) |
| | Supply line | `supply_line` | length, loss, delay, governor | ✅ M1 (`supply_line:<regiment>`, `SupplySystem.plan`) |
| | Trade route | `trade_route` | volume, toll, governor | ○ M6 |
| | Peasants | `peasants` | people per province | ✅ (a province's rural people) |
| | Artisans | `artisans` | people per town | ○ M5 |
| | Regiment | `regiment` | heads, supplies, morale, training, readiness | ✅ |
| | Enemy host | `enemy_host` | believed heads, heading | ○ M4 (the raid host) |
| People | Character | `character` | skills, opinion, traits, record | ✅ |
| | House | `house` | manors, provinces, arms | ✅ |
| | Seat | `seat` | holder, domain, salary | ✅ |
| | Faction | `faction` | power, cohesion, stage | ○ PRD Step 5 |
| Know | Source | `source` | a character, or a class (merchants, parish, hired scout) | ⚠️ implicit today |
| | Report | `report` | subject, fields, observed day, arrived day, credibility | ✅ (missives) |
| | Courier | `courier` | route, carrying | ✅ |

✅ the engine holds it now; ○ a milestone of §8 builds it; ⚠️ partly.

## 3. The charter: link types

Verbs are English in data and on screen; the UI's labels go through the same
text rules as every other screen.

**Flows of things**

| `link_id` | From → To | Verb | Status | Governed by |
|---|---|---|---|---|
| `works` | peasants → manor | works | ✅ | — |
| `yields` | manor → civil / strategic goods | yields | ✅ | — |
| `taxed` | manor → gold | pays tax | ✅ | chancellor |
| `trade_gold` | gold ⇄ civil / strategic goods | buys / sells | ✅ | steward |
| `rations` | civil goods → peasants | feeds | ✅ | steward |
| `stands_on` | building → manor | stands on | ✅ | — |
| `produces` | building → goods | produces | ✅ | — |
| `converts` | civil goods → workshop → strategic goods (`converts_in` / `converts_out`) | converts | ✅ M2 | steward |
| `supplies` | strategic goods → supply line → regiment (`supplies_in` / `supplies_out`) | supplies | ✅ M1 | marshal |
| `garrisons` | regiment → town | garrisons in | ✅ M1 (a garrison stands in a town: `SupplySystem.stronghold_of`) | marshal |
| `feeds_morale` | regiment.supplies → regiment.morale | a property function | ○ M1 | — |
| `attacks` | regiment → enemy host | attacks | ○ M4 | the commander |
| `builds` | artisans → building | build | ○ M5 | master of works |
| `consumes` | building → raw material | consumes | ○ M5 | master of works |
| `trades` | market ⇄ goods, along a trade route | trades | ○ M6 | steward / admiral (sea) |

**People**

| `link_id` | From → To | Status |
|---|---|---|
| `kin` / `marriage` / `ally` / `rival` / `grudge` / `liege` / `patron` / `puppet` / `admires` | character ⇄ character (sentiment) — one link type per `rel_type` of `data/relationships.csv` | ✅ `RelationshipGraph` |
| `holds` | house → manor | ✅ |
| `sits` | character → seat | ✅ |
| `member` | character → house | ✅ (family name) |
| `governs` | character (or faction) → workshop / supply line / trade route / building works | ○ M3 |
| `commands` | character → regiment | ○ M4 (intel P1's commanders) |

**Knowledge**

| `link_id` | From → To | Status |
|---|---|---|
| `spies_on` | spy → place | ✅ `SpySystem` |
| `carries` | courier → regiment (an order) | ✅ `CourierSystem` |
| `describes` | report → an object's property | ✅ (one report per subject, `Intel._latest`) |
| `witnessed` | source → object | ○ intel P1 |
| `rides_home` | report → court (the return leg) | ○ intel P0 |
| `contradicts` | report ⇄ report | ○ L1 (intel P0) |
| `skims` | governor → the flow he governs (hidden) | ○ M3 |

## 4. The rules that make it play

Written into the charter; every milestone is checked against them.

1. **Every link is a lever and a weak point.** The crown can thicken it;
   an enemy, a bad governor or the weather can thin or cut it.
2. **One source, many outlets, so the player must choose.** Civil goods feed
   the people, feed the workshop or are sold; the graph shows the split.
3. **Loops are drawn.** A running loop glows round its whole ring: virtuous
   (morale → victory → spoils → stores) or vicious (famine → unrest →
   falling output → hunger). `data/ledger_loops.csv` names each loop and the
   `TriggerDsl` condition under which it runs.
4. **The governor is usually the reporter (the core).** The steward governs
   the workshop and writes its account. A venal steward who skims three
   tenths reports it full; with one source the thread is thick and dark. The
   player sees through him only with a SECOND source — a spy sent to audit,
   the merchants asked, or the commander's own count of what reached him.
   Two accounts that disagree split the thread into two strands, each
   wearing its source, and the player decides which to believe. When the
   truth comes out, the debrief writes it on his card forever
   (`2026-09-28-intelligence-layer-alignment.md` §5.7), and the player may
   dismiss, punish or keep him and say nothing.
5. **The structure is always lit; the figures are blurred.** Every object
   and link TYPE is always visible (the crown knows an army eats), matching
   the ruling that the map is never shrouded. Values and instance links pass
   through `Intel`'s three levels: `full` (provinces the crown controls,
   its regiments) exact, `general` (the rest of the realm) words, `basic`
   (abroad) holder, stance and wealth only. An enemy's unknown link is a
   dashed thread with a question mark until a spy or the merchants firm it.
6. **Distance is a cost.** Stores and reports both travel the roads: the
   longer the line, the more it loses and the later it speaks.
7. **The truth comes out.** The debrief sets every report beside what
   happened; a liar's record is permanent.

## 5. Action types

| On | Orders | Status |
|---|---|---|
| a thing | build, change the chief good, buy / sell goods | ✅ `MANOR_BUILD`, `MANOR_FOCUS`, `GOODS_BUY` / `GOODS_SELL` |
| a reified flow | set the ratio, reassign the governor | ○ M2 / M3 |
| a person | the existing character orders | ✅ |
| a report or a link | send a spy | ✅ `SPY_SEND` |
| | audit a governed flow | ○ M3 `LEDGER_AUDIT` |
| | ask the guild / the parish | ○ intel P3 (`INTEL_ASK_GUILD` / `_CHURCH`) |
| | attach an observer | ○ intel P3 |

Every action is a row of `data/ledger_actions.csv` naming an existing
`action_code`, which has its `order_costs.csv` row (invariant 8) and runs
through `Game.try_execute`. An order that needs a point on the map
(`ARMY_MARCH`, `SPY_SEND` to a place) is offered as **Show on map**, which
closes the LEDGER and arms the map's own aim — the ledger never invents a
second way to pick a point.

## 6. L0 — the LEDGER screen

### 6.1 Where it lives

- The bottom bar's `RELATIONSHIP` tab becomes **`LEDGER`**, a SCREEN in the
  right-hand group beside MISSIVE (`BottomBar.TABS`); `GameRoot.toggle_relations`
  becomes `toggle_ledger`.
- It covers the map panel like the Missive board. The map stops rendering
  while it is open (the 3D view renders only while shown).
- **The columns keep their kinds (invariant 10).** The LEFT column is the
  fact card of the selected sphere or thread — every figure with its source
  and date ("the steward: full · the spy: seven tenths · 3 days ago"), and
  **Show on map**. Clicking a TYPE sphere puts the list of its instances in
  the left column instead, the most strained first (after the Manor Master
  table). The RIGHT column stays the council; selecting a minister's sphere
  lights him there, so he can be summoned to talk.

### 6.2 The view

- **Three floating discs**, translucent: KNOW on top, PEOPLE in the middle,
  THINGS at the bottom. Seen from the front they read as three bands; turned,
  they show depth within a layer. The layers are what keeps a 3D graph
  legible (occlusion and lost depth are the known failures of 3D graphs);
  three more guards:
  - **Front view** in one click — the compass rose of the map, which eases
    back to north on a click, does the same here;
  - **Focus**: selecting a sphere fades everything not linked to it;
  - **Labels on a 2D HUD**, always facing the screen, cut once per camera
    pose so they never overlap (the `Map3DHud` practice).
- **Input**, the map's: right-drag turns, left-drag on a sphere moves it (the
  layout eases round it), left-drag on empty space pans, the wheel and a
  trackpad pinch zoom about the pointer, double-click drills in. Left click
  selects (left column); right click opens the sphere's or thread's orders
  (an `ArmyOrderMenu`-style menu with each order's cost).
- **A breadcrumb** over the view: Realm › Regiments › 3rd Regiment.
- **Lens chips**: Economy / War / Court / Intelligence / All. A type row
  lists the lenses it appears in. Court is instance-level from the start (21
  people), which is today's web of the court.
- **Type level** stands at hand-set positions (`x`, `z` in
  `ledger_object_types.csv`; the layer gives `y`), so it is the same every
  time it opens. **An instance's ego network** is laid out per layer by a
  deterministic layered force layout: upstream on the left, downstream on the
  right, its governors above it in PEOPLE, the reports about it in KNOW.
  A drag moves a sphere for this viewing only; it is never saved.

### 6.3 The look: the realm's orrery

- Spheres of brass and glass, threads of gold wire, over the dark leather
  UI — a medieval armillary, not a neon network. The art is settled through
  the visual-review loop, variants for the owner to pick.
- **What the drawing means (no numeric credibility anywhere — the
  intelligence ruling):**

| Meaning | Drawn as |
|---|---|
| believed monthly flow | the thread's thickness, and the speed and brightness of the light running along it in the flow's direction |
| credibility | how dense the thread's ink is |
| a report's age | the thread yellowing |
| accounts differ | the thread splits into two strands, each with its own light and a small seal of its source (portrait chip or arms) |
| not yet built (○) | a grey dashed thread with no light, "not yet built"; its tooltip names the milestone that lights it |
| unknown abroad | a dashed thread with a question mark |
| a running loop | the whole ring glows slowly: gold if virtuous, dark red if vicious |
| a property | a small gauge inside the sphere (supplies, morale) |

- Every look number is `balance.csv` `ledger_*`; every colour is
  `data/ledger_palette.csv`.

## 7. Data and architecture

### 7.1 Data (`data/`)

| File | Columns |
|---|---|
| `ledger_object_types.csv` | `type_id`, `group` (know / people / things), `layer`, `lenses` (joined by \|), `label`, `icon` (a `resource_icons.csv` key), `x`, `z`, `instances` (resolver name, empty for a singleton), `status`, `milestone` |
| `ledger_link_types.csv` | `link_id`, `from_type`, `to_type`, `verb`, `lenses`, `status` (live / planned), `resolver`, `governor_seat`, `governor_kind` (seat; faction reserved), `intel_subject` (what `Intel` gates it by), `milestone` (M1..M6, L1, intel P0..P3), `planned_note`, `loops` |
| `ledger_actions.csv` | `target` (a type or link id), `action_code`, `label`, `needs_map` (1: offered as Show on map) |
| `ledger_loops.csv` | `loop_id`, `links` (joined by \|), `kind` (virtuous / vicious), `running` (a `TriggerDsl` condition), `label` |
| `ledger_palette.csv` | the view's colours |
| `balance.csv` `ledger_*` | sphere radius, thread width scale, light speed per unit of flow, layer heights, layout forces and iterations, label spacing, fade on focus |

A new milestone turns its rows' `status` to `live` and registers their
resolvers; nothing else in the ledger changes.

### 7.2 Engine (`scripts/engine/`, pure `RefCounted`)

- **`Ledger`** (`ledger.gd`)
  - loads and validates the schema: every `live` link has a registered
    resolver, every `planned` link names its milestone, every action's code
    exists with its cost row, every type and link names known lenses and
    layers;
  - `snapshot(repo, state, lens, focus) -> Dictionary` returns
    `{nodes, links, loops}` in a fixed order: a node is `{id, type, label,
    layer, props: [{key, text, accounts}]}`, a link `{id, type, from, to,
    flow, accounts: [{source, value, day, level}], governor, status}`;
  - **reads, never writes**: it changes no state and draws no RNG.
- **`LedgerResolvers`** (`ledger_resolvers.gd`): a table from resolver name
  to a function `(repo, state, focus) -> Array` of links, reading only the
  real systems — `RealmEconomy` (the cached lines, one province key check
  per bulk read), `MapManors`, `ArmySystem`, `RelationshipGraph`,
  `CourierSystem`, `SpySystem`, `MissiveLog`.
- **Belief goes through `Intel`, the one gate.** A resolver returns the
  truth; `Ledger` turns it into accounts through `Intel.level` / `Intel.fact`
  for the link's `intel_subject`. Today an account list holds ONE entry (the
  crown's own figure where it is `full`, else the newest report or the
  level's words); intel P0 fills it with every live claim and L1 draws them
  as strands. `Intel.dev_all` (DEV MODE) shows the truth.

### 7.3 Presentation

The same split as the map: nothing under `scripts/ledger3d/` may reach the
`Game` autoload.

- **`LedgerScreen`** (`scripts/ui/ledger_screen.gd`): the only piece that
  touches `Game`. It asks `Ledger` for snapshots on `state_changed` while
  open, fills the left column's card or list, lights the minister in the
  right column, opens the orders menu and runs an order through
  `Game.try_execute`.
- **`LedgerView3D`** (`scripts/ledger3d/`) + the AUTHORED scene
  `scenes/ledger/ledger_view.tscn` (SubViewport at window resolution shown
  by a TextureRect — never a SubViewportContainer —, camera rig,
  environment, the three discs, materials in `.tres` holding shader and
  textures only), wired with `%` unique names in the editor. It takes a
  snapshot and emits `sphere_selected`, `thread_selected`,
  `orders_requested`, `drill_requested`.
- **`LedgerLayout`** (pure): hand-set type positions; the per-layer force
  layout of an ego network with fixed iterations and a fixed seed, so the
  same snapshot always lays out the same way.
- **Picking** is ray-vs-sphere and ray-vs-tube maths, no physics (the map's
  practice since Terrain3D's collision was turned off).
- **Threads** are tube or ribbon meshes rebuilt when the snapshot changes,
  with one shader for the running light, the split strands, the dash and the
  ink; spheres are one `MultiMesh` per material.
- Size: up to ~300 spheres in an ego network; the type level has ~25.

### 7.4 Moving the web of the court in

- `RelationshipGraphScreen` is deleted. The Court lens is the `character`
  instances and one link type per `rel_type` of `data/relationships.csv`, through a
  `court_relations` resolver that reads `RelationshipGraph` (edge colour by
  sentiment, kin and marriage in gold, as today).
- `RelationshipGraph` (the engine) is untouched: seeding, monthly drift and
  events' `rel:` effects stay as they are.
- Tests that open the RELATIONSHIP overlay move to the LEDGER's Court lens.

## 8. Milestones — what lights which links

| | Sub-project | Lights | Needs | Placement | Spec / plan |
|---|---|---|---|---|---|
| **L0** | **The LEDGER and its 3D view** (this spec) | every ✅ link; ○ links drawn grey; the court's web moved in | nothing new — reads existing state | **now, ahead of PRD Step 3** (ruling 12) | this spec → `docs/superpowers/plans/2026-09-30-ledger-l0.md` |
| **L1** | Accounts differ | split strands, "accounts differ" on the card | intel P0 | with intel P0 | `2026-09-28-intelligence-layer-alignment.md` §8 P0 (L1 rides with it); the split-strand mechanics are also written up in `2026-09-30-ledger-governors-design.md` |
| **M1** | Supply and morale | `supplies`, `garrisons` (stores and defence from the stronghold), `feeds_morale` | L0 | PRD Step 8, with raid defense and intel P1–P3 | `2026-09-30-ledger-supply-design.md` → `docs/superpowers/plans/2026-09-30-ledger-m1-m2-supply.md` |
| **M2** | The war workshop | `converts` | L0 | with M1 (supply needs a source) | `2026-09-30-ledger-supply-design.md` → `docs/superpowers/plans/2026-09-30-ledger-m1-m2-supply.md` |
| **M3** | **Governors, skimming and the audit** (the core) | `governs`, `skims`, `LEDGER_AUDIT`, reassigning a governor | L1, M2 | after Step 8, before or with Step 5's factions; a faction may govern once factions exist | `2026-09-30-ledger-governors-design.md` → `docs/superpowers/plans/2026-09-30-ledger-m3-governors.md` |
| **M4** | Battle | `attacks`, `commands` (`battle_odds` made real; the raid host the first enemy) | M1 | PRD Step 8 | `2026-09-30-ledger-battle-design.md` — no plan yet: not implementable before intel P2's raid host exists |
| **M5** | Raw materials and artisans | `builds`, `consumes` (the smithy really eats iron and coal) | L0 | in the MVP (ruling 11) | `2026-09-30-ledger-industry-trade-design.md` → `docs/superpowers/plans/2026-09-30-ledger-m5-m6-industry-trade.md` |
| **M6** | Markets and trade routes | `trades` (reads the imported `markets` / `market_goods` / `deals`) | M5 | in the MVP (ruling 11) | `2026-09-30-ledger-industry-trade-design.md` → `docs/superpowers/plans/2026-09-30-ledger-m5-m6-industry-trade.md` |

Each milestone gets its own spec → plan → build. Every spec's own filename in this table is under `docs/superpowers/specs/`.

## 9. Tests (GUT, written before the code)

- **Schema**: the validation of §7.2 fails on a live link with no resolver,
  a planned link with no milestone, an action with no cost row, an unknown
  lens or layer.
- **Resolvers**: each live resolver returns what its system holds, against
  hand-computed values on a fixture (a manor's yield equals
  `ManorEconomy.line_of`'s units; the court web equals `GameState.relationships`).
- **The Intel gate**: a controlled province's flow is exact; a province of
  the realm the crown does not control gives words; abroad gives no figure;
  DEV MODE gives the truth.
- **Determinism**: the same state gives the same snapshot (order included)
  and the same layout.
- **Picking maths**: ray-vs-sphere and ray-vs-tube against hand-computed
  hits.
- **The scan**: no `Game.` under `scripts/ledger3d/`.
- **Migration**: the bottom bar has LEDGER and no RELATIONSHIP; the Court
  lens holds today's 49 edges.
- **Look** (headless cannot render 3D): `tools/snapshot_screen.gd --screen
  ledger [--lens L] [--focus ID]` through the real window, and the
  visual-review loop with an independent critic.

## 10. Documents that must change, and what the owner confirms

- **PRD §2 / §6 / §7**: the LEDGER replaces the relationship graph of Step 4;
  M1–M6 join the MVP (ruling 11) at the placements of §8; the build order
  records L0's placement (ruling 12).
- **`CLAUDE.md`**: the LEDGER in the bottom bar and the layout; the rulings
  above (the graph is belief; the governor is the reporter; the tab is
  LEDGER).
- **`2026-09-28-intelligence-layer-alignment.md`**: its §8 phases gain the
  ledger's L1 beside P0, and M3's audit beside P3's countermeasures.
- **Confirmed at the review**: L0 ahead of PRD Step 3 (ruling 12); the
  orrery as the art direction (ruling 13).

## 11. Out of scope for L0

Every ○ mechanic (M1–M6), several accounts per subject (L1), a governor's
effect on a flow, the audit, faction governors, and any save state for the
ledger (it is derived; a dragged sphere is forgotten).

## 12. What L0 settled (2026-09-30 plan)

- **`group` and `layer` are one column, `layer`.** §2's "Group" column and
  §7.1's `ledger_object_types.csv` `group` column collapse to the single
  `layer` column (values `know` / `people` / `things`) `Ledger.LAYERS`
  reads; nothing in the schema or the resolvers carries both.
- **The Intel subject is carried per link by its reader (`subj`), not an
  `intel_subject` column.** §3 and §7.1 name `intel_subject` as a
  `ledger_link_types.csv` column; the built schema has no such column.
  `LedgerResolvers.run` returns `subj` on each link dictionary it produces,
  and `Ledger._account` reads that `subj` straight through `Intel.level` /
  `Intel.fact` — the gate is data the resolver already had at hand (which
  province, manor, regiment or character a flow is really about), not a
  second table to keep in step with the first.
- **A tie never becomes an Intel word.** A structural yes/no link (`part_of`,
  `stands_on`, `based_in`, `describes_*`, `sits`, `member`, …) carries
  `flow: -1` and no magnitude. `Ledger._account` short-circuits on
  `flow < 0` before ever calling `Intel.fact`, returning
  `{"value": -1, "text": "", "source": "own records"/"common knowledge", ...}`
  — never `Intel.magnitude`'s vague-quantity words ("a handful"), which
  would otherwise turn "a manor lies in a province" into a bogus figure.
  The thread still draws at its fixed vague width; only a real flow (
  `flow >= 0`) ever carries a number or a word for one.
- **The `CylinderMesh` UV correction.** A cylinder's side V does not run
  0..1 top to bottom under Godot 4.7.2: it runs 0 at the top to **0.5** at
  the bottom, with the caps taking 0.5..1. `thread.gdshader`'s running
  light is `along = 1.0 - 2.0 * UV.y` (not `1.0 - UV.y`, which the brief
  had), with the cylinder's caps turned off (`cap_top = false`,
  `cap_bottom = false`) — the shader never reads them.
- **Spheres are one `MeshInstance3D` each (up to ~300 in an ego network),
  not a `MultiMesh`.** Each sphere needs its own focus-fade alpha and its
  own drag; a `MultiMesh` shares one material and instance-transform array
  across every instance it draws, which cannot carry a per-instance fade
  without a second per-instance buffer that defeats the point of batching
  at this count. `LedgerView3D._build_spheres` allocates one
  `MeshInstance3D.new()` a node.
- **A drag moves only the dragged sphere's incident threads.** The first
  cut rebuilt every thread mesh (`_build_threads()`) on every drag motion
  event; the reviewed fix, `_move_threads_of(id)`, walks only the links
  whose `from` or `to` is the dragged sphere, recomputes their ends (the
  pair-offset included) and re-lays the existing `MeshInstance3D` in place
  (`_place_thread`) — no mesh or material is allocated per motion event.
  Every non-incident thread keeps its instance id untouched.
- **Discs are drawn only for occupied layers, each sized to its spheres.**
  `LedgerLayout.layers_present(snap)` lists which of `Ledger.LAYERS` the
  snapshot actually has a sphere on (the court lens has PEOPLE alone, so it
  shows one disc, not three empty rings); `LedgerLayout.disc_radius` sizes
  each shown disc to (its farthest sphere's edge from the axis) +
  `ledger_disc_pad_m`, clamped to `ledger_disc_min_m` .. `ledger_disc_radius_m`
  — an ego network's two-sphere disc no longer frames itself with 10 m of
  empty brass.
- **The camera frames what is drawn.** `LedgerOrbit.frame(points, yaw,
  pitch, fov, aspect, safe)` is a pure function that bisects the least
  camera distance at which every given point (each sphere ± its radius,
  plus sample points on each drawn disc's rim, from
  `LedgerLayout.frame_points`) projects inside a safe rect, then centres
  the content in it. The safe rect is the view minus `ledger_frame_top_px`
  (92: the title, lenses, crumb and a name over the top sphere),
  `ledger_frame_side_px` (40) and `ledger_frame_bottom_px` (28) — all
  `balance.csv` rows. `LedgerView3D._frame()` runs this on the opening pose
  and on Front; an unmoved camera re-frames on a resize, and any turn, pan,
  wheel or pinch by the player clears the "framed" flag so the fixed
  `ledger_camera_distance` becomes only the fallback when nothing is drawn.
- **A drill opens the instance's card, not the list.** `LedgerScreen.drill`
  rebuilds the ego network on the chosen id and calls
  `_detail.show_entry(LedgerCards.entry(...))`: a manor, town, regiment or
  courier gets the map's own card (`MapObjects` art and fields); anything
  else gets the LEDGER's own thread card. `back()` closes the card and
  returns to the list. This is a correction from the first cut, which left
  the type's list showing with only the drilled row lit.
- **A type's instance list is `MapDetailPanel.show_list`.** Clicking a TYPE
  sphere (rather than an instance) puts its instances in the left column
  through a new `MapDetailPanel.show_list(title, rows)` and
  `list_row_chosen(id)` signal — flat, left-aligned, clipped buttons
  carrying the row's id — reusing the existing card panel rather than a
  second list widget.
- **The screen follows the map panel.** `GameRoot.toggle_ledger` connects
  `map_panel().item_rect_changed` to `_fit_ledger()` (besides the
  viewport's own `size_changed`), so the LEDGER's SubViewport display
  resizes and repositions when the map panel narrows for the council
  column or otherwise moves — `size_changed` alone would miss a panel
  resize that leaves the window untouched. The connection is torn down
  with the screen.
- **Selecting a minister does not yet light him in the right column.**
  §6.1 describes this as the eventual behaviour; no API for it exists yet
  (the court screen — `CourtScreen` — has no council column to light a
  character in, unlike the conversation stage), so `LedgerScreen` does not
  attempt it in L0. A selected character's card names his seat instead
  (`LedgerCards.entry`), which is what the left column can show today.
- **The snapshot flags.** `tools/snapshot_screen.gd --ledger LENS
  [--ledger-focus TYPE] --shot-on ledger` drives the LEDGER through real
  clicks, not internals: the bottom bar's LEDGER tab, the lens chip, and
  (with a focus) the `type:<TYPE>` sphere at `LedgerView3D.screen_pos_of`
  and the first left-column row carrying `ledger_id`.
- **Link rows added beyond §3.** The built `ledger_link_types.csv` carries
  more rows than §3's table names: `part_of` (manor → province, "lies
  in"), `based_in` (regiment → province, "stands in"), one `describes_*`
  row per subject kind a report can be about (`describes_province`,
  `describes_manor`, `describes_regiment`, `describes_town` — §3's single
  `describes` row, split so each has its own `from_type`/`to_type`), and
  one character-to-character row per `rel_type` of `data/relationships.csv`
  (`kin`, `marriage`, `ally`, `rival`, `grudge`, `liege`, `envoy`,
  `patron`, `puppet`, `admires`, `acquaintance` — more than §3's shorter
  list, matching whatever `relationships.csv` actually seeds), all read by
  `court_relations`. **`produces` folds into the manor's `yields_civil` /
  `yields_strategic` links until M5** gives buildings their own consuming
  link (`consumes`) and a reason to draw `produces` separately from a
  manor's total output.
- **The look: variant A shipped, pending the owner's pick.** The look pass
  (Task 10) shot three palette/material variants (A: warm brass and glass,
  as designed; B and C: alternate metals) side by side, with a written
  critique ranking A first. A comparison was prepared for the owner (at
  the session's scratchpad, not committed to the repo); L0 ships variant
  A's values in `data/ledger_palette.csv` and `balance.csv` unchanged, and
  the owner's pick — if it differs from A — is a follow-up re-tint, not a
  blocker on L0.

- **What §6 describes that L0 did not build, and who owns it** (final
  review, 2026-09-30):
  - **Property gauges inside spheres** (§6.3's last row) → **M1**, the
    supply-and-morale plan (`docs/superpowers/plans/2026-09-30-ledger-m1-m2-supply.md`
    Task 5 carries the note): supplies and morale inside a regiment's
    sphere, stock inside a pool's. L0 draws no gauge. **BUILT in M1**
    (plan Task 5): a snapshot node carries `props: [{key, label, value,
    max}]` (`LedgerResolvers.props_of`, whole numbers — not §7.2's
    `{key, text, accounts}`: every gauge today is the crown's own figure):
    a regiment the crown knows in full (its own; any in DEV MODE) its
    supply score out of 1000 (`ArmySystem.bars_of`) and its morale out of
    100; the civil and strategic goods type spheres the crown's plus the
    lord's stock against `ledger_gauge_stock_months` (12) of the month's
    intake. `LedgerHud` draws each as a small ring gauge with its caption
    ("Supplies 64%", "Morale 70", "Stock 24,633") on the far side of the
    sphere's name from the sphere — over a name above it, under one set
    beneath it — so the row never covers the sphere or its threads
    (`ledger_gauge_*`, palette `gauge_fill` / `gauge_track`); a type not
    yet built now yields its name's place to a live neighbour's.
  - **"Unknown abroad" — a dashed thread with a "?"** (§6.3) → **intel P0 /
    L1**, when a link can be about a place abroad at all. L0's readers only
    walk the crown's own realm, so no such thread arises; a figure the crown
    has only in words draws at the fixed vague width and fainter ink.
  - **The breadcrumb** (§6.2: Realm › Regiments › 3rd Regiment) → L0 built
    **Back plus one label**: `%Back` shows while a focus is drawn and
    `%Crumb` names the focus (`LedgerResolvers.label_of`). The full trail
    waits for drilling more than one level deep.
  - **A planned thread names its milestone** (§6.3) — BUILT in the final
    fix pass: its card reads "Not yet built (M2): lit by the war workshop",
    the milestone taken from the link row's `milestone`
    (`LedgerCards.thread_entry`).
  - **Orders that need the map promise only what they do** (owner asleep;
    controller ruling): `ledger_actions.csv` labels them "Show on the map to
    build…", "…to change its work…", "…to send a spy…", "…to march…". The
    LEDGER closes and shows the subject on the map; the player gives the
    order there. **Arming the march aim** (or the build menu) straight from
    the LEDGER is left for later.
  - **An order's menu line names what it spends**: a label may carry its
    params (`Buy {gold} gold of civil goods`), and an order that spends a
    sum of its own writes the `order_costs.csv` charge as a fee beside it
    (`Ledger.order_text`: "Buy 50 gold of civil goods  (+1 fee)").
- **The LEDGER draws the live state at most once a frame.** `Game.state_changed`
  fires once a game day, several times a frame at 4x: `LedgerScreen.refresh`
  only marks it dirty and `_process` draws it once. A redraw of the same
  lens and focus keeps the spheres the player dragged where he put them
  (`LedgerView3D._dragged`, forgotten on a new lens or focus); a drag whose
  sphere is no longer drawn ends quietly; a focus that vanished frames the
  camera afresh and closes its card. The LEDGER closes only a card or list
  it put in the left column (`LedgerScreen._card_mine`), and the map stays
  put away while it is open (`GameRoot._sync_map_view`).
- **The tax thread reads a spy's `tax` estimate.** `LedgerResolvers._yields`
  asks Intel by the fact key a spy files the figure under (`tax`), so a
  report's "≈ 40–60 · spy" reaches the `taxed` thread as it reaches the map
  card; the goods threads keep `gold` (no report carries them yet).
  `describes_town` is live but no report is filed on a town subject yet —
  spy reports land on the manor cell.

**For the intelligence alignment draft** (`2026-09-28-intelligence-layer-alignment.md`, still the owner's uncommitted draft, so this branch does not carry it): its §8 phase table should gain, in P0's content, "the LEDGER's L1 (split strands, accounts differ)" and, in P3's, "the LEDGER's M3 audit (`LEDGER_AUDIT`) beside the countermeasures".
