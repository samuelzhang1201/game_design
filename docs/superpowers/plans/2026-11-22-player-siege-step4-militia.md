# Player siege step 4a: town militia — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A besieged town with no defenders raises a militia from its population — real people, enlisted and released through the personnel model — that defends it from the works and stands down when the siege ends.

**Architecture:** One new pure class `TownMilitia` (size, raise, stand down) and one table `data/battle/town_militia.csv`. `SiegeRecord._open` raises the militia (never in the old-save conversion); `SiegeSystem.settle_day` stands down every militia unit whose record is gone. The unit is an ordinary unit (`army_roster` row + `military_rosters` + one commoner cohort, `MilitaryRoster.mobilize`), in `regiments` for a crown town and in `foes` (host "") for any other, on the town's seat, so `SiegeSystem.defenders_of`, the contact rule and the works already count it.

**Tech Stack:** Godot 4.7 GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` §5 ("Militia", "The people behind them"), §8 (militia stand down when the record closes), §10 (old saves: no militia for a siege already running), §11 row 4.

## The split of step 4

Spec §11 row 4 is three pieces. It is split like step 3:

- **4a (this plan, one PR):** `TownMilitia`, `town_militia.csv`, the population ledger lines (raise → dead → stand down), militia never march. Fixtures: militia size by works and population; people conserved over raise → dead → stand down. No live campaign change yet: an enemy host opens a siege only before a garrisoned crown town, and the crown cannot besiege yet (step 12), so `wired: false`.
- **4b (next PR):** woken garrisons (a foreign town's standing roster units woken into `foes` at open, returned to the roster with their losses when the siege lifts with them alive and in place), and `EnemyAi` counting the militia a town would raise as its defence (`_gather`), with an empty town besieged instead of RAIDed (spec §5: "RAID applies only to plain manors"). That PR changes the invasion run (`wired: true`); step 5 re-tunes it. Until 4b, a town whose seat is held by a stateless roster unit counts as garrisoned and raises no militia.

## Global Constraints

- Engine-pure `RefCounted`, deterministic, whole numbers, no random draw; every number in `data/` (`town_militia.csv`, `army_living_cap_men`, `recruitment_eligible_permille`).
- Militia people are enlisted and released through `MilitaryRoster.mobilize` / `transition`, "with no direct population debit": population falls only when a man dies; the living are released with the reason `militia of <town> stood down`.
- "The size cap is the militia table's `men_cap`, bounded by what the province can still mobilise. The recruitment panel's caps do not apply."
- "Militia never march: every movement order on a militia unit is refused" — words from `data/army/task_words.csv`.
- "Old saves load … with no militia for a siege already running. Militia rise only for a siege that opens after loading."
- Never edit `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd`, `war_front.gd`.

## Review Focus

- A town whose province has fewer eligible civilians than the table asks → the militia is smaller (arms in table order take what is left), never a refused mobilisation. Test: `test_size_bounded_by_what_the_province_can_mobilise`.
- A militia unit still in a battle when its record closes → it stands down only once the battle is over (no unit vanishing from a running battle). Test: `test_stand_down_waits_for_the_battle`.
- A militia man captured → the captive stays a captive (PrisonerSystem's), the rest are released and the unit row is kept until no captive is left. Test: `test_captives_keep_the_unit_row`.
- A town falling with its militia → the militia does not march out (it is no column); it stands down that day. Test: `test_fall_stands_the_militia_down`.
- A save mid-siege → the militia unit and the record's `militia` survive `to_dict` / `from_dict`. Test: `test_militia_round_trips_the_save`.

---

### Task 1: the table and the size

**Files:**
- Create: `data/battle/town_militia.csv`, `scripts/engine/town_militia.gd`, `tests/engine/test_siege_militia.gd`
- Modify: `data/tables.csv` (row `battle,town_militia`), `scripts/engine/data_repository.gd` (load it), `data/CLAUDE.md` (one line in the battle tables)

**Interfaces:**
- Produces: `repo.town_militia: Array` of `{works: String, arm: String, men_permille: int, men_cap: int}` in file order; `TownMilitia.works_of_town(repo, town) -> String` ("citadel" / "walls" / "town", the same test as `ArmySystem.works_of`); `TownMilitia.size(repo, state, town) -> Dictionary` arm → men (whole crews, arms with 0 left out, table order). `state` null = no province bound.

Table (first draft; step 5 tunes):

```
works,arm,men_permille,men_cap,notes
citadel,infantry,30,600,…
citadel,archers,15,300,
walls,infantry,20,400,
walls,archers,10,200,
town,infantry,10,200,
town,archers,5,100,
```

Formula per row of the town's works: `min(population × men_permille / 1000, men_cap)` rounded down to whole crews (`unit_types` `crew`); then, with a state, each arm in table order takes at most what is left of `MilitaryPopulation.available(province, "urban_population")` and of `army_living_cap_men`. `population` = the burg's `population`.

- [ ] Test `test_size_by_works_and_population` (state null): population 12551 walls → `{infantry 251, archers 125}`; citadel → `{376, 188}`; no walls → `{125, 62}`; 40000 walls → `{400, 200}` (the caps).
- [ ] Test `test_size_bounded_by_what_the_province_can_mobilise`: the province's urban ledger set so `available` is 100 → `{infantry: 100}`.
- [ ] Implement; run `./run_tests.sh --test tests/engine/test_siege_militia.gd`; commit.

### Task 2: raise at open, stand down at close

**Files:**
- Modify: `scripts/engine/town_militia.gd`, `scripts/engine/siege_record.gd` (`_open`, `ensure_for`, `migrate`), `scripts/engine/siege_system.gd` (`settle_day`, `_take`), `scripts/engine/army_ground.gd` (`seated_in`)
- Test: `tests/engine/test_siege_militia.gd`

**Interfaces:**
- Consumes: Task 1's `size`.
- Produces: `TownMilitia.raise(repo, state, id: String) -> String` (the unit code, "" when none); `TownMilitia.town_of(state, code) -> String` (an entry's `militia_town`); `TownMilitia.stand_down(repo, state) -> Array` (events `{kind: "militia_stood_down", unit, town, released, day}`); record field `militia: Array` (unit codes); `SiegeRecord._open(repo, state, town, attacker, levy := true)`, `ensure_for(repo, state, host, levy := true)`.

Rules:
- `raise` runs in `_open` when `levy` and the town has no defenders (`SiegeSystem.defenders_of` empty) and no unit holds its seat (`ArmyGround.seat_of` ""; 4b wakes such units). `migrate` opens with `levy` false.
- Codes: unit `militia:<siege id>`; cohort `militia:<siege id>:commoner`; mobilize event `militia:<siege id>`, reason `militia of <town> raised`. One unit, all commoners (a levy has no named commander), source the town's province `urban_population`, stage `active`.
- Row like `RecruitmentSystem._complete`'s: label `<Town> militia`, `kingdom_code` the record's defender, `organization_arm` the first arm of the size, `camp_town` the town, `source_parts` per arm. Entry `ArmySystem.starting_state`, put on the town's point, `militia_town`, in `regiments` (crown; `LawSystem.on_settle`) or `foes` (`host` ""); `town_seat[town]` = the unit.
- `seated_in`: a foe with a `host` holds no seat (unchanged); a host-less foe may.
- `_take`: a militia defender does not march out and is not counted in `garrison_out`.
- `stand_down` (end of `settle_day`, both returns): each militia unit no record lists and in no battle: its fit and wounded go to `released` (`MilitaryRoster.transition`, event `militia:<code>:stood_down`, reason `militia of <town> stood down`); with no captive left, its entry, roster row, personnel roster, cohorts and seat go.

- [ ] Tests: `test_empty_foreign_town_raises_militia` (crown `open_units` before a raider town with no seat: one foe on the seat, host "", kingdom the raider's, in `defenders_of`, fit = the size total, ledger unchanged, `available` down by the total); `test_crown_town_militia_is_its_garrison` (a host's SIEGE before an empty crown town: the unit in `regiments`, in `EnemyAi.garrison_of`); `test_a_garrison_raises_none`; `test_running_siege_from_an_old_save_raises_none`; `test_people_conserved_raise_dead_stand_down` (10 die: ledger −10; record closed + stand down: unit and cohorts gone, `occupied` back to before, the reason in `military_events`); `test_stand_down_waits_for_the_battle`; `test_captives_keep_the_unit_row`; `test_fall_stands_the_militia_down`; `test_militia_round_trips_the_save`.
- [ ] Implement; run the file and `--category engine-military`; commit.

### Task 3: militia never march

**Files:**
- Modify: `scripts/engine/action_system.gd` (`_validate_army`: ARMY_MARCH, ARMY_SEAT), `scripts/engine/army_tasks.gd` (`preview`), `data/army/task_words.csv` (key `militia`)
- Test: `tests/engine/test_siege_militia.gd`

- [ ] Test `test_militia_never_march`: ARMY_MARCH and ARMY_SEAT on the crown militia are refused with `task_words.militia`; `ArmyTasks.preview` with it refuses with the same words.
- [ ] Implement; run; commit.

### Task 4: guide and PR

- [ ] `scripts/engine/guide/siege.md`: a **Militia** bullet (the rules above); `defenders_of`'s "militia and woken units are step 4" becomes "woken units are step 4b"; check `test_claude_md_size.gd`.
- [ ] Run the affected categories (`engine-military`, `engine-core` for data tests) and `--category gameplay` (siege/raid scenarios touch `_take` and `seated_in`).
- [ ] PR: `prd_step: Step 8`, `player_outcome:`, `wired: false`, `GUT_INCLUDE: gameplay`; say the militia shows as the infantry piece (`organization_arm` infantry) until the militia model lands.
