# Axemen Step 2 (matchups against the foe faced) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A unit's battle strength reflects its matchups against the arms it actually faces, for every arm.
**Architecture:** New pure `BattleMatchup` (engine, RefCounted); one factor appended in the two battle factor builders; four data rows.
**Spec:** `docs/superpowers/specs/2026-11-18-axemen-arm-design.md` ("Step 2 detail").

## Global Constraints
- No edit to files pinned by `Map3DRoyalCarrierSource._SOURCES` (`army_system.gd` included).
- Whole per-mille integers, fixed iteration order (`unit_types` order), a reason on the factor.

## Review Focus
1. A foe arm with no matchup row (fleet vs land) reads neutral, never 0.
2. A unit or foe with no people (all counts 0) gives 1000, no division by zero.
3. Both battle paths (resolved battles and body-battle rounds) get the same factor.

### Task 1: BattleMatchup
**Files:** Create `scripts/engine/battle_matchup.gd`; Test `tests/engine/test_battle_matchup.gd`.
**Interfaces:** `static func permille(repo: DataRepository, own: Dictionary, foes: Array, attacking: bool) -> int` (own/foes: arm -> count rows); `static func factor(repo, state, code: String, enemies: Array, attacking: bool) -> Dictionary` (the factor row).
- [ ] Tests (rows pinned in the test): divided by the column's mean (final review: the stance-blind base let stance alone move an arm ±13%), foes weighted by fit share: pure axemen vs pure infantry attacking → 1300×1000/1100 = 1181; defending vs cavalry → 700×1000/900 = 777; a foe of every arm alike → 1000 both stances; 100 infantry + 100 axemen vs 300 cavalry (crew 2: 600 people) + 100 infantry attacking → infantry 1171 ×1000/1040 = 1125; axemen 957 ×1000/1100 = 870; unit 997; fresh infantry + 90%-down cavalry → 1148. Fleet vs infantry → 1000. Empty own or foes → 1000.
- [ ] Watch fail; implement; pass; commit.

### Task 2: Wire and data
**Files:** `scripts/engine/battle_system.gd` (`unit_strength`), `scripts/engine/body_battle_rounds.gd` (`_factors`), `data/army/army_matchups.csv`.
- [ ] Test `test_unit_strength_carries_the_matchup_factor`: a battle unit's `BattleSystem.unit_strength` breakdown has a `matchup:arms` factor; `BodyBattleRounds._factors` returns the same permille for the same unit and foes.
- [ ] Rows: infantry/archers/cavalry/artillery vs axemen as the spec; update `test_infantry_base_unchanged` to the new mean 1020 (rename `test_infantry_base_counts_its_axe_row`).
- [ ] Run engine-core, engine-military, engine-economy, ui, war_room, map3d; fix hand-computed battle tests whose expected values move, recomputing each by hand.
- [ ] Commit; PR with `prd_step: Step 8`, `wired: true`.
