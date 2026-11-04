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
	var d := to - from
	var length_sq := d.length_squared()
	var reach := int(repo.bal("battle_ranged_reach_m"))
	var close := int(repo.bal("battle_group_contact_m"))
	var contact := BattleGroupGeometry.pair([from.x, from.y], radius_from, [to.x, to.y], radius_to, close)
	var range_ := BattleGroupGeometry.pair([from.x, from.y], radius_from, [to.x, to.y], radius_to, reach)
	if not contact.ok or not range_.ok or contact.in_reach or not range_.in_reach:
		return false
	var forward := d.x * facing.x + d.y * facing.y
	var cross := d.x * facing.y - d.y * facing.x
	if forward <= 0 or absi(cross) * 1000 > forward * int(repo.bal("battle_ranged_cone_permille")):
		return false
	var blockers: Array = discs.duplicate()
	for at: Vector2i in friends:
		blockers.append({"x_m": at.x, "y_m": at.y, "radius_m": int(repo.bal("battle_ranged_block_radius_m"))})
	for blocker: Dictionary in blockers:
		var hit := BattleGroupGeometry.segment_disc([from.x, from.y], [to.x, to.y],
			[blocker.x_m, blocker.y_m], int(blocker.radius_m))
		if not hit.ok or hit.blocked: return false
	return true


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
