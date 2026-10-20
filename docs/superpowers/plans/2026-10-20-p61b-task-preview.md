# P6.1b — the area-task preview (free, reveals nothing hidden)

Scope: slice b of P6.1 (split in `2026-10-20-p61a-task-coverage.md`). A pure
`ArmyTasks.preview` answers "what would this circle order do" for the WAR ROOM
before anything is paid or sent. It reads only what the ordering realm knows.
No saved state, no action, no courier, no movement (c issues and delivers).

Approved design: spec `2026-10-16-battle-system-design.md` §13.1 (select land
units → circle → kind → preview → confirm; preview shows units, commander, area
or town, ETA on known routes, supply, cost and law limits; drawing and previewing
are free, the order pays; local within the king's range, remote pays a courier;
fleets take no land area task), §13.3 (only known, reachable, lawful targets;
forbidden categories not selectable), §13.4 (destroy names an object kind; only
actually discovered objects; warn of cutting own routes within what is known),
§13.5 (siege only when a KNOWN town lies in the circle; several → choose one);
P6 plan Review Focus 1 (`test_task_preview_does_not_reveal_hidden_state`) and
its preview bullet.

## Contract

- `ArmyTasks.preview(repo, state, realm: String, task: Dictionary) ->
  Dictionary` (new `scripts/engine/army_tasks.gd`, pure, never mutates state).
  `task` = `{kind, unit_codes: Array, center_x_m, center_y_m, radius_m,
  known_target_id: String = "", encounter_policy: String = ""}`.
- Refusals (`{ok: false, reason}`, words from a CSV row each — implementer:
  `data/army/task_words.csv` key,text, or reuse an existing words table): empty
  unit list; a unit not the realm's land unit (fleet, foe, captured, no fit man);
  unknown kind; radius ≤ 0 or above `task_max_radius_m` (balance, first draft
  20 000); centre off the map; an encounter policy the kind does not allow
  (`task_kinds.csv`); a `siege` with no known town in the circle or a
  `known_target_id` that is not a known town in it; a `destroy` without a target
  kind.
- Success `{ok: true, kind, units: [{code, commander_id, eta_days}],
  towns: [known town ids in the circle, sorted], target, cells: (count of
  `TaskCoverage.cells_in_circle`), cost: {gold, courier: bool}, encounter_policy
  (the kind's default when blank), law_limits: [reason strings]}`:
  - ETA per unit: `CourierSystem.arrival_days`-style day count for a march to
    the circle centre (implementer: reuse the existing order-ETA path, never a
    new pace formula).
  - cost: the `order_costs.csv` row for a new `ARMY_TASK` action (add the row;
    the action itself is slice c) and whether a courier is needed (any unit
    beyond `king_command_radius_m` of the king).
  - towns: only towns the realm KNOWS (implementer: find the existing knowledge
    gate — the realm's own and seen/reported towns via `Intel` / `Sighting` /
    the WAR ROOM sheets; record which one), never every town in the pack.
  - law_limits: the received laws that forbid the kind's actions for these units
    (e.g. a raid under a law forbidding it), each a reason string.
- Determinism: same knowledge ⇒ same preview, whatever the hidden enemies or
  hidden towns are.

## Implementer rulings pending the owner

1. The knowledge gate used for towns and targets.
2. `task_max_radius_m` default.
3. The `ARMY_TASK` order cost row values (first draft = the BATTLE_TASK row's).

## Hand checks (tests/engine/test_army_tasks.gd)

- `test_task_preview_does_not_reveal_hidden_state`: two SuiteData states with
  the same known information but a hidden foe moved / a hidden (unknown) town in
  the circle: the two previews are equal (`==`), and the unknown town is not
  listed.
- Empty units / a fleet / radius 0 / radius over max → `ok false` with the
  CSV reason.
- Siege with two known towns in the circle and no target → refused naming the
  need to choose; with a valid target → ok, target set.
- Search with blank policy → `keep_distance`; search `approach` ok; raid
  `keep_distance` refused.
- A unit inside the king's range → `courier false`; beyond → `true`.
- `preview` leaves `state.to_dict()` unchanged.

## Steps

1. Tests red. 2. Code + CSV rows green. 3. One paragraph in the "Area tasks"
section of `scripts/engine/guide/regiments.md`. 4. `--fast` green; one PR.

## Implementer rulings recorded (P6.1b)

1. Knowledge gate: `Intel.level(burg subj) != "basic"` (held / own-realm provinces) OR `Intel.estimate(burg, "town_people")` non-empty (a filed report). The same gate the town card uses; no new truth source.
2. `task_max_radius_m` = 20000 (balance.csv).
3. `ARMY_TASK` row = the BATTLE_TASK row (gold -1, always 1). Cost gold = row gold + `CourierSystem.fee_gold(ordinary)` when a courier is needed.
4. Courier needed = any unit for which `KingSystem.can_command` is false.
5. `destroy` carries its object kind in `known_target_id` (nonblank required; the kind list arrives with slice c/d).
6. Law limits only list (preview stays ok): raid + received `plunder` = forbid. Other kinds have none yet (table `LAW_LIMITS` in code; ponytail: move to data when a second law appears).
7. Refusal words in new `data/army/task_words.csv` (key,text,notes), loaded as `repo.task_words`.
8. Unit validity: own realm, not naval, not a foe, in `state.regiments`, not captured, `fit_count > 0`.

- Reviewer: the law-limit mapping moved from a code const into `task_kinds.csv` `law_limits` (`law:value:words_key` tokens joined by `|`), so design values stay in data.
