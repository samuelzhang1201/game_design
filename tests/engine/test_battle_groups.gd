extends GutTest
## P4.4d1: representative 100-person groups and their saved whole-metre positions.
## Hand-computed: spacing 50 m, depth 40 m (data/battle/balance.csv).
const SuiteData := preload("res://tests/suite_data.gd")
const Geometry := preload("res://scripts/engine/battle_group_geometry.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.open_country(SuiteData.repo())
	# Synthetic historical rows below are 40 m apart; keep their physical fixture explicit.
	for row: Dictionary in repo.unit_footprints.values():
		row.radius_m = 20
		row.pitch_m = 80
	var state := SuiteData.campaign(repo, 9445)
	var codes := state.regiments.keys()
	codes.sort()
	var a := String(codes[0])
	var enemy := String(state.foes.keys()[0])
	state.regiments[a]["x_m"] = 1000
	state.regiments[a]["y_m"] = 2000
	state.foes[enemy]["x_m"] = 1000
	state.foes[enemy]["y_m"] = 4000
	var battle := {"id": 9445, "att": [a], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 1000, "place_y_m": 3000, "actions": {}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	return {"repo": repo, "state": state, "a": a, "enemy": enemy, "battle": battle}

func _counts(groups: Array) -> Array:
	return groups.map(func(x: Dictionary) -> int: return int(x.count))

func test_configured_hundred_fit_counts() -> void:
	var repo := SuiteData.repo()
	assert_eq(int(repo.bal("battle_group_size")), 100)
	assert_eq(BattleGroups.counts(101, int(repo.bal("battle_group_size"))), [100, 1] as Array[int])
	assert_eq(BattleGroups.counts(1000, int(repo.bal("battle_group_size"))).size(), 10)

func test_production_rows_fit_installed_piece_discs() -> void:
	var f := _fixture()
	f.repo = SuiteData.open_country(f.repo)
	f.repo.unit_footprints = SuiteData.repo().unit_footprints.duplicate(true)
	for code: String in [f.a, f.enemy]:
		Personnel.replace(f.repo, f.state, code, 1000)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var rows: Array = f.battle.groups[f.a]
	var footprint := Geometry.footprint(f.repo, ArmySystem.regiment(f.repo, f.a, f.state))
	assert_true(footprint.ok)
	assert_eq(rows.size(), 10, "Every hundred fit people keeps its full-scale figure")
	for i: int in rows.size():
		for j: int in range(i):
			var separation := Geometry.pair([rows[i].x_m, rows[i].y_m], footprint.radius_m,
				[rows[j].x_m, rows[j].y_m], footprint.radius_m, 0)
			assert_true(separation.ok and not separation.overlap, "Installed discs must not overlap")

func test_withdrawal_waits_for_actual_rows_when_anchors_are_far_apart() -> void:
	var f := _fixture()
	for code: String in [f.a, f.enemy]: Personnel.replace(f.repo, f.state, code, 100)
	var reach := int(f.repo.bal("battle_contact_km") * 1000)
	f.state.foes[f.enemy].y_m = 2000 + reach + 1000
	assert_true(BattleGroups.refresh(f.repo, f.state, f.battle))
	# A clear saved row can lie far from its anchor after deployment or a flank.
	f.battle.groups[f.enemy][0].x_m = 1000
	f.battle.groups[f.enemy][0].y_m = 2100
	assert_true(BattleGroups.placement(f.repo, f.state, f.battle).ok)
	f.state.regiments[f.a].battle_retreat = true
	f.battle.actions = {"att": {"kind": "retreat"}, "def": {"kind": "hold"}}
	var people: Dictionary = f.state.military_cohorts.duplicate(true)
	var rng: Dictionary = f.state.rng.to_dict()
	var out := BattleSystem.step_battle(f.repo, f.state, int(f.battle.id))
	assert_eq(out.status, "complete")
	assert_true(f.a in f.battle.att, "An anchor outside encounter range cannot leave its actual contacting rows behind")
	assert_eq(f.state.battles.size(), 1)
	assert_eq(f.state.military_cohorts, people)
	assert_eq(f.state.rng.to_dict(), rng, "A quiet withdrawal creates no combat roll")


func test_bent_march_synchronizes_rows_along_its_admitted_legs() -> void:
	for saved: bool in [false, true]:
		var f := _fixture()
		f.repo = SuiteData.no_clearance(f.repo)
		for code: String in [f.a, f.enemy]: Personnel.replace(f.repo, f.state, code, 100)
		f.state.foes[f.enemy].x_m = 1050
		f.state.foes[f.enemy].y_m = 2050
		assert_true(BattleGroups.refresh(f.repo, f.state, f.battle))
		var entry: Dictionary = f.state.regiments[f.a]
		entry.order = ArmySystem.ORDER_MARCH
		entry.battle_retreat = true
		entry.camp_state = {"phase": CampSystem.NONE}
		entry.erase("departure")
		entry.dest_x_m = 1100
		entry.dest_y_m = 2100
		entry.route_m = [[1100, 2000], [1100, 2100]]
		# The two 100 m legs pass 50 m from the enemy; their diagonal chord hits it.
		f.battle.groups[f.a][0].path_m = [[1000, 2000]]
		var before := SaveLoad.state_hash(f.state)
		ArmySystem.march_ahead(f.repo, f.state, f.a, entry.duplicate(true))
		assert_eq(SaveLoad.state_hash(f.state), before, "Forecast must not publish row motion")
		if saved:
			ArmySystem.march_day_saved(f.repo, f.state, 1, 0, {f.a: entry.duplicate(true)}, {f.a: 200})
		else:
			ArmySystem.march_day(f.repo, f.state, 1, 0, true, [f.a], {f.a: 200})
		assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(1100, 2100))
		assert_eq(f.battle.group_anchor_m[f.a], [1100, 2100])
		assert_eq(f.battle.groups[f.a][0].x_m, 1100)
		assert_eq(f.battle.groups[f.a][0].y_m, 2100)
		assert_eq(f.battle.groups[f.a][0].path_m, [[1100, 2100]])
		assert_true(BattleGroups.placement(f.repo, f.state, f.battle).ok)
		var settled := SaveLoad.state_hash(f.state)
		BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.a)
		assert_eq(SaveLoad.state_hash(f.state), settled, "Repeated synchronization is inert")


func test_rejected_rigid_step_preserves_anchor_rows_paths_and_slots() -> void:
	var f := _fixture()
	f.repo = SuiteData.open_country(f.repo)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var before := SaveLoad.state_hash(f.state)
	var own: Dictionary = f.battle.groups[f.a][0]
	var enemy: Dictionary = f.battle.groups[f.enemy][0]
	BattleGroups.translate(f.repo, f.state, f.battle, f.a,
		Vector2i(int(enemy.x_m) - int(own.x_m), int(enemy.y_m) - int(own.y_m)))
	assert_eq(SaveLoad.state_hash(f.state), before, "A step through occupied enemy discs is wholly rejected")

func test_march_validates_the_complete_path_before_publishing_its_entry() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var entry: Dictionary = f.state.regiments[f.a]
	entry.order = ArmySystem.ORDER_MARCH
	entry.battle_retreat = true
	entry.camp_state = {"phase": CampSystem.NONE}
	entry.erase("departure")
	var own: Dictionary = f.battle.groups[f.a][0]
	var enemy: Dictionary = f.battle.groups[f.enemy][0]
	entry.dest_x_m = int(entry.x_m) + int(enemy.x_m) - int(own.x_m)
	entry.dest_y_m = int(entry.y_m) + int(enemy.y_m) - int(own.y_m)
	var before := SaveLoad.state_hash(f.state)
	var travelled: Array = []
	assert_false(ArmySystem._march_one(f.repo, f.state, f.a, entry, f.state.absolute_day(),
		{}, [], 1, 0, 10000, 10000, travelled))
	assert_eq(SaveLoad.state_hash(f.state), before)
	assert_eq(travelled, [], "Rejected motion cannot earn pursuit metres")
	var origin := Vector2i(int(entry.x_m), int(entry.y_m))
	entry.dest_x_m = origin.x - 100
	entry.dest_y_m = origin.y
	assert_true(ArmySystem._march_one(f.repo, f.state, f.a, entry, f.state.absolute_day(), {}, [], 1, 0, 100, 100))
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), origin - Vector2i(100, 0))
	assert_true(BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.a))
	assert_eq(f.battle.group_anchor_m[f.a], [entry.x_m, entry.y_m])

func test_installed_partial_rows_and_adjacent_friendly_unit_remain_disjoint() -> void:
	var f := _fixture()
	f.repo.unit_footprints = SuiteData.repo().unit_footprints.duplicate(true)
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var friend := String(codes[1])
	f.state.regiments[friend].x_m = 21000
	f.state.regiments[friend].y_m = 2000
	f.battle.att.append(friend)
	for people: int in [901, 1, 0]:
		for code: String in [f.a, f.enemy, friend]: Personnel.replace(f.repo, f.state, code, people)
		assert_true(BattleGroups.refresh(f.repo, f.state, f.battle))
		assert_true(BattleGroups.placement(f.repo, f.state, f.battle).ok)
		for code: String in [f.a, f.enemy, friend]:
			var rows: Array = f.battle.groups[code]
			assert_eq(rows.size(), BattleGroups.counts(people, 100).size())
			var total := 0
			for row: Dictionary in rows: total += int(row.count)
			assert_eq(total, people)
			if people == 0:
				assert_eq(BattleGroups.deployment(f.repo, f.state, f.battle)[code], BattleSystem._at_m(f.repo, f.state, code))

func test_blocked_recovery_preserves_people_receipt_and_slots_until_admission() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 200)
	Personnel.move(f.repo, f.state, f.a, "fit", "wounded", 100)
	Personnel.replace(f.repo, f.state, f.enemy, 100)
	f.state.regiments[f.a].facing_deg = 90
	f.state.foes[f.enemy].y_m = 1920  # Occupies the next80m rear slot, without overlapping the existing front.
	assert_true(BattleGroups.refresh(f.repo, f.state, f.battle))
	for code: String in f.state.military_rosters: f.state.conduct_marks["recovery:" + code] = f.state.tick
	f.state.conduct_marks.erase("recovery:" + f.a)
	var frozen := SaveLoad.state_hash(f.state)
	ArmySystem._recover_month(f.repo, f.state)
	assert_eq(SaveLoad.state_hash(f.state), frozen, "A failed physical admission cannot publish recovery people or a consumed receipt")
	assert_true(BattleGroups.translate(f.repo, f.state, f.battle, f.enemy, Vector2i(-1000, 0)))
	ArmySystem._recover_month(f.repo, f.state)
	assert_gt(ArmySystem.fit_count(f.repo, f.state, f.a), 100)
	assert_eq(f.battle.groups[f.a].size(), 2)
	var recovered := SaveLoad.state_hash(f.state)
	ArmySystem._recover_month(f.repo, f.state)
	assert_eq(SaveLoad.state_hash(f.state), recovered, "A successful physical recovery is paid and consumed once")

func test_counts_table() -> void:
	assert_eq(BattleGroups.counts(0, 100), [] as Array[int])
	assert_eq(BattleGroups.counts(1, 100), [1] as Array[int])
	assert_eq(BattleGroups.counts(49, 100), [49] as Array[int])
	assert_eq(BattleGroups.counts(50, 100), [50] as Array[int])
	assert_eq(BattleGroups.counts(51, 100), [51] as Array[int])
	assert_eq(BattleGroups.counts(800, 100).size(), 8)
	assert_eq(BattleGroups.counts(1000, 100).size(), 10)
	assert_eq(BattleGroups.counts(10000, 100).size(), 100)

func test_layout_line_rotated() -> void:
	var repo := SuiteData.repo()
	# facing 0 (+x): across = +y, back = -x; slots x -1,0,1 at 50 m
	assert_eq(BattleGroups.layout(repo, "line", 3, Vector2i(0, 0), 0),
		[Vector2i(0, -50), Vector2i(0, 0), Vector2i(0, 50)] as Array[Vector2i])
	# facing 90 (+y): across = -x
	assert_eq(BattleGroups.layout(repo, "line", 3, Vector2i(0, 0), 90),
		[Vector2i(50, 0), Vector2i(0, 0), Vector2i(-50, 0)] as Array[Vector2i])
	assert_eq(BattleGroups.layout(repo, "line", 1, Vector2i(10, 20), 0), [Vector2i(10, 20)] as Array[Vector2i])

func test_double_rank_depth_is_behind_the_front() -> void:
	var repo := SuiteData.repo()
	# double_rank 3 groups, facing 0: slots (-0.5,0), (-0.5,1), (0.5,0) -> (0,-25), (-40,-25), (0,25)
	assert_eq(BattleGroups.layout(repo, "double_rank", 3, Vector2i(0, 0), 0),
		[Vector2i(0, -25), Vector2i(-40, -25), Vector2i(0, 25)] as Array[Vector2i])

func test_refresh_groups_follow_fit_count() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 240)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var g: Array = f.battle.groups[f.a]
	assert_eq(_counts(g), [100, 100, 40])
	assert_eq(g.map(func(x: Dictionary) -> String: return String(x.role)), ["front", "reserve", "front"])
	assert_eq(int(f.battle.group_facing[f.a]), 90)
	assert_eq(int(f.battle.group_facing[f.enemy]), 270)
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 60)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_counts(f.battle.groups[f.a]), [100, 80])

func test_save_roundtrip_and_old_battle_migrates() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var back: Dictionary = JSON.parse_string(JSON.stringify(f.battle))
	assert_eq(int(back.group_facing[f.a]), 90)
	assert_eq(back.groups[f.a].size(), f.battle.groups[f.a].size())
	assert_eq(int(back.groups[f.a][0].x_m), int(f.battle.groups[f.a][0].x_m))
	f.battle.erase("groups")
	f.battle.erase("group_facing")
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_true(f.battle.groups.has(f.a))

func test_departed_unit_loses_its_entry() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.battle.def.clear()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_false(f.battle.groups.has(f.enemy))

func _points(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> Vector2i: return Vector2i(int(row.x_m), int(row.y_m)))

func test_refresh_keeps_physical_rows() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 100)
	f.battle["groups"] = {f.a: [
		{"count": 50, "role": "front", "x_m": 200, "y_m": 200, "path_m": [[210, 200]]},
		{"count": 50, "role": "reserve", "x_m": 160, "y_m": 200}]}
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(200, 200), Vector2i(160, 200)])
	assert_eq(f.battle.groups[f.a][0].get("path_m", []), [[210, 200]])
	assert_eq(f.battle.groups[f.a].map(func(row: Dictionary) -> int: return int(row.get("slot", -1))), [0, 1])
	var frozen := JSON.stringify(f.state.to_dict())
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(JSON.stringify(f.state.to_dict()), frozen)
	f.state.regiments[f.a]["facing_deg"] = 180
	f.battle.formations.att.current = "line"
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(200, 200), Vector2i(160, 200)])

func test_count_boundary_keeps_surviving_positions() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 240)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var before := _points(f.battle.groups[f.a])
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 39)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_counts(f.battle.groups[f.a]), [100, 100, 1])
	assert_eq(_points(f.battle.groups[f.a]), before)
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 1)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_counts(f.battle.groups[f.a]), [100, 100])
	assert_eq(_points(f.battle.groups[f.a]), before.slice(0, 2))
	Personnel.replace(f.repo, f.state, f.a, 301)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]).slice(0, 2), before.slice(0, 2))
	assert_eq(f.battle.groups[f.a].map(func(row: Dictionary) -> int: return int(row.get("slot", -1))), [0, 1, 3, 4])

func test_pending_round_freezes_reconciliation() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var before: Dictionary = f.battle.duplicate(true)
	f.battle["pending_round"] = {"roll": 17}
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 1)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(f.battle.groups, before.groups)

func test_translate_and_follow_anchor_apply_exactly_once() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 100)
	f.state.regiments[f.a].x_m = 200
	f.state.regiments[f.a].y_m = 200
	f.battle["groups"] = {f.a: [
		{"count": 50, "role": "front", "x_m": 200, "y_m": 200, "path_m": [[210, 200]]},
		{"count": 50, "role": "reserve", "x_m": 160, "y_m": 200}]}
	BattleGroups.refresh(f.repo, f.state, f.battle)
	BattleGroups.translate(f.repo, f.state, f.battle, f.a, Vector2i(30, 40))
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(230, 240))
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(230, 240), Vector2i(190, 240)])
	assert_eq(f.battle.groups[f.a][0].path_m, [[240, 240]])
	var before := JSON.stringify(f.state.to_dict())
	BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.a)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(JSON.stringify(f.state.to_dict()), before)
	f.state.regiments[f.a].x_m = 260
	f.state.regiments[f.a].y_m = 280
	BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.a)
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(260, 280), Vector2i(220, 280)])
	assert_eq(f.battle.group_anchor_m[f.a], [260, 280])

func test_retired_slots_stay_retired_across_json_and_battles() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 240)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 40)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var battle: Dictionary = loaded.battles[0]
	battle.att.clear()
	BattleGroups.refresh(f.repo, loaded, battle)
	battle.att.append(f.a)
	BattleGroups.refresh(f.repo, loaded, battle)
	assert_eq(battle.groups[f.a].map(func(row: Dictionary) -> int: return int(row.slot)), [3, 4])
	var next_battle := {"id": 9446, "att": [f.a], "def": [f.enemy], "actions": {}}
	loaded.battles = [next_battle]
	BattleGroups.refresh(f.repo, loaded, next_battle)
	assert_eq(next_battle.groups[f.a].map(func(row: Dictionary) -> int: return int(row.slot)), [5, 6])
	var twin := GameState.from_dict(JSON.parse_string(JSON.stringify(loaded.to_dict())))
	BattleGroups.refresh(f.repo, twin, twin.battles[0])
	assert_eq(SaveLoad.state_hash(twin), SaveLoad.state_hash(loaded))

func test_new_member_seeds_at_arrival_and_exact_people_are_conserved() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var ally := String(codes[1])
	f.state.regiments[ally].x_m = 9000
	f.state.regiments[ally].y_m = 8000
	Personnel.replace(f.repo, f.state, ally, 1)
	f.battle.att.append(ally)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[ally]), [Vector2i(9000, 8000)])
	for people: int in [0, 1, 49, 50, 51, 800, 1000]:
		Personnel.replace(f.repo, f.state, ally, people)
		BattleGroups.refresh(f.repo, f.state, f.battle)
		assert_eq(_counts(f.battle.groups[ally]), BattleGroups.counts(people, 100))
	assert_eq(BattleGroups.counts(10000, 100).size(), 100, "pure count stress does not enlist an oversized unit")

func test_legacy_rows_cannot_gain_contact_through_closed_ground() -> void:
	var f := _fixture()
	f.repo.balance["army_march_grid_px"] = 1.0
	f.repo.balance["battle_group_contact_m"] = 30
	Personnel.replace(f.repo, f.state, f.a, 50)
	Personnel.replace(f.repo, f.state, f.enemy, 50)
	f.battle["groups"] = {
		f.a: [{"count": 50, "role": "front", "x_m": 5, "y_m": 5}],
		f.enemy: [{"count": 50, "role": "front", "x_m": 25, "y_m": 5}]}
	MarchPath.use(f.repo, MarchPath.build(f.repo, 3, 1, 10, PackedByteArray([0, 255, 0])))
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var before: Array = f.battle.groups[f.a].duplicate(true)
	assert_eq(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.a), Vector2i(0, 50))
	assert_eq(f.battle.groups[f.a], before, "invalid legacy positions remain saved facts")
	MarchPath.use(f.repo, MarchPath.build(f.repo, 3, 1, 10, PackedByteArray([0, 0, 0])))
	assert_eq(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.a), Vector2i(50, 50))
	MarchPath.forget()


func test_physical_metrics_use_heterogeneous_radii_and_exact_boundaries() -> void:
	# Radii 3 + 7, reach 5: occupied tangent at 10, reach inclusive at 15.
	for distance: int in [9, 10, 11, 14, 15, 16]:
		var result: Dictionary = Geometry.pair([0, 0], 3, [distance, 0], 7, 5)
		assert_true(result.ok)
		assert_eq(result.overlap, distance < 10)
		assert_eq(result.in_reach, distance <= 15)
	assert_true(Geometry.pair([0, 0], 3, [9, 12], 7, 5).in_reach, "9²+12²=15²")
	assert_false(Geometry.pair([0, 0], 3, [10, 12], 7, 5).in_reach)


func test_physical_blockers_include_tangency_and_endpoint_overlap() -> void:
	assert_true(Geometry.segment_disc([0, 0], [10, 0], [5, 3], 3).blocked)
	assert_false(Geometry.segment_disc([0, 0], [10, 0], [5, 4], 3).blocked)
	assert_true(Geometry.segment_disc([0, 0], [10, 0], [-2, 0], 3).blocked)
	assert_false(Geometry.segment_disc([0, 0], [10, 0], [-3, 0], 3).blocked,
		"endpoint-only tangency leaves the open shot clear")
	assert_true(Geometry.segment_disc([0, 0], [10, 0], [12, 0], 3).blocked)
	assert_false(Geometry.segment_disc([0, 0], [10, 0], [13, 0], 3).blocked)
	assert_true(Geometry.segment_disc([0, 0], [0, 0], [0, 0], 1).blocked)
	assert_false(Geometry.segment_disc([0, 0], [0, 0], [1, 0], 1).blocked)
	# Diagonal: cross²=100, radius²*length²=200, so the radius-one disc blocks.
	assert_true(Geometry.segment_disc([0, 0], [10, 10], [4, 5], 1).blocked)


func test_physical_envelope_and_rigid_step_are_pure_and_bounded() -> void:
	var rows: Array = [{"x_m": -4, "y_m": 2, "count": 100, "path_m": [[-4, 2]]},
		{"x_m": 6, "y_m": 12, "count": 1}]
	var blockers: Array = [{"x_m": 0, "y_m": 5, "radius_m": 1}]
	var before := JSON.stringify([rows, blockers])
	assert_eq(Geometry.envelope(rows, 3), {"ok": true, "min_x_m": -7,
		"min_y_m": -1, "max_x_m": 9, "max_y_m": 15, "width_m": 16, "depth_m": 16})
	var moved: Dictionary = Geometry.rigid_step(rows, 3, [3, 4], 5, [])
	assert_true(moved.ok)
	assert_true(moved.allowed, "3²+4²=5², inclusive step bound")
	assert_eq(moved.envelope.min_x_m, -4)
	assert_eq(moved.envelope.max_y_m, 19)
	assert_false(Geometry.rigid_step(rows, 3, [3, 5], 5, []).allowed)
	assert_false(Geometry.rigid_step(rows, 3, [8, 0], 8, blockers).allowed,
		"swept radius 3+1 blocks even when endpoints are clear")
	assert_true(Geometry.rigid_step(rows, 3, [3, 4], 5, []).allowed)
	assert_eq(JSON.stringify([rows, blockers]), before)
	var repo := SuiteData.repo()
	var fixture := _fixture()
	var regiment: Dictionary = fixture.state.regiments[fixture.a]
	regiment.is_royal = "1"
	assert_eq(Geometry.footprint(repo, regiment).radius_m, 749)
	var footprint: Dictionary = Geometry.footprint(repo, {"is_naval": "1"})
	assert_false(footprint.ok, "missing footprint never silently shrinks a piece")


func test_physical_metrics_reject_invalid_and_overflowing_inputs() -> void:
	var maximum: int = 9223372036854775807
	assert_false(Geometry.pair([maximum, 0], 1, [-1, 0], 1, 0).ok)
	assert_false(Geometry.pair([0, 0], maximum, [0, 0], 1, 0).ok)
	assert_false(Geometry.pair([0, 0], 1, [3037000500, 0], 1, 0).ok)
	assert_false(Geometry.pair([0, 0], -1, [0, 0], 1, 0).ok)
	assert_false(Geometry.pair([0.5, 0], 1, [0, 0], 1, 0).ok)
	assert_false(Geometry.pair([0, 0], 1, [0, 0], 1, -1).ok)
	assert_false(Geometry.segment_disc([0, 0], [100000, 100000], [0, 100000], 1).ok,
		"cross-product square overflow is rejected before multiplication")
	assert_false(Geometry.envelope([{"x_m": maximum, "y_m": 0}], 1).ok)
	assert_false(Geometry.envelope([], 1).ok)
	assert_false(Geometry.rigid_step([{"x_m": maximum, "y_m": 0}], 0, [1, 0], 1, []).ok)


func test_physical_installed_footprints_and_large_world_coordinates() -> void:
	var repo := SuiteData.repo()
	var infantry: Dictionary = repo.unit_footprints.infantry
	var archers: Dictionary = repo.unit_footprints.archers
	# 927 + 932 + 30 = 1889. World coordinates exceed Vector2i's int32 range.
	for distance: int in [1888, 1889, 1890]:
		var result := Geometry.pair([5000000000, -5000000000], infantry.radius_m,
			[5000000000 + distance, -5000000000], archers.radius_m, 30)
		assert_true(result.ok)
		assert_eq(result.in_reach, distance <= 1889)
	assert_true(Geometry.pair([0, 0], 0, [3037000499, 0], 0, 0).ok)
	assert_false(Geometry.pair([0, 0], 0, [2147483648, 2147483648], 0, 0).ok,
		"both squares fit individually, their sum does not")
	assert_true(Geometry.pair([1.0, 2.0], 3, [11.0, 2.0], 7, 0).in_reach,
		"whole JSON numbers are accepted without truncating fractions")


func test_physical_rounded_formation_envelope_uses_actual_rows() -> void:
	var repo := SuiteData.repo()
	var pitch: int = repo.unit_footprints.infantry.pitch_m
	var radius: int = repo.unit_footprints.infantry.radius_m
	# Existing three-slot line at 45 degrees: +/-3708/sqrt(2) rounds to +/-2622.
	var rows: Array = []
	for slot: Vector2 in BattleFormation.slots("line", 3):
		var offset := (Vector2(-1, 1).normalized() * slot.x * pitch).round()
		rows.append({"x_m": int(offset.x), "y_m": int(offset.y)})
	assert_eq(rows, [{"x_m": 2622, "y_m": -2622}, {"x_m": 0, "y_m": 0},
		{"x_m": -2622, "y_m": 2622}])
	var bounds := Geometry.envelope(rows, radius)
	assert_eq(bounds.width_m, 7098, "5244 centre extent + 1854 diameter")
	assert_eq(bounds.depth_m, 7098)
	assert_true(Geometry.rigid_step(rows, radius, [0, 0], 0, []).allowed)
	var packed: Array = [{"x_m": 0, "y_m": 0}, {"x_m": 1853, "y_m": 0}]
	assert_false(Geometry.rigid_step(packed, radius, [0, 0], 0, []).allowed)
	packed[1].x_m = 1854
	assert_true(Geometry.rigid_step(packed, radius, [0, 0], 0, []).allowed,
		"occupied tangency is legal")
	assert_true(Geometry.rigid_step([{ "x_m": 0, "y_m": 0}], 3, [10, 0], 10,
		[{"x_m": 5, "y_m": 4, "radius_m": 1}]).allowed,
		"swept occupied tangency is legal, unlike shot tangency")


func test_physical_queries_reject_malformed_rows_and_preserve_repository() -> void:
	var repo := SuiteData.repo()
	var before := JSON.stringify(repo.unit_footprints)
	var regiment := {"is_royal": "1"}
	var footprint := Geometry.footprint(repo, regiment)
	footprint.radius_m = 1
	assert_eq(JSON.stringify(repo.unit_footprints), before, "returned footprint is detached")
	assert_eq(regiment, {"is_royal": "1"})
	repo.unit_footprints.royal.pitch_m = 1
	assert_false(Geometry.footprint(repo, regiment).ok)
	assert_false(Geometry.envelope([{"x_m": 1}], 3).ok)
	assert_false(Geometry.envelope([{"x_m": 1.5, "y_m": 0}], 3).ok)
	assert_false(Geometry.rigid_step([{ "x_m": 0, "y_m": 0}], 3, [0, 0], 0,
		[{"x_m": 5, "y_m": 4, "radius_m": -1}]).ok)
	assert_false(Geometry.segment_disc([0, 0], [10, 0], [5, 0], -1).ok)
