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
					if offset.length_squared() > 0.0 and offset.length_squared() <= reach * reach \
							and facing.dot(offset.normalized()) < frontal:
						out["flanked"] = true
						break
		if MapObjects.regiment_arm(repo, reg) in ["archers", "artillery"]:
			out["missiles"] = true
	return out


static func refusal(repo: DataRepository, state: GameState, battle_id: int, side: String, formation: String, unit := "") -> String:
	var battle := BattleSystem.battle_by_id(state, battle_id)
	if battle.is_empty() or not side in BattleSystem.SIDES or (battle[side] as Array).is_empty():
		return "The army is no longer on this battlefield."
	if unit != "" and (not unit in battle[side] or not BattleSystem._can_fight(repo, state, unit)
			or bool(BattleSystem._stored(state, unit).get("captured", false))):
		return "The unit is no longer available on this battlefield."
	if not repo.battle_formations.has(formation):
		return "Unknown formation."
	var row: Dictionary = repo.battle_formations[formation]
	var ctx := context(repo, state, battle, side, unit)
	if int(ctx["morale"]) < int(row["min_morale"]) or int(ctx["training"]) < int(row["min_training"]):
		return "The army lacks the morale or training to form this deployment."
	var required := String(row["required_arms"]).split("|", false)
	if not required.is_empty() and not ctx["arms"].any(func(arm: String) -> bool: return arm in required):
		return "The required fighting arm is absent."
	return ""


## Received deployment primitive; the caller owns warrant authority, law and costs.
static func request(repo: DataRepository, state: GameState, battle_id: int, side: String, formation: String, unit := "") -> Dictionary:
	var why := refusal(repo, state, battle_id, side, formation, unit)
	if why != "":
		return {"status": "invalid", "reason": why}
	var battle := BattleSystem.battle_by_id(state, battle_id)
	ensure(battle)
	if unit != "":
		if not battle.has("unit_formations"):
			battle["unit_formations"] = {}
		if not battle["unit_formations"].has(unit):
			battle["unit_formations"][unit] = battle["formations"][side].duplicate(true)
	var change := _deployment(battle, side, unit)
	if String(change["target"]) == formation:
		return {"status": "unchanged", "reason": "This formation is already ordered."}
	var row: Dictionary = repo.battle_formations[formation]
	change["previous"] = change["current"]
	change["target"] = formation
	change["progress"] = 0
	change["required_progress"] = int(row["change_progress"])
	change["disorder_until"] = maxi(int(change["disorder_until"]), state.absolute_day() + int(row["disorder_days"]))
	change["reason"] = "Received order to form " + String(row["label"])
	return {"status": "preparing", "reason": change["reason"]}


static func advance(repo: DataRepository, state: GameState, battle: Dictionary) -> void:
	ensure(battle)
	for side: String in BattleSystem.SIDES:
		_advance_change(repo, state, battle["formations"][side], battle[side])
	var units: Array = battle.get("unit_formations", {}).keys()
	units.sort()
	for unit: String in units:
		if BattleRules.side_of(battle, unit) == "" or not BattleSystem._can_fight(repo, state, unit) \
				or bool(BattleSystem._stored(state, unit).get("captured", false)):
			continue
		_advance_change(repo, state, battle["unit_formations"][unit], [unit])


static func _advance_change(repo: DataRepository, state: GameState, change: Dictionary, members: Array) -> void:
	if int(change["last_progress_day"]) == state.absolute_day():
		return
	change["last_progress_day"] = state.absolute_day()
	if change["current"] == change["target"]:
		return
	var weighted := 0
	var fit := 0
	for code: String in members:
		var heads := ArmySystem.fit_count(repo, state, code)
		fit += heads
		weighted += heads * int(MilitaryQuality.profile(repo, state, code)["discipline_permille"])
	@warning_ignore("integer_division")
	var step := weighted / fit if fit > 0 else 0
	change["progress"] = mini(int(change["required_progress"]), int(change["progress"]) + step)
	if int(change["progress"]) >= int(change["required_progress"]):
		change["current"] = change["target"]


## One source per modifier, with whole per-mille interpolation on narrow ground.
static func evaluate(repo: DataRepository, formation: String, ctx: Dictionary, attacking: bool) -> Dictionary:
	var row: Dictionary = repo.battle_formations.get(formation, {})
	if row.is_empty():
		return {"factors": [], "reason": "No tactical deployment", "frontage_m": 0}
	var width := int(ctx.get("width_m", 0))
	if width <= 0:
		width = int(row["frontage_m"])
		if String(ctx.get("terrain", "")) in String(row["narrow_terrains"]).split("|", false):
			width = int(row["narrow_width_m"])
	width = mini(width, int(row["frontage_m"]))
	var factor := int(row["attack_permille"] if attacking else row["defence_permille"])
	@warning_ignore("integer_division")
	factor = 1000 + (factor - 1000) * width / int(row["frontage_m"])
	var reason := String(row["label"])
	if int(row["centre_required"]) == 1 and String(ctx.get("centre", "")) == "":
		factor = mini(factor, 1000)
		reason += ": insufficient benefit; no king, wounded or train to protect"
	var factors: Array[Dictionary] = [{"source": "formation:deployment", "permille": factor, "reason": reason}]
	if bool(ctx.get("flanked", false)):
		var flank := int(row["flank_permille"])
		if int(row["centre_required"]) == 1 and String(ctx.get("centre", "")) == "":
			flank = mini(flank, 1000)
		factors.append({"source": "formation:flank", "permille": flank, "reason": "Enemy front groups contact the side or rear"})
	if not attacking and bool(ctx.get("missiles", false)):
		factors.append({"source": "formation:missiles", "permille": int(row["missile_permille"]), "reason": "Exposed to ranged fire"})
	return {"factors": factors, "reason": reason, "frontage_m": width}


static func effects(repo: DataRepository, state: GameState, battle: Dictionary, side: String, attacking: bool, unit := "") -> Dictionary:
	var change := _deployment(battle, side, unit)
	if change.is_empty():
		return {"factors": []}
	var recipient := unit if battle.get("unit_formations", {}).has(unit) else ""
	var result := evaluate(repo, String(change["current"]), context(repo, state, battle, side, recipient), attacking)
	if state.absolute_day() <= int(change["disorder_until"]):
		result["factors"].append({"source": "formation:disorder",
			"permille": int(repo.battle_formations[String(change["target"])]["disorder_permille"]),
			"reason": "Exposed while reforming: " + String(change["reason"])})
	return result


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
