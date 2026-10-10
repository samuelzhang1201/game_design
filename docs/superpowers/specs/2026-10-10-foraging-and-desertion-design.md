# Living off the land and desertion — design (army brief items 8 and 9, phase I)

Status: written 2026-10-10 after the owner's brainstorm answers (rulings in §0).
Sub-project B of the army brief of 2026-10-07 (A supply, D army split and C laws
have landed). It supersedes §2 (Sub-project B — foraging) of
`2026-10-07-war-room-p3-economy-layer-design.md`, which predates the supply
lines and was never built; B reuses that spec's capacity and stripping model,
re-based to the daily supply of `2026-10-07-army-supply-lines-design.md`.
Phase II of the brief's conduct laws (prisoners, quarter, ransom) is **not**
in this spec (§9).

## 0. The request and the owner's rulings

The owner's words (2026-10-07):

> 军队进入敌国疆域后， 会有 ‘就地征粮和劫掠’ 行为，如果军队士气训练或者士气或者补给低于一定数值，有可能未经玩家允许就自动激活‘就地征粮和劫掠’，增加补给和士气，但是肯定会有成本，我还没想好什么成本，你帮我推荐。
>
> 军队在本国疆域后， 如果军队士气训练或者士气或者补给低于一定数值，有可能出现逃兵现象。减少人员。

Rulings from the brainstorm (each can be overturned on its own):

1. **The `plunder` law is the permission** (Q1 A). No per-unit order. `allow`:
   a crown army in enemy land forages and plunders every day, automatically.
   `forbid`: it does not, except when desperate; then it breaks the law by
   itself.
2. **Gains and costs** (Q2 A). Gains: supplies (a share of the province's
   forage capacity) and morale. Costs: training, the land stripped, a share of
   the unit wounded by the peasants, and — for the desperate or the unlawful —
   legitimacy. No gold cost; the realm-level cost of `plunder: allow` stays in
   the existing monthly law effects.
3. **The automatic start is deterministic, with hysteresis** (Q3 A): no RNG.
4. **Which land** (Q4 C): by the stance the pack's `diplomacy.csv` gives the
   province's holder (`Intel.stance_of`): Enemy normal; Neutral, Suspicion,
   Unknown only at supply 0, as an incident; Suzerain, Vassal never.
5. **An incident** (Q5 B) = news, legitimacy, a hazard on that province, and a
   saved per-kingdom `grievance` counter of points, read by nothing yet. Stances are a
   static table, so a grievance cannot change one.
6. **Desertion at home** (Q6 A): per unit, per condition met, a daily share of
   the fit men leaves for good; a NEW 13th military law, `desertion_penalty`,
   scales it.
7. **Other laws that read here** (Q7 A + Q8 A): `plunder`, `no_havoc`,
   `obey_command`, `desertion_penalty`, and `protect_church`,
   `protect_women`. The rest (`register_prisoners`, `quarter`, `ransom`,
   `truce_days`, …) keep only their monthly effects until phase II.
8. **Architecture** (approach 1): a daily step beside the daily supply step —
   no month-end settlement for the trigger, no growth of `SupplySystem`.

## 1. Data

All design values live in `data/balance.csv` (first drafts, the owner tunes);
words in a new `data/conduct_words.csv` (`key,text`); laws in `laws.csv`,
`law_effects.csv`, `law_words.csv`.

### 1.1 `balance.csv`

| key | first draft | meaning |
|---|---|---|
| `forage_start_days` / `_morale` / `_training` | 3 / 25 / 5 | the lines under which an unlawful unit starts (any one) |
| `forage_start_days_obey` / `_morale_obey` / `_training_obey` | 2 / 20 / 3 | the lines with `obey_command` on |
| `forage_stop_days` / `forage_stop_morale` | 10 / 40 | an unlawful unit stops when BOTH are met |
| `forage_supply_per_food_unit` | 30 | supply units a month per `food`-tagged production unit at full season |
| `forage_spring_permille` … `_winter_permille` | 600 / 1000 / 1200 / 300 | the season's share of capacity |
| `forage_share_permille` | 1000 | the share of a day's capacity one province lends the units in it |
| `forage_strip_k` | 500 | ‰ stripped when a province's whole full monthly capacity is taken |
| `forage_recover_permille` | 100 | ‰ a stripped province recovers at the month's end |
| `forage_bare_permille` | 900 | past this, "stripped bare" news (once per crossing) |
| `forage_word_rich_permille` / `_fair_permille` | 750 / 400 | the slip's "rich" and "fair": today's yield per mille of a full summer day (above 0 but under "fair" is "thin", 0 is "stripped") |
| `forage_hazard_strip_permille` / `_protected` | 500 / 750 | stripping past which the province gets the "Raided" hazard; the second with `protect_church` on |
| `forage_morale_month` / `forage_training_month` | 4 / 3 | morale gained / training lost for 30 days foraging |
| `forage_training_floor` | 5 | the month's foraging never takes training below this (ruling R7) |
| `forage_harass_permille` | 10 | share of the fit men wounded for 30 days foraging |
| `forage_protect_cut_permille` | 100 | the yield lost for each of `protect_church`, `protect_women` on |
| `forage_incident_legitimacy` | 3 | legitimacy lost when an unlawful start happens (once per unit per month) |
| `forage_grievance_month` / `forage_grievance_month_protected` | 10 / 5 | grievance points a kingdom gains in a month the crown's armies forage in its land; the second with `protect_women` on |
| `desert_morale` / `_training` / `_supply_days` | 20 / 3 / 0 | the lines a home unit deserts under (below / below / at) |
| `desert_permille_per_day` | 3 | share of the fit men leaving a day, per condition met |
| `desert_mult_fine` / `_lenient` / `_hanging` | 1000 / 2000 / 400 | the law's multiplier, ‰ |
| `desert_news_cumulative_permille` | 50 | cumulative share of the original heads that earns its own news |

### 1.2 Laws

`desertion_penalty` — military, `discipline`, choice, values (default first)
`fine` | `lenient` | `hanging`, scope `camp`, like the other conduct laws.
`law_effects.csv`: `lenient` morale_mark +1 (unit); `hanging` peasant
contentment −0.3, legitimacy −0.2, morale_mark −1 (unit); `fine` none. The
multiplier is read by `Desertion` from the `desert_mult_<value>` keys through
`LawSystem.value`. The flags `plunder`, `no_havoc`, `obey_command`,
`protect_church`, `protect_women` already exist; this is their first reader.

## 2. State (the save)

- `state.regiments[code]` gains: `forage` ("" | "law" | "desperate"),
  `forage_days` (days foraging this month), `deserted` (men gone for good),
  `desert_rem` (the rounding remainder, units of 1/100000 of the fit men).
  `ArmySystem.fit_heads` = heads − wounded − dead − `deserted`.
- `GameState.forage_stripped`: province → ‰, only non-zero entries.
- `GameState.grievance`: kingdom → whole grievance points (see
  `forage_grievance_month`) the crown's armies earned in its land.
- `GameState.conduct_marks`: "once per month" ledger, key → month index
  (`incident:<code>`, `grievance:<kingdom>`, `desert_news:<code>`,
  `havoc:<province>:<day>`); entries of an older month are dropped at the month's
  end.
- An old save loads with all of these empty / absent keys read as zero.

## 3. The rules (engine, pure, integer, no RNG, no `Game`)

Three RefCounted classes in `scripts/engine/`; only `ArmyConduct` changes
state.

### 3.1 `Forage`

- `monthly_capacity(repo, state, province) -> int`: the province's towns'
  `food`-tagged production units × `forage_supply_per_food_unit` × the
  season's permille / 1000 (whole units, rounded once).
- `day_capacity(repo, state, province, day) -> int`: with `C = monthly_capacity
  × (1000 − stripped) / 1000`, day `d` (1..30) gets `C×d/30 − C×(d−1)/30`, so
  the thirty days sum exactly to `C`; the day is then scaled by `forage_share_permille`/1000.
- `shares(...) -> {code: units}`: for the units foraging in a province that
  day, `min(need, day_capacity × need / Σ need)` in code order, remainder to
  none. `need` = the unit's carried-load order (days × its daily use) − its
  supplies, never below 0. With `protect_church` and/or `protect_women` on
  (read per unit), the yield is cut by `forage_protect_cut_permille` each.
- `land_kind(repo, state, province) -> "home" | "enemy" | "grey" | "none"`:
  the crown's own province is home; otherwise `Intel.stance_of` of the
  holder: Enemy → enemy; Neutral / Suspicion / Unknown → grey; Suzerain /
  Vassal → none. A province nobody holds, or the sea, is none.
- `wants(repo, state, code, kind) -> String`: the unit's new `forage` value
  from §3.3's rules.

### 3.2 `Desertion`

- `conditions(repo, entry) -> int`: how many of morale < `desert_morale`,
  training < `desert_training`, supply days ≤ `desert_supply_days` hold.
- `daily_loss(repo, state, code) -> int`: only on home land. `fit × 3‰ × n ×
  multiplier‰`, kept in units of 1/100000 with the remainder in `desert_rem`
  so a small unit loses a man every few days instead of none. The loss is
  added to `deserted` and never exceeds the fit men.

### 3.3 `ArmyConduct.day_step(repo, state, day)`

Runs once a day after the day's supply step (eating, the hungry morale loss),
units in code order. Returns news and missive rows, applies state changes
through the existing reasoned channels (legitimacy with a reason string,
hazards through the call `RaidSystem` uses).

1. Find the unit's province and `land_kind`.
2. **Home:** `forage` cleared; run `Desertion`.
3. **Enemy:** `plunder: allow` → `forage = "law"`. Otherwise the start / stop
   rule: off → `desperate` when any of supply days < start_days, morale <
   start_morale, training < start_training (the `_obey` set with
   `obey_command` on); `desperate` → off when supply days ≥ stop_days AND
   morale ≥ stop_morale. A unit still under a start line restarts the next
   day; the once-a-month marks keep the news and the legitimacy cost from
   repeating.
4. **Grey:** off → `desperate` only at supply days 0 (stop as above); the
   start is an **incident**; **none** or no land: off.
5. **An unlawful start** (`desperate` begins) is charged once per unit per
   month: news; legitimacy −`forage_incident_legitimacy` ("{unit} plundered
   {province} against the law"); a missive from the marshal. In grey land
   also: the "Raided" hazard on the province, and, once per kingdom per month
   (`grievance:<kingdom>`), `grievance[kingdom] += forage_grievance_month` (`_protected` with
   `protect_women` on).
6. **Havoc:** if the start was unlawful and `no_havoc` is off, every other
   crown land unit in the same province with `forage = ""` becomes `desperate`
   the same day, without its own legitimacy charge or news.
7. **Taking:** each unit with `forage != ""` takes its share (§3.1), its
   `supplies` rise, and `forage_days += 1` only when it took more than 0 (a
   day that took nothing, full stores or stripped land, is no foraging day). The province's stripping rises by
   `taken × forage_strip_k / monthly_capacity` per taker (floor). Past
   `forage_hazard_strip_permille` (or `_protected`) the province gets the
   "Raided" hazard once. Crossing `forage_bare_permille` files the "stripped
   bare" news once per crossing.
8. **The month's end:** for each unit with `forage_days = d > 0`: morale
   += `forage_morale_month × d / 30`, training −= `forage_training_month × d
   / 30` but never below `forage_training_floor` (a unit already under it
   keeps what it has; ruling R7: training does not recover by itself, so
   foraging alone must not push a unit under its own restart or desertion
   line), wounded += `fit × forage_harass_permille × d / 30000`;
   `forage_days` reset. This unit settlement (`ArmyConduct.settle_units`)
   runs once a month in `TickEngine.advance` right after
   `ArmySystem.settle_month` (ruling R8), so the month's morale drift and
   wound recovery do not undo it. On the month's last day `day_step`
   (`settle_provinces`) recovers every province's stripping by
   `forage_recover_permille` (sorted order, clamped 0..1000, zero entries
   erased) and drops the old `conduct_marks`.
9. **Desertion letter facts** (only on home land): `desert_news:<code>` the first
   time a unit loses men in a month; once (judged by the crossing, no mark) when
   `deserted` first exceeds `desert_news_cumulative_permille` of the unit's
   original heads.

`Game` calls `ArmyConduct.day_step` from the same place it already calls the
daily supply step, and surfaces the returned news and missives as it does for
supply; the engine never names a UI class.

## 4. Presentation (text in existing places; no new scenes, no new art)

Words in `conduct_words.csv`, keys listed in a test; no kingdom named in the
text (the kingdom, province and unit are filled at runtime).

- **Letter facts** (of the Marshal's report; nothing goes to the news bar): unlawful start; the incident in grey
  land ("they will remember it"); Havoc; "stripped bare"; desertion (first
  loss of the month; past 5%). Lawful daily foraging files none.
- **Missives:** the marshal's letters use the existing `supply` kind (so no
  new keep cap): one at an unlawful start, one at a unit's first desertion of
  the month.
- **The folio / unit card:** the supply row gains the state word ("living off
  the land (law)" / "(desperate)"); a "Deserted: N" row when non-zero; the
  headcount already has the deserters taken out.
- **The war-room hover slip** (`WarGround`): in enemy or grey land
  "Forage: rich | fair | thin | stripped (N a day)", with a unit chosen "would
  feed it N of M a day"; at home "Our own land — not foraged". The intel ink
  names a province stripped past `forage_bare_permille` "Stripped".
- **The kingdom card:** "Grievance: N" only when above 0.
- **The laws screen:** the 13th law and its effects arrive from the CSVs;
  `law_words.csv` gets its words.

## 5. Tests (hand-computed, data from `SuiteData`)

- **Capacity and shares:** a province's monthly and daily capacity by
  season; the thirty daily amounts sum to the monthly; stripping lowers it;
  two units share by need; a unit never gets more than its need or its
  carry cap; the protect laws each cut 10%.
- **Switching:** with `plunder: forbid`, each of the three lines alone
  starts a unit; the stop needs both; `obey_command` lowers the lines;
  `plunder: allow` is on every day in enemy land; grey land only at supply
  0; suzerain, vassal and home never.
- **Costs:** legitimacy −3 once per unit per month; grievance points once per
  kingdom per month, fewer with `protect_women`; the hazard in grey land and
  past half stripped (three-quarters with `protect_church`); Havoc spreads
  with `no_havoc` off and stays one unit with it on; the month-end morale,
  training and wounded for a partial month.
- **Desertion:** the loss for 1, 2, 3 conditions; the three law
  multipliers; a 100-man unit loses its first man on the hand-computed day;
  deserters are permanent and leave `fit_heads`; the news once a month and
  once past 5%.
- **Save and determinism:** the new fields round-trip; an old save loads
  empty; 24 months twice from one seed give identical state.
- **Data guards:** the law and its effect rows; every `conduct_words` key
  used; no kingdom name in the words; the engine-isolation and CLAUDE.md
  size tests pass.
- **Interface:** one real-input test each for the card's state word and
  deserted row, and the hover slip's lines; then a `visual-review` pass over
  the added lines.

## 6. Documentation

A new `scripts/engine/guide/foraging_and_desertion.md`, listed in the engine
`CLAUDE.md` Topic guides index (the rule as it stands, no tuning numbers, no
owner quotes); `scripts/ui/CLAUDE.md` and the war-room guide get one line each
for the new rows; `data/CLAUDE.md` the new tables.

## 7. Order of work

Data and laws → state and save → `Forage` → `Desertion` → `ArmyConduct` and
its call in the daily loop → words, news and missives → interface lines →
docs → whole-suite run → review and fix wave → visual review → land only on
the owner's word.

## 8. Not in this spec

A gold cost; a FORAGE order; foreign armies foraging or deserting (no foreign
regiment is simulated; `RaidSystem` stays the enemy's plunder); changing a
stance from a grievance; anything reading `grievance`; market stocks as a
forage source; the 3D map and any new art.

## 9. Phase II (separate spec)

Prisoners, quarter, ransom and prisoner registration — the laws
`register_prisoners`, `quarter`, `ransom` and `truce_days` — need a battlefield
capture mechanism that does not exist. They get their own brainstorm and spec
after this phase lands.
