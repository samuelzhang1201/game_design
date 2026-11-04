class_name BattleCharge
extends RefCounted
## Momentum belongs to the unit's saved movement, never to a disposable group index.

static func mounted_share(repo: DataRepository, state: GameState, code: String) -> int:
	var row := ArmySystem.regiment(repo, code, state)
	var total := 0
	var mounted := 0
	for arm: String in repo.world_table("military", "unit_types"):
		var definition: Dictionary = repo.world_table("military", "unit_types")[arm]
		var people := int(row.get(arm, 0)) * int(definition["crew"])
		total += people
		if definition["type"] == "mounted":
			mounted += people
	@warning_ignore("integer_division")
	return mounted * 1000 / total if total > 0 else 0


static func target(repo: DataRepository, state: GameState, battle: Dictionary, code: String) -> String:
	var entry := BattleSystem._stored(state, code)
	if not BattleSystem._can_fight(repo, state, code) or bool(entry.get("captured", false)) \
			or ArmyGround.seated_in(repo, state, code) != "":
		return ""
	var reg := ArmySystem.regiment(repo, code, state)
	var bite := ArmySystem.day_bite(ArmySystem.supply_use(repo, reg, state), state.day)
	if int(entry.get("supplies", 0)) < bite + BattleSystem._attack_supply(repo, bite):
		return ""
	var action := BattleSystem.unit_action(repo, state, battle, code)
	if action["kind"] != "attack" or action.has("pursuit_target") \
			or mounted_share(repo, state, code) < int(repo.bal("battle_context_arm_threshold_permille")):
		return ""
	var task := BattleTaskSystem.current(state, code)
	if action["task_id"] != "" and task.get("request", {}).get("task", "") == "flank":
		return ""
	var side := BattleRules.side_of(battle, code)
	var foes: Array = (battle["def" if side == "att" else "att"] as Array).duplicate()
	foes.sort()
	var chosen := ""
	var best := INF
	var designated := String(task.get("request", {}).get("target_unit", "")) if action["task_id"] != "" else ""
	for foe: String in foes:
		if designated != "" and foe != designated:
			continue
		if not BattleSystem._can_fight(repo, state, foe) or bool(BattleSystem._stored(state, foe).get("captured", false)) \
				or not "charge" in BattleRules.legal_actions(repo, state, int(battle["id"]), side, code, foe):
			continue
		var distance := Vector2(BattleSystem._at_m(repo, state, code) - BattleSystem._at_m(repo, state, foe)).length_squared()
		if distance < best:
			best = distance
			chosen = foe
	return chosen


static func _point(row: Dictionary) -> Vector2:
	return Vector2(int(row["x_m"]), int(row["y_m"]))


## First contact along the actual forward corridor, including lateral group offsets.
static func _approach(repo: DataRepository, state: GameState, battle: Dictionary, code: String, foe: String, axis: Vector2) -> float:
	var own := BattleGroups.piece(repo, state, code)
	var enemy := BattleGroups.piece(repo, state, foe)
	if not own.ok or not enemy.ok: return INF
	var reach := float(int(own.radius_m) + int(enemy.radius_m) + int(repo.bal("battle_group_contact_m")))
	var distance := INF
	for row: Dictionary in battle.get("groups", {}).get(code, []):
		if row["role"] != "front":
			continue
		for other: Dictionary in battle.get("groups", {}).get(foe, []):
			var relative := _point(row) - _point(other)
			if BattleGroups.in_reach(repo, state, code, row, foe, other, int(repo.bal("battle_group_contact_m"))):
				return 0.0
			var projection := relative.dot(axis)
			var discriminant := projection * projection - relative.length_squared() + reach * reach
			if discriminant >= 0.0 and projection < 0.0:
				distance = minf(distance, -projection - sqrt(discriminant))
	return distance


static func _clear(repo: DataRepository, state: GameState, battle: Dictionary, code: String, movement: Vector2i) -> bool:
	return BattleGroups.motion(repo, state, battle, code, BattleSystem._at_m(repo, state, code),
		movement, ceili(Vector2(movement).length()))


static func move(repo: DataRepository, state: GameState, battle: Dictionary, code: String, foe: String) -> void:
	var entry := BattleSystem._stored(state, code)
	var from := BattleSystem._at_m(repo, state, code)
	var today := state.absolute_day()
	var charge: Dictionary = entry.get("charge", {}).duplicate(true)
	if charge.is_empty() or charge.get("target", "") != foe \
			or Vector2i(int(charge.get("x_m", from.x)), int(charge.get("y_m", from.y))) != from:
		var phase := String(charge.get("phase", "approach"))
		if phase == "impact":
			phase = "disengage"
		charge = {"phase": phase, "target": foe, "origin_x_m": from.x, "origin_y_m": from.y,
			"x_m": from.x, "y_m": from.y, "runup_m": 0, "impact_day": -1}
	var axis := Vector2(BattleSystem._at_m(repo, state, foe) - from).normalized()
	var heading := WarFront.facing_deg(axis)
	if charge["phase"] == "approach" and int(charge.get("heading_deg", heading)) != heading:
		charge["origin_x_m"] = from.x
		charge["origin_y_m"] = from.y
		charge["runup_m"] = 0
	charge["heading_deg"] = heading
	var approach := _approach(repo, state, battle, code, foe, axis)
	var runup := int(repo.bal("battle_charge_runup_m"))
	if charge["phase"] == "impact":
		if int(charge["impact_day"]) == today:
			return
		charge["phase"] = "disengage"
	if charge["phase"] == "regroup":
		charge["phase"] = "approach"
		charge["origin_x_m"] = from.x
		charge["origin_y_m"] = from.y
		charge["runup_m"] = 0
		entry["charge"] = charge
		return
	if charge["phase"] == "approach" and approach <= 0.0:
		charge["phase"] = "disengage"
		charge["runup_m"] = 0
		entry["charge"] = charge
		return
	var distance := approach
	if charge["phase"] == "disengage":
		distance = maxf(0.0, float(runup) - approach)
		axis = -axis
	if is_inf(distance) or axis == Vector2.ZERO:
		return
	var budget := int(repo.bal("battle_deploy_step_m"))
	var movement := Vector2i((axis * minf(distance, float(budget))).round())
	# Quantization must reach inclusive contact without exceeding the real step budget.
	if charge["phase"] == "approach" and distance <= float(budget) and Vector2(movement).dot(axis) < distance:
		if absf(axis.x) >= absf(axis.y):
			movement.x += 1 if axis.x > 0.0 else -1
		else:
			movement.y += 1 if axis.y > 0.0 else -1
	while movement.length_squared() > budget * budget:
		if absi(movement.x) >= absi(movement.y):
			movement.x -= 1 if movement.x > 0 else -1
		else:
			movement.y -= 1 if movement.y > 0 else -1
	if not _clear(repo, state, battle, code, movement):
		return
	var to := from + movement
	if not BattleGroups.translate(repo, state, battle, code, movement, budget): return
	entry["charge"] = charge
	charge["x_m"] = to.x
	charge["y_m"] = to.y
	BattleGroups.refresh(repo, state, battle)
	if charge["phase"] == "disengage":
		if _approach(repo, state, battle, code, foe, -axis) >= float(runup):
			charge["phase"] = "regroup"
		return
	var origin := Vector2i(int(charge["origin_x_m"]), int(charge["origin_y_m"]))
	charge["runup_m"] = mini(int(charge["runup_m"]) + int(Vector2(movement).length()), int(Vector2(to - origin).length()))
	if BattleGroups.engaged_counts(repo, state, battle, code, foe).x > 0:
		charge["phase"] = "impact" if int(charge["runup_m"]) >= runup else "disengage"
		charge["impact_day"] = today if charge["phase"] == "impact" else -1


## Only the actually touching front people can supply this opponent's shock.
static func impacting(repo: DataRepository, state: GameState, battle: Dictionary, code: String, foe := "") -> int:
	var charge: Dictionary = BattleSystem._stored(state, code).get("charge", {})
	if charge.get("phase", "") != "impact" or int(charge.get("impact_day", -1)) != state.absolute_day() \
			or target(repo, state, battle, code) != String(charge.get("target", "")):
		return 0
	var actual := String(charge["target"])
	if foe != "" and foe != actual:
		return 0
	var contact := BattleGroups.engaged_counts(repo, state, battle, code, actual)
	@warning_ignore("integer_division")
	return contact.x * mounted_share(repo, state, code) / 1000


static func consume(state: GameState, codes: Array, day: int) -> void:
	for code: String in codes:
		var charge: Dictionary = BattleSystem._stored(state, code).get("charge", {})
		if charge.get("phase", "") == "impact" and int(charge.get("impact_day", -1)) == day:
			charge["phase"] = "disengage"


## Candidate charges share TIME's writer, measured discs and paid allowance.
static func _candidate_error(repo: DataRepository, state: GameState) -> String:
	for key: String in ["battle_charge_runup_m", "battle_group_contact_m", "battle_context_arm_threshold_permille"]:
		if not BodyMotion._natural(repo.balance.get(key)) or repo.balance[key] > BodyMotion.LOCAL_LIMIT: return "Invalid charge policy: " + key
	for code: String in state.regiments.keys() + state.foes.keys():
		var entry := UnitBodies._entry(state, code)
		if not entry.has("charge"): continue
		var charge: Variant = entry.charge
		if not charge is Dictionary: return "Invalid saved charge"
		if charge.is_empty(): continue
		var keys := ["phase", "target", "origin_x_m", "origin_y_m", "x_m", "y_m", "heading_deg", "runup_m", "impact_day"]
		if charge.has("regroup_day"): keys.append("regroup_day")
		if not BodyMotion._keys(charge, keys) or charge.phase not in ["approach", "impact", "disengage", "regroup"] \
			or not charge.target is String or charge.target.is_empty(): return "Invalid saved charge schema"
		for key: String in ["origin_x_m", "origin_y_m", "x_m", "y_m", "heading_deg", "runup_m", "impact_day"]:
			if not BodyMotion._loco_integer(charge[key]): return "Noninteger saved charge: " + key
		if not BodyMotion._loco_point([charge.x_m, charge.y_m]) or not BodyMotion._loco_point([charge.origin_x_m, charge.origin_y_m]) \
			or charge.heading_deg < 0 or charge.heading_deg >= 360 or charge.runup_m < 0 or charge.runup_m > BodyMotion.LOCAL_LIMIT \
			or charge.impact_day < -1 or charge.impact_day > state.absolute_day(): return "Invalid saved charge values"
		if charge.has("regroup_day") and (not BodyMotion._natural(charge.regroup_day) or charge.regroup_day > state.absolute_day()): return "Invalid saved regroup day"
	return ""

static func _candidate_target(repo: DataRepository, state: GameState, battle: Dictionary, code: String) -> String:
	var entry := UnitBodies._entry(state, code)
	if bool(entry.get("captured", false)) or MilitaryRoster.fit(state, code) <= 0 or ArmyGround.seated_in(repo, state, code) != "" \
		or not CampSystem.can_march_entry(entry, state.absolute_day()) or battle.get("reserves", {}).has(code) \
		or mounted_share(repo, state, code) < int(repo.bal("battle_context_arm_threshold_permille")): return ""
	var action := BattleSystem.unit_action(repo, state, battle, code)
	if action.kind not in ["attack", "charge"] or action.has("pursuit_target"): return ""
	var reg := ArmySystem.regiment(repo, code, state)
	var bite := ArmySystem.day_bite(ArmySystem.supply_use(repo, reg, state), state.day)
	if int(entry.get("supplies", 0)) < bite + BattleSystem._attack_supply(repo, bite): return ""
	var side := BattleRules.side_of(battle, code)
	var enemies: Array = battle["def" if side == "att" else "att"].duplicate()
	enemies.sort()
	var designated: String = BattleTaskSystem.current(state, code).get("request", {}).get("target_unit", "")
	var chosen := ""
	var best := INF
	for enemy: String in enemies:
		if not designated.is_empty() and enemy != designated: continue
		if not BattleSystem._can_fight(repo, state, enemy) or bool(UnitBodies._entry(state, enemy).get("captured", false)) \
			or "charge" not in BattleRules.legal_actions(repo, state, int(battle.id), side, code, enemy) \
			or not BodyBattleContact._barred(repo, state, battle, battle, side, code, enemy).is_empty(): continue
		var other := UnitBodies._entry(state, enemy)
		var x := BodyMotion._difference(other.x_m, entry.x_m)
		var y := BodyMotion._difference(other.y_m, entry.y_m)
		if absf(x) > BodyMotion.LOCAL_LIMIT or absf(y) > BodyMotion.LOCAL_LIMIT: continue
		var distance := x * x + y * y
		if distance < best:
			best = distance
			chosen = enemy
	return chosen

static func _candidate_axis(state: GameState, code: String, enemy: String) -> Vector2:
	var entry := UnitBodies._entry(state, code)
	var other := UnitBodies._entry(state, enemy)
	return Vector2(BodyMotion._difference(other.x_m, entry.x_m), BodyMotion._difference(other.y_m, entry.y_m)).normalized()

static func _candidate_prepare(state: GameState, code: String, enemy: String, heading: int) -> Dictionary:
	var entry := UnitBodies._entry(state, code)
	var charge: Dictionary = entry.get("charge", {}).duplicate(true)
	var phase: String = charge.get("phase", "approach")
	if phase == "impact" and int(charge.impact_day) < state.absolute_day(): phase = "disengage"
	if charge.is_empty() or charge.target != enemy or [charge.x_m, charge.y_m] != [entry.x_m, entry.y_m] \
		or (phase == "approach" and charge.heading_deg != heading):
		if phase == "impact": phase = "disengage"
		charge = {"phase": phase, "target": enemy, "origin_x_m": int(entry.x_m), "origin_y_m": int(entry.y_m),
			"x_m": int(entry.x_m), "y_m": int(entry.y_m), "heading_deg": heading, "runup_m": 0, "impact_day": -1}
	charge.phase = phase
	charge.heading_deg = heading
	if phase == "regroup":
		if not charge.has("regroup_day"): charge.regroup_day = state.absolute_day()
		if state.absolute_day() > int(charge.regroup_day) + 1:
			charge.phase = "approach"
			charge.origin_x_m = int(entry.x_m)
			charge.origin_y_m = int(entry.y_m)
			charge.runup_m = 0
			charge.erase("regroup_day")
	return charge

## First actual surface along the forward axis; roles never manufacture contact.
static func _candidate_gap(repo: DataRepository, state: GameState, battle: Dictionary, code: String, enemy: String, axis: Vector2) -> float:
	var own := BattleGroupGeometry.footprint(repo, state.army_roster[code])
	var other := BattleGroupGeometry.footprint(repo, state.army_roster[enemy])
	var reach: float = own.radius_m + other.radius_m + repo.bal("battle_group_contact_m")
	var best := INF
	for row: Dictionary in battle.groups[code]:
		for foe: Dictionary in battle.groups[enemy]:
			var relative := Vector2(BodyMotion._difference(row.x_m, foe.x_m), BodyMotion._difference(row.y_m, foe.y_m))
			var pair := BattleGroupGeometry.pair([row.x_m, row.y_m], own.radius_m, [foe.x_m, foe.y_m], other.radius_m, int(repo.bal("battle_group_contact_m")))
			if pair.ok and pair.in_reach: return 0.0
			var projection := relative.dot(axis)
			var discriminant := projection * projection - relative.length_squared() + reach * reach
			if projection < 0.0 and discriminant >= 0.0: best = minf(best, -projection - sqrt(discriminant))
	return best

static func _candidate_touch(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		enemy: String, axis: Vector2, offset: Array = [0, 0]) -> bool:
	var own := BattleGroupGeometry.footprint(repo, state.army_roster[code])
	var other := BattleGroupGeometry.footprint(repo, state.army_roster[enemy])
	for row: Dictionary in battle.groups[code]:
		var a: Array = [int(row.x_m) + int(offset[0]), int(row.y_m) + int(offset[1])]
		for foe: Dictionary in battle.groups[enemy]:
			var b: Array = [int(foe.x_m), int(foe.y_m)]
			var direction := Vector2(BodyMotion._difference(b[0], a[0]), BodyMotion._difference(b[1], a[1]))
			var pair := BattleGroupGeometry.pair(a, own.radius_m, b, other.radius_m, int(repo.bal("battle_group_contact_m")))
			if pair.ok and not pair.overlap and pair.in_reach and direction.dot(axis) > 0.0 \
				and ArmySystem._body_path_terrain(MarchPath.of_pack(repo), [a, b], 0).is_empty(): return true
	return false

static func intent_candidate(repo: DataRepository, source: GameState, battle_id: int, unit: String, budget_m: int) -> Dictionary:
	var failure := {"status": "error", "reason": "Invalid candidate charge", "error": "Invalid candidate charge", "unit": unit, "path_m": []}
	if repo == null or source == null or budget_m < 0 or budget_m > BodyMotion.LOCAL_LIMIT or source.day_resolution.is_empty(): return failure
	var control: Variant = source.day_resolution.get("body_battle")
	if not control is Dictionary: return failure
	var boundary := {"version": 1, "kind": "battle", "abs_day": control.get("abs_day"), "substep": control.get("next_substep"), "sequence": control.get("sequence"), "stage": control.get("stage")}
	var error := BodyBattleMotion._source_error(repo, source, boundary)
	if not error.is_empty():
		failure.reason = error
		failure.error = error
		return failure
	source = UnitBodies._copy(source)
	var battle := UnitBodies._battle(source, BodyBattleContact._canonical_id(source, battle_id))
	if battle.is_empty() or BattleRules.side_of(battle, unit).is_empty(): return failure
	var entry := UnitBodies._entry(source, unit)
	var here: Array = [int(entry.x_m), int(entry.y_m)]
	var result := {"status": "complete", "reason": "Charge holds without a lawful mounted approach", "error": "", "unit": unit, "path_m": [here]}
	if BodyBattleMotion._writer(repo, source, unit, battle) != "charge" or budget_m == 0: return result
	var enemy := _candidate_target(repo, source, battle, unit)
	if enemy.is_empty(): return result
	var axis := _candidate_axis(source, unit, enemy)
	var charge := _candidate_prepare(source, unit, enemy, WarFront.facing_deg(axis))
	if charge.phase in ["impact", "regroup"]: return result
	var gap := _candidate_gap(repo, source, battle, unit, enemy, axis)
	var runup := float(repo.bal("battle_charge_runup_m"))
	var distance := gap if charge.phase == "approach" else (runup if gap >= runup else runup - gap)
	if is_inf(distance) or axis == Vector2.ZERO: return result
	if charge.phase == "disengage": axis = -axis
	var step := axis * minf(distance, float(budget_m))
	var to: Array = [here[0] + int(round(step.x)), here[1] + int(round(step.y))]
	if charge.phase == "approach" and distance > 0.0 and distance <= float(budget_m):
		for rounding: Array in [[0, 0], [-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [-1, 1], [1, -1], [1, 1]]:
			var option: Array = [int(to[0]) + rounding[0], int(to[1]) + rounding[1]]
			var offset: Array = [int(option[0]) - int(here[0]), int(option[1]) - int(here[1])]
			if BodyMotion._length([here, option]) <= budget_m and _candidate_touch(repo, source, battle, unit, enemy, axis, offset):
				to = option
				break
	var path := BodyMotion._clip([here, to], budget_m)
	var footprint := BattleGroupGeometry.footprint(repo, source.army_roster[unit])
	for row: Dictionary in battle.groups[unit]:
		var translated: Array = []
		for point: Array in path: translated.append([int(row.x_m) + int(point[0]) - int(here[0]), int(row.y_m) + int(point[1]) - int(here[1])])
		var terrain := ArmySystem._body_path_terrain(MarchPath.of_pack(repo), translated, int(footprint.radius_m))
		if not terrain.is_empty():
			result.reason = terrain
			return result
	result.path_m = path
	result.reason = "Earned charge corridor" if path.size() > 1 else "At actual charge contact or disengagement gap"
	return result

## Allowance rounds up; earned whole metres round down and never exceed displacement.
static func _candidate_distance(a: Array, b: Array) -> int:
	var x := BodyMotion._difference(a[0], b[0])
	var y := BodyMotion._difference(a[1], b[1])
	if absf(x) > BodyMotion.LOCAL_LIMIT or absf(y) > BodyMotion.LOCAL_LIMIT: return BodyMotion.LOCAL_LIMIT
	var squared := int(x) * int(x) + int(y) * int(y)
	var distance := BodyMotion._distance_ceil(a, b)
	return distance - (1 if distance * distance > squared else 0)

## Called only inside the union commit, after TIME has committed all actual rows.
static func _settle_candidate(repo: DataRepository, source: GameState, candidate: GameState, code: String,
		writer: String, common: Array, moves: Array) -> void:
	var entry := UnitBodies._entry(candidate, code)
	var battle := BattleSystem.battle_of(candidate, code)
	var old := UnitBodies._entry(source, code)
	if writer != "charge" or battle.is_empty():
		if not old.get("charge", {}).is_empty():
			entry.charge = old.charge.duplicate(true)
			if entry.charge.phase == "approach": entry.erase("charge")
			elif entry.charge.phase != "impact" or int(entry.charge.impact_day) < candidate.absolute_day():
				entry.charge.phase = "disengage"
				entry.charge.runup_m = 0
		return
	# Existing law queries may fill historical parties; never write into the caller.
	source = UnitBodies._copy(source)
	var previous := BattleSystem.battle_of(source, code)
	var enemy := _candidate_target(repo, source, previous, code)
	if enemy.is_empty():
		if old.get("charge", {}).get("phase") == "approach": entry.erase("charge")
		return
	var axis := _candidate_axis(source, code, enemy)
	var heading := WarFront.facing_deg(axis)
	var charge := _candidate_prepare(source, code, enemy, heading)
	var distance := _candidate_distance(common[0], common.back())
	if charge.phase == "approach":
		var straight := true
		for move: Dictionary in moves:
			if move.unit != code: continue
			distance = mini(distance, _candidate_distance(move.start, move.end))
			if int(move.final_facing_deg) != heading: straight = false
			for op: Dictionary in move.ops:
				if op.kind == "pivot" and (posmod(roundi(float(op.yaw0_udeg) / BodyMotion.LOCOMOTION_Q), 360) != heading \
					or posmod(roundi(float(op.yaw0_udeg + op.turn_udeg) / BodyMotion.LOCOMOTION_Q), 360) != heading): straight = false
				if op.kind == "move" and WarFront.facing_deg(Vector2(BodyMotion._difference(op.b[0], op.a[0]), BodyMotion._difference(op.b[1], op.a[1]))) != heading: straight = false
		if not straight:
			charge.runup_m = 0
			charge.origin_x_m = int(entry.x_m)
			charge.origin_y_m = int(entry.y_m)
		elif distance > 0:
			charge.runup_m = mini(int(charge.runup_m) + distance, _candidate_distance([charge.origin_x_m, charge.origin_y_m], [entry.x_m, entry.y_m]))
			if _candidate_touch(repo, candidate, battle, code, enemy, axis) \
				and "charge" in BattleRules.legal_actions(repo, candidate, int(battle.id), BattleRules.side_of(battle, code), code, enemy) \
				and BodyBattleContact._barred(repo, candidate, battle, battle, BattleRules.side_of(battle, code), code, enemy).is_empty():
				charge.phase = "impact" if charge.runup_m >= int(repo.bal("battle_charge_runup_m")) else "disengage"
				charge.impact_day = candidate.absolute_day() if charge.phase == "impact" else -1
	elif charge.phase == "disengage" and distance > 0 \
		and _candidate_gap(repo, candidate, battle, code, enemy, axis) >= float(repo.bal("battle_charge_runup_m")):
		charge.phase = "regroup"
		charge.regroup_day = candidate.absolute_day()
	charge.x_m = int(entry.x_m)
	charge.y_m = int(entry.y_m)
	entry.charge = charge
