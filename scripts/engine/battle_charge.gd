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
static func _approach(repo: DataRepository, battle: Dictionary, code: String, foe: String, axis: Vector2) -> float:
	var reach := float(repo.bal("battle_group_contact_m"))
	var distance := INF
	for row: Dictionary in battle.get("groups", {}).get(code, []):
		if row["role"] != "front":
			continue
		for other: Dictionary in battle.get("groups", {}).get(foe, []):
			var relative := _point(row) - _point(other)
			if relative.length_squared() <= reach * reach:
				return 0.0
			var projection := relative.dot(axis)
			var discriminant := projection * projection - relative.length_squared() + reach * reach
			if discriminant >= 0.0 and projection < 0.0:
				distance = minf(distance, -projection - sqrt(discriminant))
	return distance


static func _clear(repo: DataRepository, battle: Dictionary, code: String, movement: Vector2i) -> bool:
	return BattleGroups.sweep_clear(repo, null, battle, code, -1, Vector2i.ZERO, [movement])


static func move(repo: DataRepository, state: GameState, battle: Dictionary, code: String, foe: String) -> void:
	var entry := BattleSystem._stored(state, code)
	var from := BattleSystem._at_m(repo, state, code)
	var today := state.absolute_day()
	var charge: Dictionary = entry.get("charge", {})
	if charge.is_empty() or charge.get("target", "") != foe \
			or Vector2i(int(charge.get("x_m", from.x)), int(charge.get("y_m", from.y))) != from:
		var phase := String(charge.get("phase", "approach"))
		if phase == "impact":
			phase = "disengage"
		charge = {"phase": phase, "target": foe, "origin_x_m": from.x, "origin_y_m": from.y,
			"x_m": from.x, "y_m": from.y, "runup_m": 0, "impact_day": -1}
		entry["charge"] = charge
	var axis := Vector2(BattleSystem._at_m(repo, state, foe) - from).normalized()
	var heading := WarFront.facing_deg(axis)
	if charge["phase"] == "approach" and int(charge.get("heading_deg", heading)) != heading:
		charge["origin_x_m"] = from.x
		charge["origin_y_m"] = from.y
		charge["runup_m"] = 0
	charge["heading_deg"] = heading
	var approach := _approach(repo, battle, code, foe, axis)
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
		return
	if charge["phase"] == "approach" and approach <= 0.0:
		charge["phase"] = "disengage"
		charge["runup_m"] = 0
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
	if not _clear(repo, battle, code, movement):
		return
	var to := from + movement
	BattleGroups.translate(repo, state, battle, code, movement)
	charge["x_m"] = to.x
	charge["y_m"] = to.y
	BattleGroups.refresh(repo, state, battle)
	if charge["phase"] == "disengage":
		if _approach(repo, battle, code, foe, -axis) >= float(runup):
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
