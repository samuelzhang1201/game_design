# Regiment state, terrain and the War Room placeholder — design

Owner request 2026-09-17. Approved in chat ("go") the same day.

## Goal

1. The regiment counters on the MILITARY layer scale with the map and are
   never thinned: every one of the player's regiments is always drawn while
   the layer is on.
2. Each of the player's regiments carries a state — morale, wounded,
   supplies, a hidden training value and hidden per-arm attack/defence — that
   the monthly settlement moves and the regiment card shows, the hidden
   numbers only as fuzzy grades.
3. Terrain gives each arm a buff or debuff, quartered (defending) or
   attacking, from data.
4. A PLACEHOLDER battle-odds function, wired into nothing.
5. A WAR ROOM tab that opens a placeholder page.

Out of scope: resupply (supplies only fall), morale change, training growth
(its rate exists and is 0), battles, moving regiments, other kingdoms'
regiments (they get no state).

## 1. Counters scale with the map

`WorldMapView.army_badge_height()` becomes
`max(map_army_badge_native_px × view_scale(), map_army_badge_min_px)`:
proportional to the zoom, with a small floor so a counter is still visible
from the farthest zoom. `map_army_badge_frac` and `map_army_badge_max_px`
go (the counter no longer follows the settlement drawing's height).

`army_markers()` keeps its stacking (a counter meeting a town or another
counter moves down) but has no thinning of any kind; the only filter is the
screen frame. A test holds that, at several zooms, the number of markers
equals the number of the player's regiments whose point lies in the frame.

Still only while the MILITARY layer is on (owner's answer).

## 2. State

`GameState.regiments: Dictionary` — `regiment_code -> {morale, wounded,
supplies, training}`, only for the player's realm's regiments, saved in
`to_dict` / `from_dict`. All whole numbers.

`ArmySystem.ensure(repo, state)` adds any missing regiment of the player's
realm with its starting values from `balance.csv`:
`army_start_morale` (0..100), `army_start_training` = 10 (militia),
`wounded` 0, `supplies` = headcount × `army_supply_per_head_permille` / 1000
× `army_start_supply_months`. It runs at the settlement and before a card
reads the state, so a fresh campaign and an old save behave alike.

Headcount is `MapObjects.regiment_size` (the pack's arms summed). Wounded
are a count out of that headcount: `0 <= wounded <= headcount` always.

## 3. Monthly settlement

`ArmySystem.settle_month(repo, state)`, called from `TickEngine.advance`
after the economy's settlement, in regiment-code order:

- **Wounded recover**: `recovered = wounded × army_wound_recovery_permille
  / 1000` (integer division), at least 1 while any are wounded; wounded are
  then clamped to `[0, headcount]`.
- **Supplies are spent**: `use = headcount × army_supply_per_head_permille
  / 1000`; `supplies = max(0, supplies − use)`. No resupply, no consequence
  at 0 (placeholder).
- **Training** rises by `army_training_per_month` (0) up to 100.
- **Morale** does not change.

The card shows the two rates as the month's figures computed by the same
functions (`ArmySystem.wound_recovery(...)`, `ArmySystem.supply_use(...)`).

## 4. Terrain

`ArmySystem.terrain_of(repo, state, regiment) -> String`, from the land
cell holding the regiment's point (the same point-in-polygon lookup as
`MapEconomy.burg_cells`, generalised into `MapEconomy.cell_at(repo,
point)`):

- a naval regiment → `sea`;
- cell height ≥ `manor_focus_peak_height` → `mountains`;
- ≥ `manor_focus_high_height` → `hills`;
- otherwise by biome, from `data/army_terrain_biomes.csv` (biome_id →
  terrain): grassland/savanna → `plains`, temperate forests and taiga →
  `forest`, tropical forests → `jungle`, wetland → `marsh`, deserts →
  `desert`, tundra/glacier → `tundra`.

**Fortified**: a burg with `walls` or `citadel` in its `features` stands in
the same cell. Shown as "(fortified)" beside the terrain.

`data/army_terrain.csv`: `terrain, arm, defend_permille, attack_permille`
(1000 = no effect), with a `fortified` row set per arm applying on top when
defending. First-draft numbers the owner will tune: cavalry in mountains
700/650 and in jungle and marsh 750/700; infantry in jungle 800/800;
infantry fortified defend 1300; archers in hills and fortified defend 1150
and 1250; artillery in mountains and marsh 700/700; fleet at sea 1000/1000.
A missing row is 1000.

## 5. Hidden values and fuzzy grades

**Matchups**: `data/army_matchups.csv`: `arm, vs_arm, attack_permille,
defense_permille` — the base of each arm against each other arm (first
draft: cavalry strong against archers and artillery, infantry
(spears) strong against cavalry, archers strong against infantry).

**Float**: each regiment's value against each `vs_arm` is scaled by a
factor in `1000 ± army_float_permille`, derived from a hash of
(regiment code, vs_arm, tick) — deterministic, no draw from the engine's
RNG stream (so no existing seeded test shifts), and it changes each month.

**Power** (defending, where it stands):
`Σ_arm effective_heads(arm) × mean_over_vs_arm((attack + defense) / 2 ×
float) × training_factor × morale_factor × terrain_factor(arm, defend)`,
all permille integers, where `effective_heads` scales each arm by
`(headcount − wounded) / headcount`,
`training_factor = army_training_base_permille + training ×
army_training_step_permille`, and `morale_factor =
army_morale_base_permille + morale × army_morale_step_permille`.

**Strength grade**: the regiment's power over the mean power of the
player's regiments of the same kind (land with land, fleet with fleet):
ratio ≥ `army_strong_ratio_permille` (1250) → Strong; ≤
`army_weak_ratio_permille` (750) → Weak; else Average. A kind with one
regiment is Average.

**Training grade** (`data/army_training_grades.csv`, `above, label`, first
match from the top): above 80 Elite, above 50 Well drilled, above 30
Recruits, else Militia.

UI words are English like the rest of the game (Strong / Average / Weak,
Elite / Well drilled / Recruits / Militia).

## 6. Battle odds (PLACEHOLDER)

`ArmySystem.battle_odds(repo, state, attacker_code, defender_code) ->
float`: the attacker's power (attack stance, its own terrain) over the sum
of both powers. Marked PLACEHOLDER in its doc comment: the owner has not
decided the formula. Called by nothing but its test.

## 7. Regiment card

`MapObjects.army_card` gains, for a regiment with state, stats (icon, short
text, full tooltip) in this order after the existing ones:

- Terrain — "Hills" / "Hills (fortified)";
- Morale — "70";
- Under arms — "5,000 (120 wounded)" replaces the plain headcount;
- Wound recovery — "+12 / mo";
- Supplies — "3,000 (−500 / mo)";
- Training — the grade word;
- Strength — the grade word.

New `data/resource_icons.csv` rows `army_terrain`, `army_morale`,
`army_wounded`, `army_supply`, `army_training`, `army_strength` with a
glyph and no texture (the glyph draws until art exists).

## 8. War Room tab

`BottomBar.TABS` gains `WAR ROOM` (not a toggle). `GameRoot` routes it to
`InfoScreen.show_tab`, whose rows for it are one placeholder line ("The war
room is being prepared."). The ten tabs must still fit the 1280 px row;
a test holds it.

## Testing (GUT, hand-computed expectations)

- `ArmySystem`: ensure seeds only the player's regiments with the balance
  values; wound recovery (including the minimum of 1 and the clamp at
  headcount); supply use to 0; training cap; determinism of the float (same
  tick same factor, next tick different); terrain classification for a
  hand-picked mountain, hills, forest and sea cell of the pack and a
  fortified burg; terrain lookup with a missing row = 1000; training grade
  at 10, 30, 31, 50, 51, 80, 81; strength grade at the two thresholds;
  battle_odds is in (0, 1) and grows when the attacker gains heads.
- `GameState` save round trip keeps `regiments`.
- `WorldMapView`: counter height proportional to zoom above the floor; the
  marker count equals the in-frame regiment count at three zooms.
- `MapObjects.army_card` shows the seven new stats.
- `BottomBar`: WAR ROOM exists, opens the placeholder, the row fits.
