# Foraging and desertion (`Forage`, `Desertion`, `ArmyConduct`)

Spec `2026-10-10-foraging-and-desertion-design.md`. Integers only, no RNG, code order; every number a `balance.csv` key (`forage_*`, `desert_*`: read the CSV for the value), every word `data/conduct_words.csv`. Only the crown's own LAND units take part: fleets, foes and units that eat nothing are skipped (no foreign regiment is simulated).

## Day order

`TickEngine._end_day` runs `ArmySystem.eat_day`, `ArmySystem.hunger_day`, then `ArmyConduct.day_step` (its events land in `day_conduct`, filed as ONE `supply`-kind "Marshal's report" letter by `MissiveWriter.conduct_dispatch`), then `SupplyLines.warn_day`, so the supply warnings read what foraging left. `day_step` is three passes: (1) each land unit in code order: on home land `forage` is cleared and `Desertion` runs; elsewhere `ArmyConduct.switch`; (2) per province (sorted) the day's take, `take_day`; (3) `settle_month`, which acts on day 30 only.

## Land kinds (`Forage.land_kind`)

By the holder of the unit's province: `home` (the crown's own), `enemy` (`Intel.stance_of` = Enemy), `grey` (Neutral, Suspicion, Unknown), `none` (Suzerain, Vassal, any other stance, or a blank province code such as the sea). A province nobody holds has owner "", which `Intel.stance_of` reads as Unknown, so it is grey. A unit on `none` land does not forage.

## The switch (`ArmyConduct.wants` / `switch`)

- `forage` is `""`, `"law"` or `"desperate"`. **`plunder: allow` is the permission**: a unit on enemy land reads `law` every day.
- Otherwise on enemy land: off becomes `desperate` when ANY of supply days, morale, training is under its start line (`forage_start_*`; the `_obey` set when `obey_command` is on); `desperate` stops only when BOTH supply days and morale reach the stop lines (`forage_stop_*`): hysteresis. A unit still under a start line restarts the next day. A `law` unit whose licence is gone is judged as off.
- On grey land a unit goes `desperate` only at zero days in hand (stops as above).
- **An unlawful start** (off to `desperate`) costs, once per unit per month (`incident:<code>` mark): legitimacy `forage_incident_legitimacy` through `WorldLedger.apply` with the reason "<unit> plundered <province> against the law", and an event (`forage_unlawful` on enemy land, `forage_incident` on grey). On GREY land it also lays the "Raided" hazard (`lay_hazard`, once while it stands) and, once per kingdom per month (`grievance:<kingdom>`), adds `forage_grievance_month` (`_protected` with `protect_women` on) to `GameState.grievance[kingdom]`. Nothing reads grievance but the kingdom card.
- **Havoc**: unless the starter keeps `no_havoc` on, every other crown land unit in that province with `forage == ""` becomes `desperate` the same day, with no legitimacy charge of its own; one `forage_havoc` event per province per day. A converted unit keeps that state for the day (it is not re-judged).

## Taking and stripping (`take_day`, `Forage`)

- Capacity: the province's burgs' `food`-tagged production units × `forage_supply_per_food_unit` × the season's `forage_<season>_permille` (`Forage.monthly_capacity`); cut by `GameState.forage_stripped` (per mille) into the month's remainder; day `d` gets the running thirtieth, so the days sum to the month before `day_capacity` scales the day by `forage_share_permille`/1000 (a scale, not a cap).
- `Forage.shares` splits the day among the province's foragers by need (carried-load order less supplies, bounded by what the unit may hold), each cut by `forage_protect_cut_permille` per law of `protect_church`, `protect_women` it keeps. A unit never takes past its need or its cap; leftover goes to no one.
- Each taker raises `supplies` (and `forage_days`, only on a day it took more than 0), and strips the province by `taken × forage_strip_k / monthly_capacity` (floor, per taker). At or past `forage_hazard_strip_permille` (`_protected` if any taker keeps `protect_church`) the province gets the "Raided" hazard once while it stands (laid again after it expires). Crossing `forage_bare_permille` files `stripped_bare` once per crossing.
- `Forage.word_of` is the slip's "rich | fair | thin | stripped" (today's yield against a full summer day, `forage_word_*`).

## The month's settlement (`settle_month`, day 30)

For each unit with `forage_days = d > 0`, wherever it now stands: morale up `forage_morale_month × d/30`, training down `forage_training_month × d/30` but never below `forage_training_floor` (a unit already under it keeps its training), morale capped at 100, wounded up by `forage_harass_permille` of the fit men × d/30; `forage_days` reset. Every stripped province recovers `forage_recover_permille` (sorted, zero entries erased). `conduct_marks` of an older month are dropped.

## Desertion (`Desertion`, home land only)

Conditions held: morale under `desert_morale`, training under `desert_training`, days in hand at or under `desert_supply_days`. The daily loss is `desert_permille_per_day` of the fit men per condition held × the `desertion_penalty` law's multiplier (`desert_mult_<fine|lenient|hanging>`), kept in 1/100000 of the fit men with the remainder in `desert_rem`, so a small unit loses a man every few days. `deserted` is permanent: `ArmySystem.fit_heads` takes it out, and `ArmySystem.under_arms` subtracts `deserted` itself (it does not call `fit_heads`). Letter facts: `deserting` the first loss of a unit's month (`desert_news:<code>` mark), `deserting_big` once when `deserted` first passes `desert_news_cumulative_permille` of the heads (judged by the crossing, no mark).

## Who reads which law

`plunder` (permission), `obey_command` (lower start lines), `no_havoc` (Havoc), `protect_church` (yield cut; hazard line), `protect_women` (yield cut; smaller grievance), `desertion_penalty` (the multiplier; its `law_effects` rows carry the realm side). All through `LawSystem.value` with the unit's code. Phase II (prisoners, quarter, ransom, `register_prisoners`, `truce_days`) behaviour is NOT built: those laws' monthly `law_effects.csv` rows still apply, but their `flag` rows (behaviour hooks) have no reader yet.

## What is saved

Regiment entry keys `forage`, `forage_days`, `deserted`, `desert_rem`; `GameState.forage_stripped` (province → per mille; non-zero after the day-30 settlement, a 0 entry can exist until then), `grievance` (kingdom → points), `conduct_marks` (key → the tick it was set; `mark_once` is true the first time in a tick; keys `incident:<code>`, `grievance:<kingdom>`, `desert_news:<code>`, `havoc:<province>:<day>`). An old save reads all of them as empty or zero.

## Where it shows

Words from `repo.conduct_words`: the folio and unit card ("Foraging" row, "Deserted" row, `WarFolio.conduct_rows`; the card's supply tooltip repeats the state), the hover slip (`WarGround`: "Forage: <word> (N a day)", what the chosen unit would be fed, "Our own land, not foraged" at home), the kingdom card ("Grievance: N" when above 0), the war-room intel ink ("Stripped" at a province past `forage_bare_permille`), and the Marshal's report letter. The `day_conduct` events (unlawful start, incident, Havoc, stripped bare, deserting, deserting_big) are consumed only by `MissiveWriter.conduct_dispatch`: facts of that one letter a day, not news-bar lines.

## Tests

`tests/engine/conduct_helpers.gd` builds the fixtures from the repo (no pack, kingdom or province named). `Forage` caches food counts per repository: call `Forage.forget()` after a test edits the production rows.
