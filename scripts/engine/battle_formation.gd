class_name BattleFormation
extends RefCounted

const DEFAULT := "double_rank"

static func ensure(battle: Dictionary) -> void:
	if not battle.has("formations"):
		battle["formations"] = {}
	for side: String in BattleSystem.SIDES:
		if not battle["formations"].has(side):
			battle["formations"][side] = {"current": DEFAULT, "previous": DEFAULT, "target": DEFAULT,
				"progress": 0, "required_progress": 0, "disorder_until": 0,
				"last_progress_day": -1, "reason": "Initial compact deployment", "order_id": -1}


static func of_unit(state: GameState, code: String) -> String:
	var battle := BattleSystem.battle_of(state, code)
	if battle.is_empty():
		return ""
	for side: String in BattleSystem.SIDES:
		if code in battle[side]:
			return String(_deployment(battle, side, code).get("current", DEFAULT))
	return ""


static func _deployment(battle: Dictionary, side: String, unit := "") -> Dictionary:
	return battle.get("unit_formations", {}).get(unit, battle.get("formations", {}).get(side, {}))


static func context(repo: DataRepository, state: GameState, battle: Dictionary, side: String, unit := "") -> Dictionary:
	var out := {"width_m": 0, "terrain": "", "centre": "", "arms": [],
		"morale": 100, "training": 100, "flanked": false, "missiles": false}
	var narrow: PackedStringArray = String(repo.battle_formations.get("line", {}).get("narrow_terrains", "")).split("|", false)
	var place := Vector2i(int(battle["place_x_m"]), int(battle["place_y_m"]))
	var members: Array = battle[side] if unit == "" else [unit]
	for code: String in members:
		var reg := ArmySystem.regiment(repo, code, state)
		var entry := BattleSystem._stored(state, code)
		var terrain := ArmySystem.terrain_of(repo, reg, state)
		if out["terrain"] == "" or terrain in narrow:
			out["terrain"] = terrain
		out["arms"].append(MapObjects.regiment_arm(repo, reg))
		out["morale"] = mini(int(out["morale"]), int(entry.get("morale", 0)))
		out["training"] = mini(int(out["training"]), int(entry.get("training", 0)))
		if ArmySystem.wounded_count(repo, state, code) > 0:
			out["centre"] = "wounded:" + code
		if not ArmySystem.is_foe(state, code) and Vector2(KingSystem.position(state)).distance_to(Vector2(place)) <= repo.bal("king_command_radius_m"):
			out["centre"] = "king"
	var other := "def" if side == "att" else "att"
	var reach := float(repo.bal("battle_group_contact_m"))
	var frontal := cos(deg_to_rad(float(repo.bal("battle_flank_front_half_deg"))))
	for code: String in battle[other]:
		var reg := ArmySystem.regiment(repo, code, state)
		for member: String in members:
			if bool(out["flanked"]):
				break
			var facing := WarFront.facing_vector(int(battle.get("group_facing", {}).get(member, 0)))
			for own: Dictionary in battle.get("groups", {}).get(member, []):
				if bool(out["flanked"]):
					break
				for incoming: Dictionary in battle.get("groups", {}).get(code, []):
					if incoming["role"] != "front":
						continue
					var offset := Vector2(int(incoming["x_m"]) - int(own["x_m"]), int(incoming["y_m"]) - int(own["y_m"]))
					if offset.length_squared() > 0.0 and BattleGroups.in_reach(repo, state, member, own, code, incoming, int(reach)) \
							and facing.dot(offset.normalized()) < frontal:
						out["flanked"] = true
						break
		if MapObjects.regiment_arm(repo, reg) in ["archers", "artillery"]:
			out["missiles"] = true
	return out


## Owner R-H (2026-11-13; design 2026-10-25 §2 rules 1-2): a unit has no
## internal tactical formation, so no formation order is ever accepted and no
## deployment changes a battle's odds. Saved formation records stay readable.
const RETIRED := "Units hold one compact block; tactical formations are retired."


static func refusal(repo: DataRepository, state: GameState, battle_id: int, side: String, _formation: String, unit := "") -> String:
	var battle := BattleSystem.battle_by_id(state, battle_id)
	if battle.is_empty() or not side in BattleSystem.SIDES or (battle[side] as Array).is_empty():
		return "The army is no longer on this battlefield."
	if unit != "" and (not unit in battle[side] or not BattleSystem._can_fight(repo, state, unit)
			or bool(BattleSystem._stored(state, unit).get("captured", false))):
		return "The unit is no longer available on this battlefield."
	return RETIRED


## Shape only; views own spacing, rotation, ink and figure-count tiers.
static func slots(formation: String, figures: int, frontage_permille := 1000) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in figures:
		match formation:
			"line":
				var columns := maxi(1, ceili(float(figures * frontage_permille) / 1000.0))
				@warning_ignore("integer_division")
				out.append(Vector2(float(i % columns) - float(columns - 1) / 2.0, i / columns))
			"wedge":
				var rank := ceili(float(i) / 2.0)
				out.append(Vector2(rank * (-1 if i % 2 else 1), rank))
			"diamond":
				if i == 0:
					out.append(Vector2.ZERO)
				else:
					var ring := float(ceili(float(i) / 4.0))
					out.append([Vector2(0, -ring), Vector2(ring, 0), Vector2(0, ring), Vector2(-ring, 0)][(i - 1) % 4])
			_:
				out.append(Vector2(float(i / 2) - float(ceili(float(figures) / 2.0) - 1) / 2.0, i % 2))
	return out
