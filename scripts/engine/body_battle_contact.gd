class_name BodyBattleContact
extends RefCounted
## Read-only candidate melee evidence; no movement, discovery or damage publication.

static func query_candidate(repo: DataRepository, source: GameState, battle_id: int,
		unit: String, enemies: Array, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null or battle_id <= 0 or battle_id > BodyMotion.JSON_INTEGER_MAX:
		return _failure(battle_id, unit, "Contact requires data, source and a live battle ID")
	var canonical := _canonical_id(source, battle_id)
	if canonical <= 0: return _failure(battle_id, unit, "Invalid raw contact battle alias")
	var checked := UnitBodies.validate_battle_candidate(repo, source, boundary)
	if checked.status != "complete": return _failure(battle_id, unit, checked.reason)
	# BattleRules infers missing historical parties, so even legal queries use the detached admission.
	var state: GameState = checked.candidate
	battle_id = canonical
	var battle := UnitBodies._battle(state, battle_id)
	var side := BattleRules.side_of(battle, unit)
	if battle.is_empty() or side == "": return _failure(battle_id, unit, "Contact unit is not a live battle member")
	var index := UnitBodies._owners(state)
	var targets: Array[Dictionary] = []
	var previous := ""
	var relations := {"player": repo.resolve_realm("player_realm"), "raider": repo.resolve_realm("raider_realm"),
		"diplomacy": repo.world_table("political", "diplomacy"), "hostile": {}}
	for raw: Variant in enemies:
		if not raw is String or raw.is_empty() or (previous != "" and raw <= previous):
			return _failure(battle_id, unit, "Contact enemies must be unique sorted unit codes")
		previous = raw
		var field: Dictionary = index.owners.get(raw, {})
		if field.is_empty() or _canonical_id(source, int(field.id)) != int(field.id) \
			or BattleRules.side_of(field, raw) == "" or raw == unit \
			or (int(field.id) == battle_id and BattleRules.side_of(field, raw) == side) \
			or not ArmySystem._hostile(relations, ArmySystem.realm_of(repo, unit, state), ArmySystem.realm_of(repo, raw, state)):
			return _failure(battle_id, unit, "Contact target is absent, hidden or not an opposing battlefield member")
		targets.append({"unit": raw, "battle": field})
	var reach: Variant = repo.balance.get("battle_group_contact_m")
	if not BodyMotion._loco_integer(reach) or reach < 0:
		return _failure(battle_id, unit, "Invalid configured surface contact reach")
	var grid := MarchPath.of_pack(repo)
	if not BodyMotion._loco_grid_ok(grid): return _failure(battle_id, unit, "Contact requires valid land terrain")
	var own := BattleGroupGeometry.footprint(repo, state.army_roster[unit])
	if not own.ok: return _failure(battle_id, unit, own.reason)
	var fit := MilitaryRoster.fit(state, unit)
	var engaged := 0
	var pairs: Array[Dictionary] = []
	var reasons: Array[String] = []
	for row: Dictionary in battle.groups[unit]:
		var touching := false
		for target: Dictionary in targets:
			var enemy: String = target.unit
			var barred := _barred(repo, state, battle, target.battle, side, unit, enemy)
			if not barred.is_empty():
				if not barred in reasons: reasons.append(barred)
				continue
			var footprint := BattleGroupGeometry.footprint(repo, state.army_roster[enemy])
			if not footprint.ok: return _failure(battle_id, unit, footprint.reason)
			for other: Dictionary in target.battle.groups[enemy]:
				var a: Array = [row.x_m, row.y_m]
				var b: Array = [other.x_m, other.y_m]
				var metric := BattleGroupGeometry.pair(a, int(own.radius_m), b, int(footprint.radius_m), int(reach))
				if not metric.ok: return _failure(battle_id, unit, metric.reason)
				if metric.overlap: return _failure(battle_id, unit, "Contact bodies overlap")
				if not metric.in_reach: continue
				var terrain := ArmySystem._body_path_terrain(grid, [a, b], 0)
				if not terrain.is_empty():
					if not terrain in reasons: reasons.append(terrain)
					continue
				touching = true
				pairs.append({"unit": unit, "slot": int(row.slot), "target_unit": enemy,
					"target_slot": int(other.slot), "count": int(row.count), "target_count": int(other.count),
					"kind": "melee", "reason": "Lawful physical surface contact over open ground"})
		if touching: engaged += int(row.count)
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return UnitBodies._battle_pair_less([a.unit, a.slot, a.target_unit, a.target_slot],
			[b.unit, b.slot, b.target_unit, b.target_slot]))
	var reason := "Lawful surface contact: %d of %d fit personnel" % [engaged, fit]
	if not reasons.is_empty(): reason += "; " + "; ".join(reasons)
	return {"status": "complete", "reason": reason, "error": "", "battle_id": battle_id,
		"unit": unit, "fit": fit, "engaged": engaged, "pairs": pairs}

static func _barred(repo: DataRepository, state: GameState, own: Dictionary,
		target: Dictionary, side: String, unit: String, enemy: String) -> String:
	if bool(UnitBodies._entry(state, unit).get("captured", false)) \
		or bool(UnitBodies._entry(state, enemy).get("captured", false)):
		return "Captured personnel cannot form outgoing contact pairs"
	var legal := BattleRules.legal_actions(repo, state, int(own.id), side, unit, enemy)
	for field: Dictionary in [own, target]:
		if BattleRules._binds(field, "ceasefire", "protect", state.absolute_day(), [unit], enemy):
			return "Bilateral ceasefire bars outgoing contact"
	if not "attack" in legal: return "Received law or agreement bars outgoing attack"
	var enemy_side := BattleRules.side_of(target, enemy)
	var withdrawing: bool = BattleOrders.kind(target, enemy_side) == "retreat" \
		or target.get("routed_side", "") == enemy_side \
		or bool(UnitBodies._entry(state, enemy).get("battle_retreat", false))
	if withdrawing:
		for field: Dictionary in [own, target]:
			if BattleRules._binds(field, "safe_withdrawal", "protect", state.absolute_day(), [unit], enemy):
				return "Bilateral safe withdrawal bars outgoing contact"
			if BattleRules._binds(field, "tactics", "restrained", state.absolute_day(), [unit], enemy):
				return "Bilateral restrained tactics bars pursuit of the withdrawing target"
		if not "pursue" in legal: return "Received law bars pursuit of the withdrawing target"
	return ""

static func _canonical_id(source: GameState, id: int) -> int:
	var seen := {}
	while source.battle_aliases.has(str(id)):
		if seen.has(id): return 0
		seen[id] = true
		var next: Variant = source.battle_aliases[str(id)]
		if not BodyMotion._loco_integer(next) or next <= 0: return 0
		id = int(next)
	return id

static func _failure(battle_id: int, unit: String, reason: String) -> Dictionary:
	return {"status": "error", "reason": reason, "error": reason, "battle_id": battle_id,
		"unit": unit, "fit": 0, "engaged": 0, "pairs": []}
