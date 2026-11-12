extends GutTest
## D-FIRE (CF06 cases 3-4): the candidate direct-fire query on admitted body worlds.
## Every footprint is shrunk to radius 20 so blockers and edges fit between real bodies;
## reach (battle_ranged_reach_m = 400) and contact (100) are SURFACE gaps beyond 20 + 20,
## the production `clear_shot` geometry since #248. The cone is set to 250 permille.

const R := 20

func after_each() -> void:
	MarchPath.forget()

func _small(repo: DataRepository) -> void:
	for row: Dictionary in repo.unit_footprints.values():
		row.radius_m = R
		row.pitch_m = 80
		row.width_m = (int(row.files) - 1) * 80 + 2 * R
		row.depth_m = (int(row.ranks) - 1) * 80 + 2 * R
		if row.has("locomotion_certificate"): row.locomotion_certificate.radius_m = R
	repo.balance.battle_ranged_cone_permille = 250
	assert_eq(int(repo.bal("battle_ranged_reach_m")), 400)
	assert_eq(int(repo.bal("battle_group_contact_m")), 100)

## Crown archer row (100) at (10000,10000) facing +x; the enemy's one row `gap` m beyond
## both surfaces; `other` 40 km away.
func _field(gap: int = 300, own_fit: int = 100) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_contact.gd").new()
	var f: Dictionary = helper.call("_fixture", own_fit, 100)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	_small(f.repo)
	for arm: String in f.repo.world_table("military", "unit_types"):
		f.state.army_roster[f.unit][arm] = "0"
	f.state.army_roster[f.unit].archers = "100"
	assert_eq(BattleRanged.share(f.repo, f.state, f.unit), 1000)
	var battle: Dictionary = f.state.battles[0]
	battle.actions = {"att": {"kind": "attack", "reason": "Received advance plan"}, "def": {"kind": "hold", "reason": "Hold"}}
	battle.group_facing = {f.unit: 0, f.enemy: 180, f.other: 180}
	_put(f, f.unit, 0, 10000, 10000)
	_put(f, f.enemy, 0, 10000 + 2 * R + gap, 10000)
	_put(f, f.other, 0, 10000, 50000)
	return f

func _put(f: Dictionary, code: String, slot: int, x: int, y: int, battle: int = 0) -> void:
	var row: Dictionary = f.state.battles[battle].groups[code][slot]
	row.x_m = x
	row.y_m = y
	if slot == 0:
		var entry := UnitBodies._entry(f.state, code)
		entry.x_m = x
		entry.y_m = y

func _boundary(state: GameState) -> Dictionary:
	return {"version": 1, "kind": "safe", "abs_day": str(state.absolute_day()), "sequence": "0"}

func _fire(f: Dictionary, unit: String = "", target: String = "", battle_id: int = 8, opposing: int = 0) -> Dictionary:
	var before := BodyMotion._hash(f.state.to_dict())
	var result: Dictionary = BattleRanged.counts_candidate(f.repo, f.state, battle_id, f.unit if unit == "" else unit,
		target, opposing, _boundary(f.state))
	assert_eq(result.keys().size(), 9, "the closed fire result")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before, "the query changes nothing")
	if result.status == "complete":
		assert_eq(result.error, "")
		assert_false(String(result.reason).is_empty())
	return result

func test_reach_contact_cone_and_facing_edges() -> void:
	# At gap 100 the archer holds in close defence; it defends against the ATTACKING enemy
	# (two holders never hurt each other, the original active-round rule).
	for row: Array in [[399, 100, 0], [400, 100, 0], [401, 0, 0], [100, 0, 100], [101, 100, 0]]:
		var f := _field(row[0])
		if row[0] == 100: f.state.battles[0].actions.def = {"kind": "attack", "reason": "Received advance plan"}
		var result := _fire(f)
		assert_eq(result.status, "complete", result.reason)
		assert_eq(result.firing, row[1], "gap %d firing" % row[0])
		assert_eq(result.melee, row[2], "gap %d close defence" % row[0])
		if row[1] > 0:
			assert_eq(result.pairs.size(), 1)
			assert_eq(result.pairs[0].kind, "fire")
			assert_eq(result.pairs[0].target_unit, f.enemy)
	# Cone 250: forward 400, lateral 100 is the edge (100*1000 == 400*250), 101 is beyond.
	# Centre 412.3 m: gap 372, inside reach.
	for lateral: Array in [[100, 100], [101, 0]]:
		var f := _field()
		_put(f, f.enemy, 0, 10400, 10000 + lateral[0])
		assert_eq(_fire(f).firing, lateral[1], "lateral %d" % lateral[0])
	var behind := _field()
	_put(behind, behind.enemy, 0, 10000 - 2 * R - 300, 10000)
	assert_eq(_fire(behind).firing, 0, "facing away never fires")

func test_moving_the_target_from_400_to_401_stops_fire_at_once() -> void:
	var f := _field(400)
	assert_eq(_fire(f).firing, 100)
	_put(f, f.enemy, 0, 10000 + 2 * R + 401, 10000)
	assert_eq(_fire(f).firing, 0)

func test_own_front_blocks_at_interior_tangency_and_one_metre_clears() -> void:
	# Shooter row 0 at (10000,10000), enemy at (10340,10000). Own row 1 (1 person) at
	# (10170,10020) is tangent to that open segment and blocks row 0; at 10021 it clears.
	# Row 1 has its own clear shot either way, so firing is 1 vs 1 + 100.
	for row: Array in [[10020, 1], [10021, 101]]:
		var f := _field(300, 101)
		_put(f, f.unit, 1, 10170, row[0])
		assert_eq(_fire(f).firing, row[1], "row 1 at y %d" % row[0])

func test_negative_rules_retreat_reserve_designated_sight_protection_terrain() -> void:
	var f := _field()
	assert_eq(_fire(f).firing, 100, "baseline")
	f.state.battles[0].actions.att = {"kind": "retreat", "reason": "Received withdrawal"}
	assert_eq(_fire(f).firing, 0, "a received retreat stays retreat")
	f = _field()
	f.state.battles[0].reserves = {f.unit: {"reason": "Held back"}}
	assert_eq(_fire(f).firing, 0, "an uncommitted reserve does not fire")
	f = _field()
	assert_eq(_fire(f, "", f.other).firing, 0, "the remote target is out of reach")
	assert_eq(_fire(f, "", f.enemy).firing, 100, "a named target in reach")
	f = _field()
	f.repo.balance.player_sight_km = 0.2
	var blind := _fire(f)
	assert_eq(blind.firing, 0, "beyond local sight (340 m > 200 m)")
	assert_true(String(blind.reason).contains("sight"), blind.reason)
	f = _field()
	var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	f.state.battles[0].parley = {"battle_id": 8, "agreed": {"ceasefire": term}, "parties": {"att": [f.unit], "def": [f.enemy]}}
	var protected := _fire(f)
	assert_eq(protected.firing, 0, "a protected target is not fired upon")
	assert_true(String(protected.reason).contains("agreement"), protected.reason)
	# 50 m cells: the cell at x 10150..10200, y 10000..10050 lies on the open segment.
	f = _field()
	f.grid.cell_m = 50
	f.grid.cols = 400
	f.grid.rows = 1200
	f.grid.closed.resize(400 * 1200)
	f.grid.water.resize(400 * 1200)
	assert_eq(_fire(f).firing, 100, "open 50 m ground")
	f.grid.closed[200 * 400 + 203] = 1
	assert_eq(_fire(f).firing, 0, "terrain on the segment blocks")

func test_designated_task_restricts_fire_to_its_target() -> void:
	var f := _field()
	# A second target in reach and cone: lateral 60 * 1000 <= forward 340 * 250; 60 m from the enemy.
	_put(f, f.other, 0, 10340, 10060)
	assert_eq(_fire(f).firing, 100)
	assert_eq(_fire(f).pairs.size(), 2)
	UnitBodies._entry(f.state, f.unit).supplies = 1000000
	f.state.unit_tasks = {f.unit: {"current_id": "t1", "received_sequence": 1, "orders": {"t1": {
		"sequence": 1, "status": "received", "reason": "Received", "history": [],
		"request": {"id": "t1", "unit": f.unit, "battle_id": 8, "task": "advance", "formation": "",
			"target_unit": f.other, "source": "player", "issuer": "", "max_route_m": 0, "region": ""}}}}}
	var told := _fire(f)
	assert_eq(told.pairs.size(), 1)
	assert_eq(told.pairs[0].target_unit, f.other)
	assert_true(String(told.reason).contains("designated"), told.reason)

## Cross-field: archer C (field 9) fires at A (field 8). B (field 8, C's ally) blocks; a
## ceasefire recorded in either field between C and A bars fire; positive fire merges.
func _cross() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_merge.gd").new()
	var f: Dictionary = helper.call("_fixture", "touch", true)
	helper.free()
	_small(f.repo)
	f.state.battles[1].actions.att = {"kind": "attack", "reason": "Received advance plan"}
	f.state.battles[1].group_facing[f.c] = 0
	var far := {f.a: 100000, f.b: 120000, f.c: 140000, f.d: 160000}
	for i: int in [0, 1]:
		for code: String in f.state.battles[i].groups:
			for row: Dictionary in f.state.battles[i].groups[code]:
				if int(row.slot) > 0:
					row.y_m = far[code]
					row.path_m = []
	_put(f, f.c, 0, 10000, 10000, 1)
	_put(f, f.d, 0, 10000, 30000, 1)
	_put(f, f.a, 0, 10340, 10000, 0)
	_put(f, f.b, 0, 10170, 10021, 0)
	for i: int in [0, 1]:
		for code: String in f.state.battles[i].group_anchor_m:
			var first: Dictionary = f.state.battles[i].groups[code][0]
			f.state.battles[i].group_anchor_m[code] = [first.x_m, first.y_m]
	BodyBattle._seal_private(f.repo, f.state)
	return f

func _cross_fire(f: Dictionary) -> Dictionary:
	var before := BodyMotion._hash(f.state.to_dict())
	var result: Dictionary = BattleRanged.counts_candidate(f.repo, f.state, 9, f.c, f.a, 8, BodyBattleMotion._boundary(f.state))
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	return result

func test_both_field_allies_block_and_both_field_terms_bind() -> void:
	var f := _cross()
	var clear := _cross_fire(f)
	assert_eq(clear.status, "complete", clear.reason)
	assert_eq(clear.firing, 100, "C's row 0 fires across the fronts")
	_put(f, f.b, 0, 10170, 10020, 0)
	BodyBattle._seal_private(f.repo, f.state)
	assert_eq(_cross_fire(f).firing, 0, "B of the other field is a measured blocker")
	var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	for field: int in [0, 1]:
		var g := _cross()
		g.state.battles[field].parley.agreed = {"ceasefire": term}
		g.state.battles[field].parley.parties = {"att": [g.a], "def": [g.c]} if field == 0 else {"att": [g.c], "def": [g.a]}
		BodyBattle._seal_private(g.repo, g.state)
		assert_eq(_cross_fire(g).firing, 0, "a C<->A ceasefire in field %d binds" % (8 + field))

func test_positive_cross_field_fire_merges_the_fields() -> void:
	var f := _cross()
	var boundary := BodyBattleMotion._boundary(f.state)
	var plan := BodyBattle.plan_candidate(f.repo, f.state, {"kind": "merge", "first_id": "8", "second_id": "9"}, boundary)
	assert_eq(plan.status, "complete", plan.reason)
	if plan.status != "complete": return
	var merged := BodyBattle.commit_candidate(f.repo, f.state, plan.plan, boundary)
	assert_eq(merged.status, "complete", merged.reason)
	if merged.candidate != null:
		assert_eq(merged.candidate.battles.size(), 1)
		assert_eq(merged.candidate.day_resolution.journal.battles.back().kind, "merge")
	# With B tangent again, no fire, so no merge.
	_put(f, f.b, 0, 10170, 10020, 0)
	BodyBattle._seal_private(f.repo, f.state)
	var blocked := BodyBattle.plan_candidate(f.repo, f.state, {"kind": "merge", "first_id": "8", "second_id": "9"}, BodyBattleMotion._boundary(f.state))
	assert_eq(blocked.status, "deferred")
	assert_eq(blocked.reason, "No lawful physical cross-field contact or direct fire")

func test_contact_with_any_opponent_suppresses_fire_at_the_named_target() -> void:
	# `other` touches the shooter (surface gap 50, behind it); the enemy is a clear target.
	var f := _field()
	_put(f, f.other, 0, 10000 - 2 * R - 50, 10000)
	var named := _fire(f, "", f.enemy)
	assert_eq(named.firing, 0, "melee with a non-target foe still suppresses fire")
	assert_eq(named.melee, 0, "and is not melee against the named target")
	var all := _fire(f)
	assert_eq(all.firing, 0)
	assert_eq(all.melee, 0, "the archer holds in close defence and `other` holds: no melee")
	f.state.battles[0].actions.def = {"kind": "attack", "reason": "Received advance plan"}
	var defended := _fire(f)
	assert_eq(defended.firing, 0)
	assert_eq(defended.melee, 100, "self-defence against the attacking touching foe")
	assert_eq(defended.pairs.size(), 1)
	assert_eq(defended.pairs[0].target_unit, f.other)
	assert_eq(defended.pairs[0].kind, "melee")

func test_contact_on_the_queried_field_with_a_non_target_still_suppresses_fire() -> void:
	# Cross-field: crown D moves into field 8 beside A and touches C (surface gap 50, behind C).
	# C (field 9) is queried against A only; D is a hostile non-target of the queried field.
	var f := _cross()
	var nine: Dictionary = f.state.battles[1]
	var eight: Dictionary = f.state.battles[0]
	nine.def.erase(f.d)
	eight.att.append(f.d)
	for key: String in ["groups", "group_anchor_m", "group_facing"]:
		eight[key][f.d] = nine[key][f.d]
		nine[key].erase(f.d)
	_put(f, f.d, 0, 10000 - 2 * R - 50, 10000, 0)
	eight.group_anchor_m[f.d] = [10000 - 2 * R - 50, 10000]
	BodyBattle._seal_private(f.repo, f.state)
	var result := _cross_fire(f)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.firing, 0, "touching D of the queried field stops fire at A")

func test_touching_a_protected_opponent_still_suppresses_fire() -> void:
	# `other` touches the shooter but is protected by a ceasefire; the enemy is a clear target.
	var f := _field()
	_put(f, f.other, 0, 10000 - 2 * R - 50, 10000)
	var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	f.state.battles[0].parley = {"battle_id": 8, "agreed": {"ceasefire": term}, "parties": {"att": [f.unit], "def": [f.other]}}
	var result := _fire(f, "", f.enemy)
	assert_eq(result.firing, 0, "physical contact, not permission, suppresses fire")
	assert_eq(result.melee, 0, "and no lawful melee arises against the protected foe")
	assert_true(String(result.reason).contains("fire suppressed"), result.reason)

func test_real_radius_bodies_fire_across_an_open_surface_gap() -> void:
	# Production radii (archers 932, cavalry 804) and reach 400 measured as a surface gap (#248):
	# centres 1736 + 300 apart fire; + 401 do not.
	for row: Array in [[300, 100], [401, 0]]:
		var helper: GutTest = load("res://tests/engine/test_body_battle_contact.gd").new()
		var f: Dictionary = helper.call("_fixture", 100, 100)
		helper.free()
		for arm: String in f.repo.world_table("military", "unit_types"):
			f.state.army_roster[f.unit][arm] = "0"
		f.state.army_roster[f.unit].archers = "100"
		assert_eq(BattleGroupGeometry.footprint(f.repo, f.state.army_roster[f.unit]).radius_m, 932)
		f.state.battles[0].actions = {"att": {"kind": "attack", "reason": "Advance"}, "def": {"kind": "hold", "reason": "Hold"}}
		f.state.battles[0].group_facing = {f.unit: 0, f.enemy: 180, f.other: 180}
		_put(f, f.unit, 0, 10000, 10000)
		_put(f, f.enemy, 0, 10000 + 932 + 804 + row[0], 10000)
		var shot := _fire(f, "", f.enemy)
		assert_eq(shot.firing, row[1], "real-radius gap %d: %s" % [row[0], shot.reason])

func test_malformed_requests_error() -> void:
	var f := _field()
	for args: Array in [[f.unit, "nobody", 8, 0], [f.unit, f.unit, 8, 0], ["nobody", "", 8, 0], [f.unit, "", 12, 0], [f.unit, "", 8, 12]]:
		var result: Dictionary = BattleRanged.counts_candidate(f.repo, f.state, args[2], args[0], args[1], args[3], _boundary(f.state))
		assert_eq(result.status, "error", str(args))
		assert_eq(result.firing, 0)
		assert_eq(result.pairs, [])
	f.state.battles[0].groups[f.unit][0].x_m = 9007199254740993
	assert_eq(_fire(f).status, "error", "raw overflow")
	assert_eq(BattleRanged.counts_candidate(null, f.state, 8, f.unit, "", 0, _boundary(f.state)).status, "error")
