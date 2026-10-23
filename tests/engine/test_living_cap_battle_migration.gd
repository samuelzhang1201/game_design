extends "res://tests/engine/test_military_reorganization.gd"

func test_active_battle_keeps_saved_points_and_singular_intent() -> void:
	state.military_cohorts.common.fit = 1000
	state.military_cohorts.common.wounded = 0
	var rows: Array = []
	for i: int in 20:
		rows.append({"count": 50, "role": "front", "x_m": 100 + i, "y_m": 200, "slot": i})
	rows.append({"count": 1, "role": "reserve", "x_m": 999, "y_m": 333, "slot": 20})
	state.battles = [{"id": 7, "att": [original], "def": ["foe"], "groups": {original: rows},
		"group_facing": {original: 37}, "pending_round": {}, "rounds": 3,
		"unit_formations": {original: {"current": "line"}}, "reports": [{"unit": original, "loss": 9}]}]
	state.battle_aliases = {"6": 7}
	state.unit_tasks = {original: {"current_id": "charge", "received": {"charge": {"status": "received", "request": {"task": "charge"}}}}}
	state.regiments[original].charge = {"phase": "impact", "target": "foe"}
	state.king_state.follow_unit = original
	var tasks := state.unit_tasks.duplicate(true)
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	var battle: Dictionary = state.battles[0]
	assert_eq(battle.att, children)
	assert_eq(battle.reports, [{"unit": original, "loss": 9}])
	assert_eq(state.battle_aliases, {"6": 7})
	assert_eq(state.unit_tasks, tasks)
	assert_eq(state.king_state.follow_unit, original)
	assert_false(state.regiments[children[1]].has("charge"))
	var counts := [0, 0]
	for i: int in children.size():
		var code: String = children[i]
		assert_eq(battle.group_facing[code], 37)
		for group: Dictionary in battle.groups[code]:
			counts[i] += int(group.count)
			assert_true(rows.any(func(saved: Dictionary) -> bool: return saved.x_m == group.x_m and saved.y_m == group.y_m))
	assert_eq(counts, [501, 500])
	assert_eq(battle.groups[original][-1].x_m, battle.groups[children[1]][0].x_m, "Boundary row splits in place")
	var hash_before := SaveLoad.state_hash(state)
	assert_eq(_reconcile().status, "complete")
	assert_eq(SaveLoad.state_hash(state), hash_before)

func test_wounded_only_battle_child_has_no_groups() -> void:
	state.battles = [{"id": 7, "att": [original], "def": [], "groups": {original: [{"count": 1, "x_m": 9, "y_m": 8, "role": "front"}]}, "group_facing": {original: 90}}]
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	assert_eq(state.battles[0].groups[children[1]], [])

func test_paid_assembling_reservations_partition_without_receipt_or_gear_replay() -> void:
	state.military_cohorts.common.wounded = 899
	state.military_cohorts.common.initial -= 101
	_add("paid", 101, 0)
	state.military_cohorts.paid.stage = "assembling"
	var request := {"request_id": "paid", "mode": "reinforce", "unit_code": original, "arm": "cavalry",
		"total": 101, "noble_permille": 0, "source_province": state.military_cohorts.paid.source_province,
		"source_population_field": "rural_population", "assembly_town": state.army_roster[original].camp_town,
		"commander_id": state.military_rosters[original].commander_id}
	state.recruitment_projects = {"paid": {"unit_code": original, "status": "assembling", "cohort_ids": ["paid"],
		"equipment": {"cavalry": 5}, "quote": {"needs_commander": false}, "request": request.duplicate(true), "result": {"gold": 99}}}
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	var totals := [0, 0]
	for i: int in children.size():
		for id: String in state.military_rosters[children[i]].cohort_ids:
			var cohort: Dictionary = state.military_cohorts[id]
			totals[i] += int(cohort.fit) + int(cohort.wounded)
	assert_eq(totals, [501, 500])
	var project: Dictionary = state.recruitment_projects.paid
	assert_eq(project.unit_codes, children)
	assert_eq(project.request, request)
	assert_eq(project.result, {"gold": 99})
	var gear := 0
	for allocation: Dictionary in project.equipment_by_unit.values(): gear += int(allocation.cavalry)
	assert_eq(gear, 5)
	var before := state.to_dict()
	assert_eq(_reconcile().status, "complete")
	assert_eq(state.to_dict(), before)

func test_bad_group_fit_total_refuses_entire_candidate() -> void:
	state.battles = [{"id": 7, "att": [original], "def": [], "groups": {original: [{"count": 99, "x_m": 9, "y_m": 8}]}}]
	var before := SaveLoad.state_hash(state)
	assert_eq(_reconcile().status, "error")
	assert_eq(SaveLoad.state_hash(state), before)

func test_new_child_without_a_task_holds_under_an_attacking_side() -> void:
	state.military_cohorts.common.fit = 1000
	state.military_cohorts.common.wounded = 0
	state.battles = [{"id": 7, "att": [original], "def": [], "actions": {"att": {"kind": "attack"}},
		"groups": {original: [{"count": 1001, "x_m": 9, "y_m": 8}]}}]
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	assert_true(BattleTaskSystem.current(state, children[1]).is_empty())
	assert_eq(BattleTaskSystem.combat_action(repo, state, state.battles[0], children[1]).kind, "hold", "New detachment receives no inherited side attack")
	assert_eq(BattleTaskSystem.combat_action(repo, state, state.battles[0], original).kind, "attack")
	var events := state.military_events.duplicate(true)
	var child: String = children[1]
	state.unit_tasks[child] = {"current_id": "received-advance", "orders": {"received-advance": {
		"status": "received", "request": {"id": "received-advance", "battle_id": 7, "task": "advance", "target_unit": "", "source": "player"}}}}
	assert_eq(BattleTaskSystem.combat_action(repo, state, state.battles[0], child).kind, "attack", "A genuine received task overrides migration hold")
	state.battles[0].actions.att.kind = "retreat"
	assert_eq(BattleTaskSystem.combat_action(repo, state, state.battles[0], child).kind, "retreat", "Rout and actual withdrawal still take precedence")
	assert_eq(state.military_events, events)


func test_unrelated_idle_units_migrate_while_a_frozen_round_waits() -> void:
	var frozen_unit: Dictionary = state.army_roster[original].duplicate(true)
	frozen_unit.regiment_code = "frozen"
	state.army_roster.frozen = frozen_unit
	state.military_rosters.frozen = {"commander_id": "", "cohort_ids": ["frozen"]}
	var source: Dictionary = state.military_cohorts.common.duplicate(true)
	source.id = "frozen"
	source.unit_code = "frozen"
	source.fit = 1001
	source.wounded = 0
	source.captured_current = 0
	source.dead = 0
	source.released = 0
	source.initial = 1001
	state.military_cohorts.frozen = source
	var round_input := {"att": ["frozen"], "roll": 99, "costs": {"frozen": 17}}
	state.battles = [{"id": 7, "att": ["frozen"], "def": [], "pending_round": round_input.duplicate(true),
		"groups": {"frozen": [{"count": 1001, "x_m": 123, "y_m": 456}]}}]
	assert_eq(_reconcile().status, "deferred")
	assert_eq(_children().size(), 2)
	assert_eq(state.battles[0].pending_round, round_input)
	assert_eq(Roster.living(state, "frozen"), 1001)
	assert_eq(int(state.military_migration.get("living_cap_version", 0)), 0)
	var before := SaveLoad.state_hash(state)
	assert_eq(_reconcile().status, "deferred")
	assert_eq(SaveLoad.state_hash(state), before)
	state.battles[0].erase("pending_round")
	assert_eq(_reconcile().status, "complete")
	assert_eq(state.military_migration.living_cap_version, 2)
	assert_eq(state.battles[0].att, ["frozen", "frozen:living:v2:1"])

func test_migration_seeds_child_anchor_and_preserves_retired_slot_counter() -> void:
	state.military_cohorts.common.fit = 1000
	state.military_cohorts.common.wounded = 0
	var at := BattleSystem._at_m(repo, state, original)
	state.regiments[original].group_next_slot = 90
	state.battles = [{"id": 7, "att": [original], "def": [], "groups": {original: [
		{"count": 501, "x_m": at.x, "y_m": at.y, "slot": 11, "role": "front"},
		{"count": 500, "x_m": at.x + 1, "y_m": at.y, "slot": 29, "role": "reserve"}]},
		"group_anchor_m": {original: [at.x, at.y]}, "group_facing": {original: 37}}]
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	var child: String = children[1]
	assert_eq(state.battles[0].get("group_anchor_m", {}).get(child, []), [at.x, at.y])
	assert_eq(state.regiments[child].group_next_slot, 90)
	var before := SaveLoad.state_hash(state)
	BattleGroups.follow_anchor(repo, state, state.battles[0], child)
	assert_eq(SaveLoad.state_hash(state), before, "Zero movement after migration must not initialize or translate rows again")

func test_migration_hold_follows_saved_battle_alias_without_a_task() -> void:
	state.military_cohorts.common.fit = 1000
	state.military_cohorts.common.wounded = 0
	state.battles = [{"id": 7, "att": [original], "def": [], "actions": {"att": {"kind": "attack"}},
		"groups": {original: [{"count": 1001, "x_m": 9, "y_m": 8}]}}]
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	# A merged survivor retains unit state and aliases, not arbitrary source battle fields.
	state.battles = [{"id": 1, "att": state.battles[0].att, "def": [], "actions": {"att": {"kind": "attack"}}}]
	state.battle_aliases["7"] = 1
	assert_true(BattleTaskSystem.current(state, children[1]).is_empty())
	assert_eq(BattleTaskSystem.combat_action(repo, state, state.battles[0], children[1]).kind, "hold")

func test_no_task_child_uses_defensive_strength_under_attacking_side() -> void:
	state.military_cohorts.common.fit = 1000
	state.military_cohorts.common.wounded = 0
	state.battles = [{"id": 7, "att": [original], "def": [], "actions": {"att": {"kind": "attack"}},
		"groups": {original: [{"count": 1001, "x_m": 9, "y_m": 8, "role": "front"}]}}]
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	var child: String = children[1]
	var strength := BattleSystem.unit_strength(repo, state, child, Callable(), true)
	assert_false(strength.has("error"), str(strength))
	assert_true(strength.factors.any(func(f: Dictionary) -> bool: return f.source == "stance:defence"))
	assert_true(strength.factors.any(func(f: Dictionary) -> bool: return f.source == "camp:defence"))
	var defence := BattleSystem.unit_strength(repo, state, child, Callable(), false)
	assert_eq(strength, defence, "A held child's strength cannot inherit its side's attack flag")
	assert_eq(BattleSystem.side_power(repo, state, [child], Callable(), true), defence.power)
	assert_true(BattleTaskSystem.current(state, child).is_empty(), "No synthetic task is needed for defence")

func test_partitioned_rows_survive_refresh_and_json_without_movement() -> void:
	state.military_cohorts.common.fit = 1000
	state.military_cohorts.common.wounded = 0
	var rows: Array = []
	for i: int in 20:
		rows.append({"count": 50, "role": "front", "x_m": 100 + i, "y_m": 200, "slot": i})
	rows.append({"count": 1, "role": "reserve", "x_m": 999, "y_m": 333, "slot": 20})
	state.battles = [{"id": 7, "att": [original], "def": [], "groups": {original: rows}}]
	assert_eq(_reconcile().status, "complete")
	var before: Dictionary = state.battles[0].groups.duplicate(true)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	BattleGroups.refresh(repo, state, state.battles[0])
	assert_eq(state.battles[0].groups, before, "A refresh cannot relocate the boundary group's people")
	BattleGroups.refresh(repo, state, state.battles[0])
	assert_eq(state.battles[0].groups, before, "Repeated refresh preserves partial rows and retired slots")
	var child: String = _children()[1]
	assert_false(MilitaryRoster.transfer_units(repo, state, "boundary-wound",
		[{"unit_code": child, "from": "fit", "to": "wounded", "count": 1}], "Boundary continuity wound").has("error"))
	BattleGroups.refresh(repo, state, state.battles[0])
	var survivors: Array = before[child].slice(0, 10)
	assert_eq(state.battles[0].groups[child], survivors, "Only the one-person tail retires")
	assert_false(MilitaryRoster.transfer_units(repo, state, "boundary-recover",
		[{"unit_code": child, "from": "wounded", "to": "fit", "count": 1}], "Boundary continuity recovery").has("error"))
	BattleGroups.refresh(repo, state, state.battles[0])
	assert_eq(state.battles[0].groups[child].slice(0, 10), survivors)
	assert_eq(state.battles[0].groups[child][-1].count, 1)
	assert_eq(state.battles[0].groups[child][-1].slot, 21, "Recovery cannot reuse retired slot20")
