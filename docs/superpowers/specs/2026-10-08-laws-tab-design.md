# Laws: a data-driven layer, decreed by courier — design

Owner request 2026-10-07 (items 10–13 of the fourteen-item army brief; supply, items 1–7, is `2026-10-07-army-supply-lines-design.md`, the army split, item 14, is `2026-10-07-army-split-and-ground-design.md`; foraging, plunder and desertion are sub-project B):

> 10. 法律页：经济、政治、军事三个子页，不要美术。
> 11. 每一次法律变更都由信使送达，军事法律送到每一支部队。
> 12. 例如“允许/禁止劫掠”，以及中世纪军法：服从指挥、保护教会、保护妇女、禁止擅自喊“Havoc”、俘虏登记、佩戴标识、禁止私斗。
> 13. 请脑暴骑士精神政策。

**Status: BUILT 2026-10-08 on feat/laws-tab (not yet merged); the screen's look awaits the visual review.** Design approved in chat 2026-10-08 (owner, section by section); where the build settles what this text leaves open, §11 rules. The owner's answers, in order:

- existing settings: **A** — tax rate, tariff, grain ration, justice severity and church policy become laws, and every change rides by courier;
- delivery of economy and political laws: **A** — one courier to each province, a province's new law is in force when its courier arrives;
- delivery of military laws: **B** — one courier to each camp (a town, reaching every unit camped by it);
- units outside a camp (in the field, on the march): **A** — each gets its own courier, aimed at it as a march order's is;
- the effect of the military laws: **A** — all of them (the first answer given as C was a slip, corrected by the owner) have data-driven effects through the existing channels, every effect with a reason string;
- how an economy law pays: **A** — a province's monthly settlement reads the rate in force THERE;
- chivalry candidates: **A** — four are added to the owner's eight (quarter, ransom, truce days, inviolable envoys);
- overall approach: **A** — a data-driven layer (two CSV tables, two state maps, one order).

**Build order.** War-system work ahead of its PRD §6 place, by the owner's direct request (2026-10-07).

## 1. What changes

| Today | After |
|---|---|
| LAWS opens a read-only table (tax, tariff, ration) | LAWS opens a screen with three sub-pages (economy, politics, military): a row per law with its decreed value, its delivery, its effects, a control and a Decree button |
| Five policy actions (`TAX_RATE_ADJUST`, `TARIFF_ADJUST`, `GRAIN_POLICY_SET`, `JUSTICE_SEVERITY`, `CHURCH_POLICY`) act at once on a realm-wide metric | One order, `LAW_SET`; its change reaches each place by courier; the old action codes are removed |
| One realm-wide tax and tariff rate in the settlement | Each province's settlement reads the rate in force in that province |
| No military laws | Twelve military laws (§6) with effects, and flags that sub-project B and later systems read |

Unchanged: the courier ride itself (road network, weather, pace, the 60-day fuse), the order-cost guarantee (every executed order carries a cost), the council's role as the source of suggestions.

## 2. Ontology and state

### 2.1 A law (`data/laws.csv`)

A row per law: `law_code`, `tab` (economy | politics | military), `group` (a label for the military page's sections), `label`, `kind` (toggle | choice | range), `values` (the allowed values; for a range, `min|max|step`), `default`, `scope` (province | camp), `gold_cost`, `admin_cost`, `cooldown_ticks`, `notes`.

Seventeen laws:

| Page | Laws |
|---|---|
| Economy | tax rate (range 1..10), tariff rate (range 0..10), grain ration (toggle) |
| Politics | justice severity (range), church policy (choice) |
| Military | plunder, obey command, protect the church, protect women, no unauthorised "Havoc", register prisoners, wear badges, no private feuds, quarter, ransom, truce days, inviolable envoys |

Words for the screen (the pages' and groups' titles, the values' labels, the refusal texts) are in `data/law_words.csv`.

### 2.2 State (`GameState`, saved)

- `law_decree`: `law_code -> {value, decree_id, day}` — what the crown has decreed. `decree_id` is a per-law, ever-rising integer.
- `law_in_force`: `scope_key -> {law_code -> {value, decree_id}}` — what each place or unit follows.
  - `province:<code>`: an economy or political law, in a province.
  - `town:<code>`: a military law, in the camp round a town.
  - `unit:<code>`: a military law, in a unit standing in the field or on the march.
- A place with no entry for a law follows the law's default.

Every value is a whole number or a string; nothing floats.

### 2.3 The one way in

`LawSystem.value(repo, state, law_code, scope_code) -> value`, where `scope_code` is a province for an economy or political law and a unit for a military one. A unit camped by a town (`ArmyGround.camped_by`) reads its town's entry; a unit in the field or on the march reads its own. No system reads `law_in_force` any other way.

### 2.4 Units entering and leaving camp

- A unit that settles into a town's camp (`ArmyGround.settle`, `take_seat`) takes, for each law, the entry with the HIGHER `decree_id` of its own and the town's (a newer decree wins, as a newer courier order does).
- A unit that leaves a camp (a march order taking effect) copies what it read into its own `unit:` entry.
- A town whose kingdom loses it is forgotten (reconcile).

### 2.5 The five old settings

- Their initial decreed value is read from `metrics` (`tax_rate`, `tariff_rate`, `grain_ration`) and the pack-seeded values; every province's in-force entry starts equal to it.
- `metrics["tax_rate"]` and `["tariff_rate"]` become a mirror of the decreed value, for display only. No formula reads them as the rate in force.
- An older save has no law state: `LawSystem.ensure` seeds it from `metrics` at load, as `TownStores.ensure` does. No save is refused.

## 3. `LAW_SET`

An ordinary action with params `{law, value}`.

- **Validation.** The law exists; the value is allowed; the value differs from the decreed one; the law's cooldown has run; the chest can pay the couriers.
- **Cost.** The order's own gold and admin cost from `laws.csv` (`gold_cost`, `admin_cost`) through `order_costs`; plus an ordinary courier's fee for each courier.
- **Couriers.**
  - Economy or political law: one courier to each province the realm holds, ending at its capital burg.
  - Military law: one courier to each town that has a camp of the realm's units, and one to each land unit not camped by a held town (in the field or on the march), the unit's courier aimed at it and re-aimed as it moves.
  - Fleets are not recipients in this version.
  - The ride is `CourierSystem`'s, a new order kind `LAW_SET` carrying `{law, value, decree_id, scope_key}`.
- **Delivery.** When a courier arrives, `law_in_force[scope_key][law]` is written if the courier's `decree_id` is higher than the entry's; else the order is set aside as stale. A courier lost on the road or past the fuse leaves its place on the old value.
- **A newer decree** for the same law does not recall the old couriers; they arrive stale.
- **When.** From the laws screen the order may be given while the clock runs; its couriers ride from the next day's end, as other orders' do.
- **News and letters.** A decree files a letter with its count of couriers. Its last delivery, or its last courier's loss, files a second: "reached X of Y places in N days". The news bar says it once, when all have arrived. The military letters have a keep count of their own (`missive_keep_law`), as the supply letters do.
- **Who proposes.** The council's suggestions and the LLM's parsed actions use `LAW_SET`; the old codes are removed.

## 4. Effects (`data/law_effects.csv`)

A row: `law_code`, `value`, `channel`, `target`, `amount`, `reason`.

### 4.1 Channels

- **Unit channels:** a unit's morale mark (added to the mark its monthly morale drifts toward), a unit's pace (per mille).
- **Realm channels:** church opinion, peasant contentment, legitimacy, unrest, treasury.
- **Flag:** nothing changes; a system reads it through `LawSystem.value`.

### 4.2 How the military laws pay

- A unit channel is applied to each unit by its own in-force value.
- A realm channel is scaled by the SHARE of the army's men under that value: a plunder permit that has reached half the men moves contentment by half. A unit that has not been told follows the default.
- The share is rounded once, and the effect is a whole per-mille amount of the row's amount; every line carries its reason, e.g. "allow plunder: contentment −0.4 (8 units, 36% of the host)".

### 4.3 How the economy and political laws pay

- Tax rate, tariff rate and grain ration are CONTINUOUS: each province's monthly settlement reads its own in-force value; the formulas (`ManorEconomy.line_of`, the unrest pressure) are unchanged.
- Justice severity and church policy are ONE-SHOT: when a province's courier arrives, the realm-wide effect the old action had is applied once, times that province's share of the realm's people. Delivered everywhere, the sum is the old total.

### 4.4 The military laws' first numbers

A first draft, every number in the CSV and the owner's to tune. The value listed first is the default (every toggle's is `off`). A default value has no effect, except quarter's `give` and ransom's `ransom`, whose effects the table gives after "(the default)". "Morale mark" is the unit channel; realm rows are per month at full share.

| Law | Values (default first) | Effect of the non-default value |
|---|---|---|
| Plunder | forbid / allow | allow: morale mark +2, contentment −0.4, church −0.2, legitimacy −0.1; flag |
| Obey command | off / on | on: morale mark +1; flag |
| Protect the church | off / on | on: church +0.3; flag |
| Protect women | off / on | on: contentment +0.3, legitimacy +0.1, morale mark −0.5 |
| No unauthorised "Havoc" | off / on | on: contentment +0.2, unrest −0.1, morale mark −1 |
| Register prisoners | off / on | on: treasury −2 per 1,000 men, legitimacy +0.1; flag |
| Wear badges | off / on | on: morale mark +1, treasury −1 per 1,000 men |
| No private feuds | off / on | on: morale mark +1, unrest −0.1 |
| Quarter | give / refuse | refuse: morale mark +1, legitimacy −0.3; give (the default): legitimacy +0.2, church +0.1; flag |
| Ransom | ransom / execute | execute: legitimacy −0.2; ransom (the default): legitimacy +0.1; flag |
| Truce days | off / on | on: church +0.3, pace −50‰ |
| Inviolable envoys | off / on | on: legitimacy +0.1; flag |


## 5. The laws screen

- LAWS in the bottom bar opens `scenes/screens/laws_screen.tscn`; it works while the clock runs; Esc closes it. The `InfoScreen` LAWS branch is removed.
- Three sub-pages; a table, a row a law. The military page's rows sit under the group titles of `laws.csv`.
- A row: the label; the decreed value; the delivery ("20 / 20 provinces", "14 / 20 provinces · 6 couriers riding · the last in 5 days"; for the military page "8 / 10 camps and 3 / 5 units in the field"); the effects, spelled from `law_effects.csv`; a control (a check box, a drop-down or a stepper); a Decree button.
- Changing the control shows the cost beside it: "20 couriers · 40 gold · order 5 gold · 9 days at most". `LawSystem.preview(repo, state, law, value)` returns `{gold, couriers, max_days, refusal}`; the screen computes nothing. When refused, Decree is greyed and the row says why.
- A click on the delivery opens the list of places that have not been told, each with its days left; a place whose courier was lost is marked and may be decreed again.
- Words come from `data/law_words.csv`; the look is the game's theme kinds, authored in the editor (the look-in-editor rule). The screen reads the state and gives orders through `Game`.

## 6. The twelve military laws and the brainstorm

The owner's eight: plunder, obey command, protect the church, protect women, no unauthorised "Havoc", register prisoners, wear badges, no private feuds. Added: quarter, ransom, truce days, inviolable envoys.

Considered and left for later (in order of fit): no burning of crops in the campaigning season, military discipline (how a deserter is punished — sub-project B's desertion), a formal declaration of war before a campaign, the share of spoils the crown takes, trial by combat instead of feuds. Each is a row in `laws.csv` and `law_effects.csv` and a reader of its flag.

## 7. Testing

- Engine formulas with hand-computed values: the men-share scaling and its single rounding; a one-shot effect's people share and its sum; a newer decree beating an older courier; a unit's inheritance on entering and leaving camp; the cooldown and the cost preview; the courier counts for each kind of law.
- The economy: in the first month after a tax change, provinces reached use the new rate and the rest the old, and the realm's income is the hand-computed sum; unchanged provinces' lines are unchanged.
- A save round-trips the law state bit-exactly; an older save is seeded from `metrics`.
- A guard: no code outside `LawSystem` reads `metrics["tax_rate"]` or `["tariff_rate"]` as the rate in force, and none reads `law_in_force` directly.
- The screen, through real input: switch page, change a control, read the preview, press Decree, see the delivery text change as days run.
- Existing tests that name the five old action codes move to `LAW_SET`.
- Tests name no pack and no kingdom.

## 8. Build order

Each step ends with the full suite green at the expected error count.

1. The tables, `LawSystem`'s state, its reads and `ensure`; the save.
2. `LAW_SET`, the courier's kind and delivery, the preview; the old five actions' removal and their suggestions' and tests' move.
3. The economy per province; the one-shot effects.
4. The military laws' effects, the shares, the units' inheritance in camp and on the march.
5. The laws screen and the letters.
6. The visual review and the guidance files.

## 9. Not in this sub-project

- Plunder, foraging and desertion themselves (B reads the flags).
- Fleets as recipients of laws.
- Interception of couriers (the envoys law keeps only its flag until a courier can be caught).
- Events or random events that a law triggers.
- Showing laws in the war room.
- The deferred chivalry laws of §6.

## 10. Risks

- The economy by province touches the realm economy's cache (its key must carry the provinces' law versions) and a batch of economy tests; it is the widest change.
- The council's suggestions and the model's action codes change with the old actions' removal.
- Many couriers on the map at once after a military decree: the courier layer's cost is watched in the bench.

## 11. Implementation rulings

Where the plan (`docs/superpowers/plans/2026-10-08-laws-tab.md`) and the build settle what the text above leaves open. Each holds over the section it names.

**The plan's rulings.**

- **R1 — values are Strings** in every state map ("on" / "off", a choice's name, a range's plain digits); `LawSystem.number` gives a range's int.
- **R2 — no `admin_cost`** (§2.1): no script read the policy tables' column; a law carries `cost_ops` instead, in the `EventEffects` op grammar (`opinion:steward:-2:re-cutting the tax rolls`), charged when the order executes. `gold_cost` is extra gold on top of the order's row.
- **R3 — `LAW_SET` has one `order_costs.csv` row** (`gold:-1:the chancery drafts the decree`), so invariant 8 holds; the per-law gold and ops are `laws.csv`'s.
- **R4 — the cooldown is per law**: `law_cooldown[law]` is the tick it runs to; the action row's own `cooldown_ticks` is 0.
- **R5 — re-sending** (§3, §5): the decreed value may be decreed again while some places are missing it (`delivery(...).missing`); couriers then ride ONLY to those places, with the SAME `decree_id`.
- **R6 — a courier to a place** has the scope key as his target (`province:<code>`, `town:<code>`): he is never lost for want of a regiment and never re-aimed. A courier to a unit has the unit's code and is re-aimed as it moves.
- **R7 — the three old modes are choices**: grain policy `market | ration | release` (`release` reads as `market` for the court's ration and pays its one-shot on delivery), church policy `none | endow | tithe`, justice severity a range. A one-shot is paid when the value CHANGES to it.
- **R8 — the metrics stand in** for a state with no law state at all (a hand-built test state), so `LawSystem.value` reads `metrics` there.
- **R9 — no save version bump**: the three maps load empty from an older save and `LawSystem.ensure` seeds them.
- **R10 — law couriers are `ordinary`**: no new courier kind (it would need courier art).
- **R11 — `law_effects.csv` has `timing` (`monthly | once`) and `share` (`army | people | unit | flat`)** beside §4's columns: `law_code,value,channel,target,amount,timing,share,reason`. A range law's once-row has a blank value and is paid per point of change.
- **R12 — the state keys** are `law_decree`, `law_in_force` and `law_cooldown`, saved plain.
- **R13 — a province with no entry** (annexed, or retaken) follows the law's default until a courier reaches it.

**The controller's rulings.**

- **P1** — `LawSystem.decree` writes the metric mirror (§2.5) at once, from the first decree.
- **P2** — `LawEffects.summary(repo, law, value)` spells the screen's effects text from the rows.
- **P3** — the two scenes are authored in the editor; an agent that cannot reach it stops and hands back.
- **P4** — landing on `main` waits for the owner's word.

**The build's rulings.**

- **A re-send's cost** (R5): only the order's row and the couriers' fees — no `gold_cost`, no `cost_ops`, no opinion drift (it changes no law) — and it skips the cooldown.
- **Every toggle defaults to its first value**, `off`, as §4.4's table heading says ("Values (default first)"); plunder `forbid`, quarter `give` and ransom `ransom` likewise. A law is a tool the crown imposes: undecreed, only quarter's and ransom's default rows pay.
- **The one-shots are apportioned exactly** (§4.3 and invariant 11, over the plan's one-decimal rounding): each once-row's old realm-wide total is split over the realm's provinces by people, largest remainder (ties to the code that sorts first; with no people anywhere, evenly), in whole units for treasury and grain and tenths otherwise, the sign re-applied. Delivered everywhere, in any order, the provinces pay the old total exactly.
- **The shares are taken at each delivery's moment**: a province's part is re-split on the people as they are when its courier arrives, so a realm that grows, shrinks or loses a province mid-decree drifts from the old total.
- **An event's change of law (`law:<code>:<value>`, `LawSystem.impose`)** is a new decree in force at once everywhere (a range takes a signed step, `+1`, clamped): no courier, no cooldown, and it pays no one-shot.
- **`LawSystem.reconcile`** (each day's end) extends §2.4 to every scope: a province the realm no longer holds forgets its entries (retaken, it reads the default, R13); a town lost or left with no camp is forgotten, the realm's units still camped there keeping what they read (another kingdom's never take a law); the entry of a unit gone, or no longer the realm's land unit, goes with it.
- **A camp no courier reached is told** when every unit camped there reads the decree (or a newer one): a camp formed after the decree of units that carried it in is not "missing".
- **The letters** (§3): ALL of a decree's letters, not only the military ones, are kind `law` and keep their own count (`missive_keep_law`). The reach letter counts the decree's recipients NOW (a province lost meanwhile leaves the count) and the days from the decree's day to the last courier's, both counted (a re-send counts from the first decree). It is filed after the day's ride (`LawSystem.close_rides`), not inside a delivery, since a unit courier's loss and a spent fuse never reach `LawSystem.deliver`; a courier of an older decree closes nothing.
- **The news** (§3): one line as a decree's couriers set out ("The decree on <law> is sent: N couriers.") and one when its last is home ("The decree on <law> is in force everywhere: N of N places in D days.", or "reached X of Y places" when some are missing). Single deliveries and weather delays are not said; a courier set aside, lost or out of time is said once.
- **The military page's group** is a key in `laws.csv`, its title `law_words.csv`'s; refusals are worded from `law_words.csv` too.

**For the owner.**

- **Legitimacy creeps**: undecreed, quarter's `give` (+0.2 legitimacy, +0.1 church a month) and ransom's `ransom` (+0.1 legitimacy) pay from the first day at full share. Against the drift toward 50 that is about +0.2 a month above it, ~+2.4 a year, with no ceiling short of the metric's own cap. Tune those two rows or `legitimacy_drift`.
