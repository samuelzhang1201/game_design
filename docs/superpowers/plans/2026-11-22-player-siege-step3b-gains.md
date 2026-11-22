# Player siege step 3b — control stops at the realm, and what a capture gives

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the second half of spec §11 row 3. The crown's control counts only its own realm's provinces, and a crown capture of a foreign town pays the council, the sack and a once-per-occupation key.

**Architecture:**
- **Control.** `MapManors.crown_controls` also asks that the province is the player's realm's (`MapOwnership.owner_of`). `controlled_provinces` is built on it, so every reader follows: BUILD, FOCUS, purses, the dashboard, the model's lists and spy refusal. `controlled_provinces`' cache key adds `province_owner`.
- **Gains.** They run in `SiegeSystem._take`, right after `_occupy`, when the crown made a fresh occupation of a town. They do not run on a retake.

**Tech Stack:** Godot 4.7 GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` §7 (the last two bullets) and §11 row 3. Step 3a: `2026-11-22-player-siege-step3-sides.md`.

## Global Constraints

- Inv. 1–11. Whole numbers. A reason on every move. Engine-pure code.
- Never edit `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd` or `war_front.gd`.
- Numbers go in `data/battle/balance.csv`. A signature goes in `data/realm/action_signatures.csv`.

## Decisions

- **The signature.** `TOWN_TAKEN` has the same axes as `BATTLE_LOST` (militarism 20, expansionism 10). It is the mirror of the loss.
- **The opinion formula.** Each seat moves by `+round(battle_victory_opinion × (1 + w))`, where `w` is `OpinionDrift.weight` clamped to −1..1. The result runs from 0 to +2 × base, so it is never a loss.
  - The spec's "a seat of opposed ideology feels it as a loss by the drift's own sign" cannot happen under the formula it gives. An opposed seat's gain shrinks toward 0 instead, mirroring the loss's "never a gain".
  - This is flagged for the owner in the PR.
- **The reason** is `took <town> from <realm> (supports, <axis>)`, where `<realm>` is `repo.realm_label(defender)`.
- **The sack.** It happens when the plunder law (`LawSystem.value`) of the record's first unit, in code order, reads `allow`.
  - The amount is `RaidSystem.month_of(town's own manor) × siege_sack_permille / 1000`, whole gold rounded down. The month is read before the manors move.
  - It goes into `metrics.strategic` through `WorldLedger.apply`, with source `sack` and reason `sacked <town>`.
  - `no_sack` is a terms flag of step 11 and is not read yet.
- **Once per occupation.** `GameState.town_takes` is saved as an Array of `{town, day}`, where day is the occupation's day. If the same key comes again, nothing is paid.
- **The holder's lines need no new code.** The occupied manors' lines pay as before: the economy sums only the realm's provinces, so a foreign province's lines reach no crown purse.
- **The recruitment list is not touched.** `army_recruitment_panel.gd` lists by `ArmyGround.holds`; that gap belongs to step 12, where the crown first occupies a town in play.

## Review Focus

1. **A crown province that changes realm by `MapOwnership`** (an event, or another kingdom's conquest) leaves `controlled_provinces` on the same day. The cache key carries `province_owner`.
2. **A retake of the crown's own town pays nothing.** It is a liberation, not a capture.
3. **Taking the same town again** after a liberation is a new occupation, so it pays again on a later day.
4. **An empty or missing council seat** is skipped, as `DefeatSystem._council` does.
5. **A save round-trip keeps `town_takes`.**

---

### Task 1: The crown's control stops at its realm

**Files:**
- Modify: `scripts/engine/map_manors.gd` (`crown_controls`, and the signature in `controlled_provinces`)
- Test: `tests/engine/test_siege_gains.gd` (new)

- [ ] Write the failing test `test_control_stops_at_the_realm`. Give every manor of a raider province to `MapManors.crown(s)` with a reason. Then:
  - assert `MapManors.controller_of` is the crown house;
  - assert the province is not in `controlled_provinces`, and `crown_controls` is false.
  - Then call `MapOwnership.set_owner` to move one of the crown's provinces to the raider, and assert it leaves `controlled_provinces` (this checks the cache).
- [ ] Run it: `godot_lock.sh ./run_tests.sh --test tests/engine/test_siege_gains.gd`. Expected: FAIL.
- [ ] Implement: `crown_controls` returns false when `MapOwnership.owner_of(repo, state, code) != repo.resolve_realm("player_realm")`. Add `state.province_owner.hash()` to the `controlled_provinces` signature.
- [ ] Run it again, plus the map_manors, purchase, economy and army-towns tests. Expected: PASS.

### Task 2: What a capture gives the crown

**Files:**
- Modify: `scripts/engine/siege_system.gd` (`_take`, plus a new `_gains`)
- Modify: `scripts/engine/game_state.gd` (`town_takes`, saved)
- Modify: `data/realm/action_signatures.csv` (`TOWN_TAKEN`)
- Modify: `data/battle/balance.csv` (`battle_victory_opinion` 5, `siege_sack_permille` 500)
- Test: `tests/engine/test_siege_gains.gd`

**Interfaces:**
- Produces: `SiegeSystem.opinion_gain(base: int, w: float) -> int`.
- Produces: the `siege_ours_taken` event gains `opinion` (`[{character_id, delta, reason}]`) and `sack` (int gold).

Tests. Each fixture finds an undefended raider town and opens a crown record with one unit at its gate, as `test_siege_sides` does.

- [ ] `test_council_gain_is_hand_computed`. Set `battle_victory_opinion` to 5.
  - Expected: the marshal +6, the chaplain +4, the chancellor +5. These mirror `test_defeat`'s −6 / −4 / −5 for the same inputs.
  - Each seat gets one log entry, whose reason starts with `took <town> from <raider label> (supports, `.
- [ ] `test_no_sack_without_plunder_allowed`. The strategic delta is 0, and the event's `sack` is 0.
- [ ] `test_sack_under_plunder_allow`:
  - Call `LawSystem.impose(..., "plunder", "allow")` and set `siege_sack_permille` to 250.
  - Expected: `got == month × 250 / 1000`, where `month` is the town manor's `RaidSystem.month_of` read before the fall and `month > 0`.
  - The ledger gets one line with source `sack`.
- [ ] `test_town_takes_once_per_occupation`:
  - Call `_take`'s gains a second time with the same key and assert it pays nothing.
  - Then free the town, take it again on a later day, and assert it pays again.
  - Assert `town_takes` survives `to_dict` / `from_dict`.
- [ ] `test_retake_pays_nothing`. Use `test_siege_sides`' `_occupied` fixture and retake the town. Assert no opinion moves, `town_takes` is empty, and the strategic stores are unchanged.
- [ ] Implement:
  - `_gains(repo, state, town, defender, units, month) -> Dictionary` (`{opinion, sack}`), called from `_take` when `attacker == player` and the occupation is the crown's and fresh;
  - `opinion_gain`;
  - `town_takes`, the CSV row and the two keys.
- [ ] Run `test_siege_gains`, `test_siege_sides`, `test_siege`, `test_defeat` and `test_raid`. Expected: PASS.

### Task 3: Guides and the full check

- [ ] Update `scripts/engine/guide/siege.md` (the gains) and `guide/raid_and_defeat.md` (the mirror of the loss). Add one line in `scripts/engine/CLAUDE.md`'s Manors section: control counts only the realm's provinces.
- [ ] Run `godot_lock.sh ./run_tests.sh --base origin/main` in the background. Then commit, push, and open the PR with `prd_step: Step 8`, `player_outcome`, `wired: false` and `GUT_INCLUDE: gameplay`.
