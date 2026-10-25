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


static func touching(repo: DataRepository, battle: Dictionary, code: String, state: GameState = null) -> bool:
	var side := BattleRules.side_of(battle, code)
	if side == "":
		return false
	for row: Dictionary in battle.get("groups", {}).get(code, []):
		for foe: String in battle["def" if side == "att" else "att"]:
			var reach := BattleGroups.contact_reach(repo, state, battle, code, foe)
			for other: Dictionary in battle.get("groups", {}).get(foe, []):
				var d := point(other) - point(row)
				if int(row["count"]) > 0 and int(other["count"]) > 0 and d.length_squared() <= reach * reach:
					return true
	return false


## Inclusive reach and cone edge; a friendly disc tangent to the open segment blocks.
static func clear_shot(repo: DataRepository, from: Vector2i, to: Vector2i,
		facing: Vector2i, friends: Array[Vector2i], footprints := Vector2i.ZERO,
		friend_radii: Array[int] = []) -> bool:
	var d := to - from
	var length_sq := d.length_squared()
	var reach := int(repo.bal("battle_ranged_reach_m")) + footprints.x + footprints.y
	var close := int(repo.bal("battle_group_contact_m")) + footprints.x + footprints.y
	if length_sq <= close * close or length_sq > reach * reach:
		return false
	var forward := d.x * facing.x + d.y * facing.y
	var cross := d.x * facing.y - d.y * facing.x
	if forward <= 0 or absi(cross) * 1000 > forward * int(repo.bal("battle_ranged_cone_permille")):
		return false
	var length := sqrt(float(length_sq))
	for i: int in friends.size():
		var radius := maxi(int(repo.bal("battle_ranged_block_radius_m")), friend_radii[i] if i < friend_radii.size() else 0)
		var offset := friends[i] - from
		var along := offset.x * d.x + offset.y * d.y
		# Relative integer geometry avoids world-coordinate Vector2 precision changing tangency.
		if float(along) <= footprints.x * length:
			var distance_sq := float(offset.length_squared()) + float(footprints.x * footprints.x) - 2.0 * footprints.x * float(along) / length
			if distance_sq < radius * radius: return false
		elif float(along) >= float(length_sq) - footprints.y * length:
			var end_offset := friends[i] - to
			var end_along := end_offset.x * d.x + end_offset.y * d.y
			var distance_sq := float(end_offset.length_squared()) + float(footprints.y * footprints.y) + 2.0 * footprints.y * float(end_along) / length
			if distance_sq < radius * radius: return false
		else:
			var area := offset.x * d.y - offset.y * d.x
			if float(area) * float(area) <= float(radius * radius) * float(length_sq): return false

	return true


## Count each group once. An optional other field retains both sources' commands and terms.
static func counts(repo: DataRepository, state: GameState, battle: Dictionary, code: String,
		target := "", opposing_battle: Dictionary = {}) -> Dictionary:
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
	if action["kind"] == "retreat" or (not in_melee and battle.get("reserves", {}).has(code) and action["task_id"] == ""):
		return out
	var task := BattleTaskSystem.current(state, code)
	var designated := String(task.get("request", {}).get("target_unit", "")) if action["task_id"] != "" else ""
	var opponents := battle if opposing_battle.is_empty() else opposing_battle.duplicate(true)
	var friendly := side if opposing_battle.is_empty() else BattleSystem._side_for(state, opponents, code)
	var other := "def" if friendly == "att" else "att"
	var sight := int(repo.bal("ai_sight_km" if ArmySystem.is_foe(state, code) else "player_sight_km") * 1000)
	var axis := Vector2i((WarFront.facing_vector(int(battle.get("group_facing", {}).get(code, 0))) * 1000).round())
	var friends: Array[Dictionary] = []
	for field: Dictionary in [battle] if opposing_battle.is_empty() else [battle, opponents]:
		for member: String in field[side if is_same(field, battle) else friendly]:
			var radius := BattleGroups.group_radius(repo, state, field, member) if ArmyGround.clearance_on(repo) else 0
			for row: Dictionary in field.get("groups", {}).get(member, []):
				if int(row["count"]) > 0:
					friends.append({"row": row, "radius": radius})
	for row: Dictionary in rows:
		if int(row["count"]) <= 0:
			continue
		var from := point(row)
		var blockers: Array[Vector2i] = []
		var blocker_radii: Array[int] = []
		for friend: Dictionary in friends:
			if is_same(friend.row, row): continue
			blockers.append(point(friend.row))
			blocker_radii.append(int(friend.radius))
		var inside := true
		var region := String(action.get("pursuit_region", ""))
		if region != "":
			var at := ArmySystem.metres_to_pack(repo, from)
			inside = MapManors.province_of(repo, MapEconomy.cell_at(repo, at), state) in region.split("|")
		for foe: String in opponents[other]:
			if target != "" and target != foe:
				continue
			var self_defence: bool = in_melee and BattleSystem.unit_action(repo, state, opponents, foe)["kind"] == "attack"
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
			if withdrawing and not "pursue" in legal:
				continue
			var visible := BattleSystem._at_m(repo, state, foe) - BattleSystem._at_m(repo, state, code)
			if visible.length_squared() > sight * sight:
				continue
			var close := BattleGroups.contact_reach(repo, state, battle, code, foe, opponents)
			var footprints := Vector2i(BattleGroups.group_radius(repo, state, battle, code), BattleGroups.group_radius(repo, state, opponents, foe)) if ArmyGround.clearance_on(repo) else Vector2i.ZERO
			var engaged := false
			for enemy: Dictionary in opponents.get("groups", {}).get(foe, []):
				if int(enemy["count"]) <= 0:
					continue
				var to := point(enemy)
				if in_melee:
					if row["role"] == "front" and (to - from).length_squared() <= close * close:
						out["melee"] += int(row["count"])
						engaged = true
				elif clear_shot(repo, from, to, axis, blockers, footprints, blocker_radii):
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
