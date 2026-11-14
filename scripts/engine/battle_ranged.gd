class_name BattleRanged
extends RefCounted
## Direct fire uses saved group positions; no projectile or camera decides a hit.

static func share(repo: DataRepository, state: GameState, code: String) -> int:
	var row := ArmySystem.regiment(repo, code, state)
	var total := 0
	var ranged := 0
	for arm: String in repo.world_table("military", "unit_types"):
		var definition: Dictionary = repo.world_table("military", "unit_types")[arm]
		var people := int(row.get(arm, 0)) * int(definition["crew"])
		total += people
		if definition["type"] in ["ranged", "machinery"]:
			ranged += people
	@warning_ignore("integer_division")
	return ranged * 1000 / total if total > 0 else 0


static func point(row: Dictionary) -> Vector2i:
	return Vector2i(int(row["x_m"]), int(row["y_m"]))


static func touching(repo: DataRepository, battle: Dictionary, code: String, state: GameState) -> bool:
	var side := BattleRules.side_of(battle, code)
	if side == "":
		return false
	var reach := int(repo.bal("battle_group_contact_m"))
	for row: Dictionary in battle.get("groups", {}).get(code, []):
		for foe: String in battle["def" if side == "att" else "att"]:
			for other: Dictionary in battle.get("groups", {}).get(foe, []):
				if int(row["count"]) > 0 and int(other["count"]) > 0 \
						and BattleGroups.in_reach(repo, state, code, row, foe, other, reach):
					return true
	return false


## Inclusive reach and cone edge; a friendly disc tangent to the open segment blocks.
static func clear_shot(repo: DataRepository, from: Vector2i, to: Vector2i,
		facing: Vector2i, friends: Array[Vector2i], radius_from := 0, radius_to := 0, discs: Array = []) -> bool:
	var blockers: Array = discs.duplicate()
	for at: Vector2i in friends:
		blockers.append({"x_m": at.x, "y_m": at.y, "radius_m": int(repo.bal("battle_ranged_block_radius_m"))})
	var checked := shot(repo, from, to, facing, radius_from, radius_to, blockers)
	return checked.ok and checked.clear


## `clear_shot` with its geometry errors kept apart from "no clear shot": `{ok, clear}`.
static func shot(repo: DataRepository, from: Vector2i, to: Vector2i, facing: Vector2i,
		radius_from: int, radius_to: int, blockers: Array) -> Dictionary:
	var d := to - from
	var reach := int(repo.bal("battle_ranged_reach_m"))
	var close := int(repo.bal("battle_group_contact_m"))
	var contact := BattleGroupGeometry.pair([from.x, from.y], radius_from, [to.x, to.y], radius_to, close)
	var range_ := BattleGroupGeometry.pair([from.x, from.y], radius_from, [to.x, to.y], radius_to, reach)
	if not contact.ok or not range_.ok: return {"ok": false, "clear": false}
	if contact.in_reach or not range_.in_reach: return {"ok": true, "clear": false}
	var forward := d.x * facing.x + d.y * facing.y
	var cross := d.x * facing.y - d.y * facing.x
	if forward <= 0 or absi(cross) * 1000 > forward * int(repo.bal("battle_ranged_cone_permille")):
		return {"ok": true, "clear": false}
	for blocker: Dictionary in blockers:
		var hit := BattleGroupGeometry.segment_disc([from.x, from.y], [to.x, to.y],
			[blocker.x_m, blocker.y_m], int(blocker.radius_m))
		if not hit.ok: return {"ok": false, "clear": false}
		if hit.blocked: return {"ok": true, "clear": false}
	return {"ok": true, "clear": true}


## Count each group once. An optional other field retains both sources' commands and terms.
static func counts(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		target := "", opposing_battle: Dictionary = {}, incoming_context := false, active_round := false) -> Dictionary:
	var out := {"firing": 0, "melee": 0, "fit": 0}
	var rows: Array = battle.get("groups", {}).get(code, [])
	for row: Dictionary in rows:
		out["fit"] += int(row["count"])
	var side := BattleRules.side_of(battle, code)
	if side == "" or rows.is_empty() or not BattleSystem._can_fight(repo, state, code) \
			or bool(BattleSystem._stored(state, code).get("captured", false)):
		return out
	var action := BattleSystem.unit_action(repo, state, battle, code)
	var in_melee := touching(repo, battle, code, state)
	if (action["kind"] == "retreat" and not (incoming_context and in_melee)) or (not in_melee and battle.get("reserves", {}).has(code) and action["task_id"] == ""):
		return out
	var task := BattleTaskSystem.current(state, code)
	var designated := String(task.get("request", {}).get("target_unit", "")) if action["task_id"] != "" else ""
	var opponents := battle if opposing_battle.is_empty() else opposing_battle.duplicate(true)
	var friendly := side if opposing_battle.is_empty() else BattleSystem._side_for(state, opponents, code)
	var other := "def" if friendly == "att" else "att"
	var close := int(repo.bal("battle_group_contact_m"))
	var sight := int(repo.bal("ai_sight_km" if ArmySystem.is_foe(state, code) else "player_sight_km") * 1000)
	var axis := Vector2i((WarFront.facing_vector(int(battle.get("group_facing", {}).get(code, 0))) * 1000).round())
	var friends: Array = []
	for member: String in battle[side]:
		for row: Dictionary in battle.get("groups", {}).get(member, []):
			if int(row["count"]) > 0:
				friends.append({"x_m": row.x_m, "y_m": row.y_m,
					"radius_m": BattleGroups.piece(repo, state, member).get("radius_m", -1)})
	if not opposing_battle.is_empty():
		for member: String in opponents[friendly]:
			for row: Dictionary in opponents.get("groups", {}).get(member, []):
				if int(row["count"]) > 0:
					friends.append({"x_m": row.x_m, "y_m": row.y_m,
					"radius_m": BattleGroups.piece(repo, state, member).get("radius_m", -1)})
	for row: Dictionary in rows:
		if int(row["count"]) <= 0:
			continue
		var from := point(row)
		var blockers: Array = friends.duplicate()
		blockers.erase({"x_m": from.x, "y_m": from.y, "radius_m": BattleGroups.piece(repo, state, code).get("radius_m", -1)})  # exclude this shooter, retaining any overlapping other group
		var inside := true
		var region := String(action.get("pursuit_region", ""))
		if region != "":
			var at := ArmySystem.metres_to_pack(repo, from)
			inside = MapManors.province_of(repo, MapEconomy.cell_at(repo, at), state) in region.split("|")
		for foe: String in opponents[other]:
			if target != "" and target != foe:
				continue
			var self_defence: bool = in_melee and BattleSystem.unit_action(repo, state, opponents, foe)["kind"] == "attack"
			if active_round and action["kind"] != "attack" and not self_defence:
				continue # A remote attack cannot authorize this holding pair to hurt each other.
			if not self_defence and (not inside or (designated != "" and designated != foe)):
				continue
			if not BattleSystem._can_fight(repo, state, foe) or bool(BattleSystem._stored(state, foe).get("captured", false)):
				continue
			var legal := BattleRules.legal_actions(repo, state, int(battle["id"]), side, code, foe)
			if not opposing_battle.is_empty():
				# Source-scoped parties can bind a target now fighting on another field.
				if BattleRules._binds(opponents, "ceasefire", "protect", state.absolute_day(), [code], foe):
					legal.erase("attack")
				if BattleRules._binds(opponents, "safe_withdrawal", "protect", state.absolute_day(), [code], foe) \
						or BattleRules._binds(opponents, "tactics", "restrained", state.absolute_day(), [code], foe):
					legal.erase("pursue")
			if not "attack" in legal:
				continue
			var withdrawing := BattleOrders.kind(opponents, other) == "retreat" or bool(BattleSystem._stored(state, foe).get("battle_retreat", false))
			if not opposing_battle.is_empty():
				withdrawing = BattleSystem.unit_action(repo, state, opponents, foe)["kind"] == "retreat"
			# combat_context already suppresses the bound opponent's power share once.
			var protected_share := incoming_context and BattleRules._binds(battle,
				"safe_withdrawal", "protect", state.absolute_day(), [foe], code)
			if withdrawing and not "pursue" in legal and not protected_share:
				continue
			var visible := BattleSystem._at_m(repo, state, foe) - BattleSystem._at_m(repo, state, code)
			if visible.length_squared() > sight * sight:
				continue
			var engaged := false
			for enemy: Dictionary in opponents.get("groups", {}).get(foe, []):
				if int(enemy["count"]) <= 0:
					continue
				var to := point(enemy)
				if in_melee:
					if row["role"] == "front" and BattleGroups.in_reach(repo, state, code, row, foe, enemy, close):
						out["melee"] += int(row["count"])
						engaged = true
				elif action["kind"] == "attack" and share(repo, state, code) > 0 and clear_shot(repo, from, to, axis, [],
						int(BattleGroups.piece(repo, state, code).get("radius_m", -1)),
						int(BattleGroups.piece(repo, state, foe).get("radius_m", -1)), blockers):
					out["firing"] += int(row["count"])
					engaged = true
				if engaged:
					break
			if engaged:
				break
	return out


static func active_permille(count: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (int(count["firing"]) + int(count["melee"])) * 1000 / int(count["fit"]) if int(count["fit"]) > 0 else 0


## Each equipment share contributes only where its actual personnel can reach.
static func incoming_permille(repo: DataRepository, state: GameState, battle: Dictionary,
		side: String, target := "", active_round := true) -> int:
	# Arithmetic adapters/old records retain their context until production refreshes groups.
	if not battle.has("groups"):
		return 1000
	var total := 0
	var active := 0
	for code: String in battle["def" if side == "att" else "att"]:
		var fit := ArmySystem.fit_count(repo, state, code)
		var ranged := share(repo, state, code)
		var actual := counts(repo, state, battle, code, target, {}, true, active_round)
		var factor := active_permille(actual)
		@warning_ignore("integer_division")
		var melee := int(actual.melee) * 1000 / int(actual.fit) if int(actual.fit) > 0 else 0
		total += fit
		@warning_ignore("integer_division")
		active += fit * ((1000 - ranged) * melee / 1000 + ranged * factor / 1000)
	@warning_ignore("integer_division")
	return active / total if total > 0 else 1000


## CF06 candidate direct fire on an admitted body world: `{status,reason,error,battle_id,unit,
## fit,firing,melee,pairs}`. Close defence is the lawful physical surface query; otherwise only
## an attacking ranged-equipped unit fires, with the production reach/cone/contact geometry of
## `clear_shot`, every positive friendly row of both fields as a measured blocker (only the
## shooter row excluded) and an open terrain segment. Firing and melee are disjoint unions of
## row identities. `opposing_battle_id` 0 is the same field; `target` "" is every opponent.
static func counts_candidate(repo: DataRepository, source: GameState, battle_id: int, unit: String,
		target: String, opposing_battle_id: int, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null or battle_id <= 0 or opposing_battle_id < 0:
		return _fire_failure(battle_id, unit, "Fire requires data, source and live battle IDs")
	var own_id := BodyBattleContact._canonical_id(source, battle_id)
	var other_id := own_id if opposing_battle_id == 0 else BodyBattleContact._canonical_id(source, opposing_battle_id)
	if own_id <= 0 or other_id <= 0: return _fire_failure(battle_id, unit, "Invalid raw fire battle alias")
	var checked := UnitBodies.validate_battle_candidate(repo, source, boundary)
	if checked.status != "complete": return _fire_failure(own_id, unit, checked.reason)
	var state: GameState = checked.candidate
	var battle := UnitBodies._battle(state, own_id)
	var opponents := UnitBodies._battle(state, other_id)
	var side := BattleRules.side_of(battle, unit)
	if battle.is_empty() or opponents.is_empty() or side == "": return _fire_failure(own_id, unit, "Fire unit is not a live battle member")
	var friendly := side if other_id == own_id else BattleSystem._side_for(state, opponents, unit)
	var other := "def" if friendly == "att" else "att"
	var relations := {"player": repo.resolve_realm("player_realm"), "raider": repo.resolve_realm("raider_realm"),
		"diplomacy": repo.world_table("political", "diplomacy"), "hostile": {}}
	var hostile := func(code: String) -> bool:   # the contact query's own hostility predicate
		return ArmySystem._hostile(relations, ArmySystem.realm_of(repo, unit, state), ArmySystem.realm_of(repo, code, state))
	var all_foes: Array = opponents[other].filter(hostile)
	var foes: Array = all_foes.duplicate() if target == "" else [target]
	foes.sort()
	for foe: String in foes:
		if foe not in all_foes: return _fire_failure(own_id, unit, "Fire target is not a hostile opposing member of that field")
	var fit := MilitaryRoster.fit(state, unit)
	var result := {"status": "complete", "reason": "", "error": "", "battle_id": own_id, "unit": unit,
		"fit": fit, "firing": 0, "melee": 0, "pairs": []}
	if foes.is_empty():
		result.reason = "No opposing target"
		return result
	if not BattleSystem._can_fight(repo, state, unit) or bool(UnitBodies._entry(state, unit).get("captured", false)):
		result.reason = "Captured or incapable units neither fire nor defend"
		return result
	var action := BattleSystem.unit_action(repo, state, battle, unit)
	var task := BattleTaskSystem.current(state, unit)
	var designated := String(task.get("request", {}).get("target_unit", "")) if String(action.get("task_id", "")) != "" else ""
	var sight := int(repo.bal("ai_sight_km" if ArmySystem.is_foe(state, unit) else "player_sight_km") * 1000)
	# PHYSICAL contact with ANY hostile opponent of its own field (or the queried field) suppresses
	# fire, even where the law bars attacking that opponent; the lawful query gives the melee pairs.
	var nearby: Array = battle["def" if side == "att" else "att"].filter(hostile)
	for foe: String in all_foes:
		if foe not in nearby: nearby.append(foe)
	nearby.sort()
	var touching := BodyBattleContact.exposure_candidate(repo, source, own_id, unit, nearby, boundary)
	if touching.status != "complete": return _fire_failure(own_id, unit, touching.reason)
	var close := BodyBattleContact.query_candidate(repo, source, own_id, unit, nearby, boundary)
	if close.status != "complete": return _fire_failure(own_id, unit, close.reason)
	if int(touching.engaged) > 0:
		# Close defence (a received retreat stays retreat). Outside self-defence against an
		# attacking foe, the designated target and local sight still restrict the pair.
		if action.kind == "retreat":
			result.reason = "A received retreat neither fires nor defends forward"
			return result
		var rows := {}
		var melee_region := String(action.get("pursuit_region", ""))
		for pair: Dictionary in close.pairs:
			if pair.target_unit not in foes or int(pair.count) <= 0 or int(pair.target_count) <= 0: continue
			if not BattleSystem._can_fight(repo, state, pair.target_unit): continue
			var foe_field := opponents if pair.target_unit in opponents[other] else battle
			var foe_action := BattleSystem.unit_action(repo, state, foe_field, pair.target_unit)
			var defending: bool = foe_action.kind == "attack" or bool(foe_action.get("close_defence", false))
			# A holding pair cannot hurt each other: one side must attack (original active-round rule).
			if action.kind != "attack" and not defending: continue
			var seen := BattleSystem._at_m(repo, state, pair.target_unit) - BattleSystem._at_m(repo, state, unit)
			if seen.length_squared() > sight * sight: continue
			if not defending and designated != "" and designated != pair.target_unit: continue
			if not defending and melee_region != "":
				var own_row: Dictionary = battle.groups[unit].filter(func(r: Dictionary) -> bool: return int(r.slot) == int(pair.slot))[0]
				var cell := MapEconomy.cell_at(repo, ArmySystem.metres_to_pack(repo, point(own_row)))
				if not MapManors.province_of(repo, cell, state) in melee_region.split("|"): continue
			result.pairs.append(pair)
			rows[pair.slot] = int(pair.count)
		for count: int in rows.values(): result.melee += count
		result.reason = "Close defence at physical contact: %d of %d; fire suppressed" % [result.melee, fit]
		return result
	if action.kind != "attack" or share(repo, state, unit) <= 0:
		result.reason = "Only an attacking ranged-equipped unit fires (%s)" % action.kind
		return result
	if battle.get("reserves", {}).has(unit) and String(action.get("task_id", "")) == "":
		result.reason = "An uncommitted reserve does not fire"
		return result
	var grid := MarchPath.of_pack(repo)
	if not BodyMotion._loco_grid_ok(grid): return _fire_failure(own_id, unit, "Fire requires valid land terrain")
	var axis := Vector2i((WarFront.facing_vector(int(battle.get("group_facing", {}).get(unit, 0))) * 1000).round())
	var radius := int(BattleGroups.piece(repo, state, unit).get("radius_m", -1))
	if radius <= 0: return _fire_failure(own_id, unit, "Fire requires the shooter's measured radius")
	var friends: Array = []
	var fields: Array = [[battle, side]] if other_id == own_id else [[battle, side], [opponents, friendly]]
	for pair: Array in fields:
		for member: String in pair[0][pair[1]]:
			for row: Dictionary in pair[0].groups.get(member, []):
				if int(row.count) > 0:
					var blocker_radius := int(BattleGroups.piece(repo, state, member).get("radius_m", -1))
					if blocker_radius <= 0: return _fire_failure(own_id, unit, "Fire requires every blocker's measured radius")
					friends.append({"unit": member, "slot": int(row.slot), "x_m": row.x_m, "y_m": row.y_m, "radius_m": blocker_radius})
	var reasons: Array[String] = []
	var region := String(action.get("pursuit_region", ""))
	var pairs: Array = []
	var firing := 0
	for row: Dictionary in battle.groups[unit]:
		if int(row.count) <= 0: continue
		var from := point(row)
		var blockers: Array = friends.filter(func(f: Dictionary) -> bool: return not (f.unit == unit and f.slot == int(row.slot)))
		if region != "" and not MapManors.province_of(repo, MapEconomy.cell_at(repo, ArmySystem.metres_to_pack(repo, from)), state) in region.split("|"):
			if not "Outside the received pursuit region" in reasons: reasons.append("Outside the received pursuit region")
			continue
		var fired := false
		for foe: String in foes:
			var why := _fire_barred(repo, state, battle, opponents, side, other, unit, foe, designated, sight, String(action.get("pursuit_target", "")))
			if not why.is_empty():
				if not why in reasons: reasons.append(why)
				continue
			var foe_radius := int(BattleGroups.piece(repo, state, foe).get("radius_m", -1))
			if foe_radius <= 0: return _fire_failure(own_id, unit, "Fire requires the target's measured radius")
			for enemy: Dictionary in opponents.groups.get(foe, []):
				if int(enemy.count) <= 0: continue
				var to := point(enemy)
				var aim := shot(repo, from, to, axis, radius, foe_radius, blockers)
				if not aim.ok: return _fire_failure(own_id, unit, "Invalid fire geometry")
				if not aim.clear: continue
				var terrain := ArmySystem._body_path_terrain(grid, [[from.x, from.y], [to.x, to.y]], 0)
				if not terrain.is_empty():
					if not terrain in reasons: reasons.append(terrain)
					continue
				pairs.append({"unit": unit, "slot": int(row.slot), "target_unit": foe, "target_slot": int(enemy.slot),
					"count": int(row.count), "target_count": int(enemy.count), "kind": "fire",
					"reason": "Clear direct fire within reach and cone over open ground"})
				fired = true
		if fired: firing += int(row.count)
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return UnitBodies._battle_pair_less([a.unit, a.slot, a.target_unit, a.target_slot, a.kind],
			[b.unit, b.slot, b.target_unit, b.target_slot, b.kind]))
	result.firing = firing
	result.pairs = pairs
	result.reason = "Direct fire: %d of %d fit personnel" % [firing, fit]
	if not reasons.is_empty(): result.reason += "; " + "; ".join(reasons)
	return result


## The original per-target fire filters, with both fields' (and absorbed sources') party terms.
static func _fire_barred(repo: DataRepository, state: GameState, battle: Dictionary, opponents: Dictionary,
		side: String, other: String, unit: String, foe: String, designated: String, sight: int, pursuit_target := "") -> String:
	if designated != "" and designated != foe: return "A received designated target restricts fire"
	if not BattleSystem._can_fight(repo, state, foe) or bool(UnitBodies._entry(state, foe).get("captured", false)):
		return "Captured or incapable targets are not fired upon"
	var legal := BattleRules.legal_actions(repo, state, int(battle.id), side, unit, foe)
	for field: Dictionary in [battle, opponents]:
		if BattleRules._binds(field, "ceasefire", "protect", state.absolute_day(), [unit], foe): legal.erase("attack")
		if BattleRules._binds(field, "safe_withdrawal", "protect", state.absolute_day(), [unit], foe) \
			or BattleRules._binds(field, "tactics", "restrained", state.absolute_day(), [unit], foe): legal.erase("pursue")
	if not "attack" in legal: return "Received law or agreement bars fire"
	var withdrawing: bool = BattleSystem.unit_action(repo, state, opponents, foe).kind == "retreat"
	if withdrawing and not "pursue" in legal: return "Protected or unlawful pursuit of a withdrawing target"
	if withdrawing and pursuit_target != "" and pursuit_target != foe: return "Received pursuit names another target"
	var seen := BattleSystem._at_m(repo, state, foe) - BattleSystem._at_m(repo, state, unit)
	if seen.length_squared() > sight * sight: return "Target beyond local sight"
	return ""


static func _fire_failure(battle_id: int, unit: String, reason: String) -> Dictionary:
	return {"status": "error", "reason": reason, "error": reason, "battle_id": battle_id, "unit": unit,
		"fit": 0, "firing": 0, "melee": 0, "pairs": []}
