# The crown's sight and the enemy's ghosts — design

Owner report 2026-10-10: in normal (non-dev) play the enemy's army is never on the 3D map, even beside one of the crown's columns. The cause: `Map3DContext.regiments()` drew every realm's units only in DEV MODE and the player's alone otherwise, and the player's side had no sight rule at all (the hosts have `ai_sight_km`). The owner chose **option B: sight + scouting ghosts.** This completes the fog line of `2026-10-07-enemy-ai-and-battle-design.md` §2 ("玩家这边敌军是'幽灵'，数字永远是估计，来源与日期标明").

## 1. Sight (engine, pure)

`Sighting.seen_foes(repo, state)` — the foe units (`GameState.foes`) the crown SEES now, in code order: a foe with men under arms (pack headcount less its `dead`) standing within **`player_sight_km`** (inclusive, squared whole metres) of

- any land unit of the player's realm with men under arms (its `x_m` / `y_m`; a fleet sees nothing), or
- the point of any town the crown holds (`TownStores.realm_towns`, an occupied one excluded: `ArmyGround.holds`).

No random number, no float in state. `player_sight_km` (Default 12) sits under `ai_sight_km` (40: the host's scouts sweep ahead), well over `battle_contact_km` (5) and every `army_town_reach.csv` reach, so a column sees a host about a day's march before contact. On the first pack the main host gathers ~29 km from the nearest held town — out of sight, so the rumour is all the crown has — and is first seen the day after it crosses.

## 2. Ghosts (engine state, saved)

`GameState.sightings`: key → `{kind, code, x_m, y_m, day, source, men}`, ints and strings, saved whole; an old save reads `{}`.

- **Representation.** A sight and a spy name UNITS, so their ghosts are per unit, keyed by the unit code (`kind` `unit`). The border rumour names no unit, only that a host gathers, so its ghost is the HOST's, keyed `host:<host code>` (`kind` `host`), at its assembly point with `men` 0 (unknown). The first ghost of any unit of that host takes the host's ghost away.
- **Seen** (`source` `seen`): `Sighting.update`, once a day at the end of `TickEngine._end_day` (after the march, the minds, the battles, the sieges and the raids — every column where the day left it), records each seen unit at its true place today with `men` = `Sighting.about(men under arms, player_sight_estimate_quality, bias 0)`.
- **Spy** (`source` `spy`): when a spy's report is filed (`SpySystem.observe`), `Sighting.on_spy` records each foe column he counted (`SpySystem.foe_codes_near`, the same columns as the report's `foe_columns`) at its TRUE place at report time — the report is as good as the spy — with `men` = `about` at the spy's own quality and bias (no new roll).
- **Rumour** (`source` `rumour`): on the rumour's day (`EnemyAi.rumoured_host`, the host `EnemyAi.warnings` writes the letter about), a host ghost at `EnemyAi.home_m`.
- **Which wins**: a newer day; on the same day seen > spy > rumour.
- **Forgetting**: a ghost older than **`ghost_keep_days`** (Default 20; kept at exactly that age) is forgotten, as is one whose unit is no longer in the field or has no man under arms (a battle destroyed it), or whose host the campaign no longer has.
- **Drawn**: `Sighting.ghosts` lists every ghost not forgotten, but never one of a unit SEEN now (its real piece stands there) nor a host one of whose units is seen.
- `about(v, q, bias)`: the middle of `SpySystem.estimate`'s span, rounded half up to `intel_facts.csv` `foe_troops` (100), never under one step for a unit with men. A ghost never holds the exact men.

## 3. The map (`scripts/map3d/`, no `Game`)

- `Map3DContext.regiments()` out of DEV MODE: the player's units plus the seen foes' roster rows, so the existing piece pipeline draws them at their true places (cached by state, day and every unit's place). DEV MODE is unchanged: every realm's units, no ghost.
- `Map3DContext.fogged(code)`: a foe out of DEV MODE. Its chip carries no readiness / stores bars and its men as `≈` the seers' estimate (`ArmyCounters.layout` takes a point's `text`); its march road and end ring are not drawn; its order menu does not open (`ArmyOrderMenu`).
- `Map3DContext.ghosts()`: `Sighting.ghosts` as data — `{key, kind, code, x_m, y_m, day, age, source, men, label, line}`.
- **The ghost's look**: `Map3DLayerUnits` stands a ghost as its unit's own piece (a host's: its first column's), at full formation (what is left of it is unknown), STANDBY, never walking, see-through by the Units node's export `ghost_alpha` (Default 0.35) through the meshes' `transparency` — the same way a courier's piece fades (`Map3DCourierRide.apply`). A click on it picks `ghost:<key>`; its card is `Sighting.ghost_card` through `MapObjects.army_card`.

## 4. The card

- A seen foe's card (`MapObjects.army_card`, the intel `basic` level: the kingdom, the headcount as a word) gains a **Sighted** field: `Sighting.card_line` — "Seen today — about N men".
- A ghost's card: its name, whose men, "Under arms: about N" (or "unclear"), "Last known near <place>", and its line — "Last seen N days ago" / "Spy report, N days ago" / "Rumoured at the border, N days ago", "— about N men" where known. It stands at the ghost's place, never the unit's true one.
- The words are `templates.csv` `sighting_*` rows (realm slots filled at load).

## 5. Keys

| key | Default | what |
|---|---|---|
| `player_sight_km` | 12 | the crown's sight round each land unit and held town |
| `player_sight_estimate_quality` | 1000 | how well the seers count a unit's men (`SpySystem.estimate` quality) |
| `ghost_keep_days` | 20 | days a ghost is kept |

## 6. Not in this pass (needs a local session)

- The ghost's and the seen foe's look is unreviewed: `ghost_alpha`, whether a still STANDBY clip or a paused pose reads better, whether a ghost needs a ring or a tint (an editor-authored material), the `≈` chip — the `visual-review` loop with real-window shots.
- The card's field rows are unreviewed in the left column.
- `WarRoom.believed_hosts` (the WAR ROOM's place for enemy ghosts) is still empty; it can read `Sighting.ghosts`.
