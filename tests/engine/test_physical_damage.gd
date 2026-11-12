extends GutTest
## D-QUERY (CF06 cases 1-2): physical defensive exposure and the candidate melee adapter.
## Field 8: the crown unit (infantry, radius 927, att) against `enemy` and `other`
## (cavalry, radius 804, def); contact allowance battle_group_contact_m = 100.

func after_each() -> void:
	MarchPath.forget()

func _fixture(own_fit: int = 1000, enemy_fit: int = 100) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_contact.gd").new()
	var f: Dictionary = helper.call("_fixture", own_fit, enemy_fit)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	return f

func _boundary(state: GameState) -> Dictionary:
	return {"version": 1, "kind": "safe", "abs_day": str(state.absolute_day()), "sequence": "0"}

func _melee(f: Dictionary, unit: String, enemies: Array) -> Dictionary:
	var before := BodyMotion._hash(f.state.to_dict())
	var result: Dictionary = BattleGroups.melee_counts(f.repo, f.state, f.state.battles[0], unit, enemies)
	assert_eq(result.keys().size(), 3, "the original three-field contract")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before, "the adapter changes nothing")
	return result

func _exposure(f: Dictionary, unit: String, enemies: Array) -> Dictionary:
	var before := BodyMotion._hash(f.state.to_dict())
	var sorted := enemies.duplicate()
	sorted.sort()
	var result: Dictionary = BodyBattleContact.exposure_candidate(f.repo, f.state, 8, unit, sorted, _boundary(f.state))
	assert_eq(result.keys().size(), 8, "the closed CF05 query result")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before, "exposure changes nothing")
	return result

func _put(f: Dictionary, code: String, slot: int, x: int, y: int) -> void:
	var row: Dictionary = f.state.battles[0].groups[code][slot]
	row.x_m = x
	row.y_m = y

func test_one_touching_row_is_the_only_engaged_personnel() -> void:
	var f := _fixture()
	# Crown rows stand at x = 10000 + slot*10000; the enemy's one row 1731 m east of row 0.
	var hit := _melee(f, f.unit, [f.enemy])
	assert_eq(hit.engaged, 100, "one 100-person row in lawful surface contact")
	assert_eq(hit.fit, 1000)
	assert_eq(hit.fit - hit.engaged, 900, "the nine remote rows contribute nothing")
	assert_false(String(hit.reason).begins_with("Rejected"))
	assert_eq(_exposure(f, f.unit, [f.enemy]).engaged, 100)
	_put(f, f.enemy, 0, 11731, 30000)
	var none := _melee(f, f.unit, [f.enemy])
	assert_eq(none.engaged, 0, "no contact is a legitimate zero, not a reserve share")
	assert_eq(none.fit, 1000)
	assert_eq(_exposure(f, f.unit, [f.enemy]).engaged, 0)

func test_final_one_person_row_counts_once_against_two_targets() -> void:
	var f := _fixture(101)
	# Row 1 (1 person) at x=20000 touches the enemy at 21731 and `other` at 18269.
	_put(f, f.enemy, 0, 21731, 10000)
	_put(f, f.other, 0, 18269, 10000)
	var both := _melee(f, f.unit, [f.other, f.enemy])
	assert_eq(both.engaged, 1, "one person is never two")
	assert_eq(both.fit, 101)
	var exposed := _exposure(f, f.unit, [f.enemy, f.other])
	assert_eq(exposed.engaged, 1)
	assert_eq(exposed.pairs.size(), 2)

func test_protected_outgoing_keeps_defensive_exposure_and_nonparty_scope() -> void:
	var f := _fixture()
	# B = the crown unit; A = enemy (touches B's row 0) under an A<->B ceasefire;
	# C = other (touches B's row 1) is no party to it.
	_put(f, f.other, 0, 21731, 10000)
	assert_eq(_melee(f, f.enemy, [f.unit]).engaged, 100, "baseline: before the ceasefire A attacks B")
	var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	f.state.battles[0].parley = {"battle_id": 8, "agreed": {"ceasefire": term}, "parties": {"att": [f.unit], "def": [f.enemy]}}
	var barred := _melee(f, f.enemy, [f.unit])
	assert_eq(barred.engaged, 0, "A may not attack B")
	assert_true(String(barred.reason).contains("ceasefire"), barred.reason)
	assert_eq(_exposure(f, f.enemy, [f.unit]).engaged, 100, "A is still physically exposed to B")
	assert_eq(_melee(f, f.unit, [f.enemy]).engaged, 0, "B may not attack A either")
	assert_eq(_melee(f, f.other, [f.unit]).engaged, 100, "C is no party: its attack on B stays lawful")
	assert_eq(_melee(f, f.unit, [f.other]).engaged, 100)
	var exposed := _exposure(f, f.unit, [f.enemy, f.other])
	assert_eq(exposed.engaged, 200, "filtering A's pair cannot erase B's exposure to C (rows 0 and 1)")
	assert_eq(exposed.pairs.map(func(p: Dictionary) -> String: return p.target_unit), [f.enemy, f.other] if f.enemy < f.other else [f.other, f.enemy])
	var lawful: Dictionary = BodyBattleContact.query_candidate(f.repo, f.state, 8, f.unit, [f.enemy, f.other] if f.enemy < f.other else [f.other, f.enemy], _boundary(f.state))
	assert_eq(lawful.engaged, 100, "the lawful query keeps only the C pair")
	assert_true(String(lawful.reason).contains("ceasefire"))

func test_infantry_surface_gap_edges() -> void:
	# Two infantry radii 927 + allowance 100: centre gaps 1854 and 1954 touch, 1955 does not,
	# and 1853 is an invalid overlap, not a stronger contact.
	for gap: int in [1854, 1954, 1955, 1853]:
		var f := _fixture()
		for arm: String in f.repo.world_table("military", "unit_types"):
			f.state.army_roster[f.enemy][arm] = "0"
		f.state.army_roster[f.enemy].infantry = "100"
		assert_eq(BattleGroupGeometry.footprint(f.repo, f.state.army_roster[f.enemy]).radius_m, 927)
		_put(f, f.enemy, 0, 10000 + gap, 10000)
		var result := _melee(f, f.unit, [f.enemy])
		if gap == 1853:
			assert_eq(result.engaged, -1, "overlap is a rejection")
			assert_eq(result.fit, -1)
			assert_true(String(result.reason).begins_with("Rejected"), result.reason)
			assert_eq(_exposure(f, f.unit, [f.enemy]).status, "error")
		else:
			assert_eq(result.engaged, 100 if gap <= 1954 else 0, str(gap))
			assert_eq(result.fit, 1000)
			assert_eq(_exposure(f, f.unit, [f.enemy]).engaged, 100 if gap <= 1954 else 0, str(gap))

func test_wall_water_and_raw_overflow() -> void:
	for blocker: String in ["closed", "water"]:
		var f := _fixture(100)
		# 50 m cells: the crown row at (2000,2000), the enemy 1831 m east; the cell at
		# x 2950..3000, y 2000..2050 lies in the 100 m surface gap, outside both discs.
		_put(f, f.unit, 0, 2000, 2000)
		_put(f, f.enemy, 0, 3831, 2000)
		_put(f, f.other, 0, 8000, 8000)
		f.grid.cell_m = 50
		f.grid.cols = 200
		f.grid.rows = 200
		f.grid.closed.resize(40000)
		f.grid.water.resize(40000)
		assert_eq(_melee(f, f.unit, [f.enemy]).engaged, 100, "open ground touches")
		if blocker == "closed": f.grid.closed[40 * 200 + 59] = 1
		else: f.grid.water[40 * 200 + 59] = 1
		var blocked := _melee(f, f.unit, [f.enemy])
		assert_eq(blocked.engaged, 0, blocker)
		assert_false(String(blocked.reason).begins_with("Rejected"))
		assert_eq(_exposure(f, f.unit, [f.enemy]).engaged, 0, blocker + " also blocks exposure")
	var f := _fixture()
	f.state.battles[0].groups[f.unit][0].x_m = 9007199254740993
	var raw := _melee(f, f.unit, [f.enemy])
	assert_eq(raw.engaged, -1)
	assert_true(String(raw.reason).begins_with("Rejected"))
	assert_eq(_exposure(f, f.unit, [f.enemy]).status, "error")
	assert_eq(_exposure(_fixture(), f.unit, [f.enemy, f.enemy]).status, "error", "duplicate enemies")

func test_rejections_are_never_a_zero() -> void:
	var f := _fixture()
	for enemies: Array in [[f.enemy, f.enemy], [f.unit], ["nobody"]]:
		var bad := _melee(f, f.unit, enemies)
		assert_eq(bad.engaged, -1, str(enemies))
		assert_eq(bad.fit, -1)
	var missing: Dictionary = BattleGroups.melee_counts(f.repo, f.state, {"id": 99}, f.unit, [f.enemy])
	assert_eq(missing.engaged, -1)
	# A day of another protocol has no admitted candidate boundary.
	f.state.day_resolution = DayResolution.begin(f.state.day, false, f.state.absolute_day())
	var other_day := _melee(f, f.unit, [f.enemy])
	assert_eq(other_day.engaged, -1)
	assert_eq(other_day.reason, "Rejected: candidate melee needs an admitted battle boundary")
	assert_eq(BattleGroups.melee_counts(null, f.state, f.state.battles[0], f.unit, [f.enemy]).engaged, -1)
	# A malformed saved battle day is a rejection, not a runtime error.
	f.state.day_resolution = {"body_battle": {"stage": "round"}}
	assert_eq(_melee(f, f.unit, [f.enemy]).engaged, -1)
