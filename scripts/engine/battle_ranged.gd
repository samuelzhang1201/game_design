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


static func touching(repo: DataRepository, battle: Dictionary, code: String) -> bool:
	var side := BattleRules.side_of(battle, code)
	if side == "":
		return false
	var reach := int(repo.bal("battle_group_contact_m"))
	for row: Dictionary in battle.get("groups", {}).get(code, []):
		for foe: String in battle["def" if side == "att" else "att"]:
			for other: Dictionary in battle.get("groups", {}).get(foe, []):
				var d := point(other) - point(row)
				if int(row["count"]) > 0 and int(other["count"]) > 0 and d.length_squared() <= reach * reach:
					return true
	return false


## Inclusive reach and cone edge; a friendly disc tangent to the open segment blocks.
static func clear_shot(repo: DataRepository, from: Vector2i, to: Vector2i,
		facing: Vector2i, friends: Array[Vector2i]) -> bool:
	var d := to - from
	var length_sq := d.length_squared()
	var reach := int(repo.bal("battle_ranged_reach_m"))
	var close := int(repo.bal("battle_group_contact_m"))
	if length_sq <= close * close or length_sq > reach * reach:
		return false
	var forward := d.x * facing.x + d.y * facing.y
	var cross := d.x * facing.y - d.y * facing.x
	if forward <= 0 or absi(cross) * 1000 > forward * int(repo.bal("battle_ranged_cone_permille")):
		return false
	var radius := int(repo.bal("battle_ranged_block_radius_m"))
	for at: Vector2i in friends:
		var offset := at - from
		var along := offset.x * d.x + offset.y * d.y
		if along <= 0:
			if offset.length_squared() < radius * radius:
				return false
			continue
		if along >= length_sq:
			if (at - to).length_squared() < radius * radius:
				return false
			continue
		var area := offset.x * d.y - offset.y * d.x
		if area * area <= radius * radius * length_sq:
			return false
	return true


## Count each group once, against a lawful locally seen opponent. No remote fallback.
static func counts(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		target := "") -> Dictionary:
	var out := {"firing": 0, "melee": 0, "fit": 0}
	var rows: Array = battle.get("groups", {}).get(code, [])
	for row: Dictionary in rows:
		out["fit"] += int(row["count"])
	var side := BattleRules.side_of(battle, code)
	if side == "" or rows.is_empty() or not BattleSystem._can_fight(repo, state, code) \
			or bool(BattleSystem._stored(state, code).get("captured", false)):
		return out
	var action := BattleSystem.unit_action(repo, state, battle, code)
	var in_melee := touching(repo, battle, code)
	if action["kind"] == "retreat" or (not in_melee and battle.get("reserves", {}).has(code) and action["task_id"] == ""):
		return out
	var task := BattleTaskSystem.current(state, code)
	var designated := String(task.get("request", {}).get("target_unit", "")) if action["task_id"] != "" else ""
	var other := "def" if side == "att" else "att"
	var close := int(repo.bal("battle_group_contact_m"))
	var sight := int(repo.bal("ai_sight_km" if ArmySystem.is_foe(state, code) else "player_sight_km") * 1000)
	var axis := Vector2i((WarFront.facing_vector(int(battle.get("group_facing", {}).get(code, 0))) * 1000).round())
	var friends: Array[Vector2i] = []
	for member: String in battle[side]:
		for row: Dictionary in battle.get("groups", {}).get(member, []):
			if int(row["count"]) > 0:
				friends.append(point(row))
	for row: Dictionary in rows:
		var from := point(row)
		var blockers: Array[Vector2i] = friends.duplicate()
		blockers.erase(from)  # exclude this shooter, retaining any overlapping other group
		var inside := true
		var region := String(action.get("pursuit_region", ""))
		if region != "":
			var at := ArmySystem.metres_to_pack(repo, from)
			inside = MapManors.province_of(repo, MapEconomy.cell_at(repo, at), state) in region.split("|")
		for foe: String in battle[other]:
			if target != "" and target != foe:
				continue
			var self_defence: bool = in_melee and BattleSystem.unit_action(repo, state, battle, foe)["kind"] == "attack"
			if not self_defence and (not inside or (designated != "" and designated != foe)):
				continue
			if not BattleSystem._can_fight(repo, state, foe) or bool(BattleSystem._stored(state, foe).get("captured", false)):
				continue
			var legal := BattleRules.legal_actions(repo, state, int(battle["id"]), side, code, foe)
			if not "attack" in legal:
				continue
			if (BattleOrders.kind(battle, other) == "retreat" or bool(BattleSystem._stored(state, foe).get("battle_retreat", false))) \
					and not "pursue" in legal:
				continue
			var visible := BattleSystem._at_m(repo, state, foe) - BattleSystem._at_m(repo, state, code)
			if visible.length_squared() > sight * sight:
				continue
			var engaged := false
			for enemy: Dictionary in battle.get("groups", {}).get(foe, []):
				if int(enemy["count"]) <= 0:
					continue
				var to := point(enemy)
				if in_melee:
					if row["role"] == "front" and (to - from).length_squared() <= close * close:
						out["melee"] += int(row["count"])
						engaged = true
				elif clear_shot(repo, from, to, axis, blockers):
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


## Preserve non-ranged threat; ranged personnel contribute only where they can fight.
static func incoming_permille(repo: DataRepository, state: GameState, battle: Dictionary,
		side: String, target := "") -> int:
	# Arithmetic adapters/old records retain their context until production refreshes groups.
	if not battle.has("groups"):
		return 1000
	var total := 0
	var active := 0
	for code: String in battle["def" if side == "att" else "att"]:
		var fit := ArmySystem.fit_count(repo, state, code)
		var ranged := share(repo, state, code)
		var factor := active_permille(counts(repo, state, battle, code, target)) if ranged > 0 else 1000
		total += fit
		@warning_ignore("integer_division")
		active += fit * (1000 - ranged + ranged * factor / 1000)
	@warning_ignore("integer_division")
	return active / total if total > 0 else 1000
