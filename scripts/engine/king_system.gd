class_name KingSystem
extends RefCounted
## The king's physical location, separate from the royal regiment and the
## player's selected screen location (battle-system spec §11).

static func initial_state(repo: DataRepository) -> Dictionary:
	var realm := repo.resolve_realm("player_realm")
	var kingdom: Dictionary = repo.kingdoms.get(realm, {})
	var capital := String(kingdom.get("capital_burg", ""))
	if not repo.burgs.has(capital):
		return {}
	var burg: Dictionary = repo.burgs[capital]
	var metres := ArmySystem.pack_to_metres(repo,
		Vector2(float(burg.get("x", 0.0)), float(burg.get("y", 0.0))))
	return {
		"x_m": metres.x,
		"y_m": metres.y,
		"route": [],
		"follow_code": "",
		"travel_state": "stationary",
		"last_advanced_day": 0,
	}


static func position(state: GameState) -> Vector2i:
	var king: Dictionary = state.king_state
	return Vector2i(int(king.get("x_m", 0)), int(king.get("y_m", 0)))


## Set a route in whole metres. The final point is the destination; all prior
## points are walked in order. A reason is stored with the state transition.
static func set_route(repo: DataRepository, state: GameState, route: Array, reason: String) -> Dictionary:
	if reason.strip_edges().is_empty():
		return {"status": "error", "error": "A reason is required for the king's journey."}
	if route.is_empty():
		return {"status": "error", "error": "The king needs a destination."}
	ensure(repo, state)
	var points: Array = []
	for p: Variant in route:
		if not p is Vector2i:
			return {"status": "error", "error": "King route points must be whole metre coordinates."}
		points.append(p)
	var here := position(state)
	var path := ArmySystem.route_m_of(repo, here, points.slice(0, -1), points.back())
	var king: Dictionary = state.king_state
	king["route"] = MarchRoute.to_pairs(path)
	king["follow_code"] = ""
	king["travel_state"] = "travelling" if not path.is_empty() else "stationary"
	king["reason"] = reason
	return {"status": "ok", "route": king["route"].duplicate(true)}


## Travel to a field regiment, then follow its actual position each day.
static func follow(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or ArmySystem.is_foe(state, code) or not state.regiments.has(code):
		return {"status": "error", "error": "The king can only follow a friendly regiment."}
	var target := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, reg))
	var king := state.king_state
	var points := ArmySystem.route_m_of(repo, position(state), [], target)
	king["route"] = MarchRoute.to_pairs(points)
	king["follow_code"] = code
	king["travel_state"] = "rendezvous" if position(state) != Vector2i(roundi(target.x), roundi(target.y)) else "following"
	king["reason"] = "the king rides to join " + String(reg.get("label", code))
	return {"status": "ok", "travel_state": king["travel_state"]}


## Advance at the royal travel pace once at the end of each absolute day.
static func step_day(repo: DataRepository, state: GameState) -> void:
	ensure(repo, state)
	var king: Dictionary = state.king_state
	var today := state.absolute_day()
	if int(king.get("last_advanced_day", 0)) == today:
		return
	king["last_advanced_day"] = today
	var follow_code := String(king.get("follow_code", ""))
	if follow_code != "" and not ArmySystem.regiment(repo, follow_code, state).is_empty():
		var target := ArmySystem.pack_to_metres(repo,
			ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, follow_code, state)))
		if String(king.get("travel_state", "")) == "following":
			king["x_m"] = target.x
			king["y_m"] = target.y
			return
		if position(state) == Vector2i(roundi(target.x), roundi(target.y)):
			king["travel_state"] = "following"
			king["route"] = []
			return
		if MarchRoute.from_pairs(king.get("route", [])).is_empty():
			king["route"] = MarchRoute.to_pairs(ArmySystem.route_m_of(repo, position(state), [], target))
	else:
		king["follow_code"] = ""
		if String(king.get("travel_state", "")) == "following":
			king["travel_state"] = "stationary"
			return
	var path := MarchRoute.from_pairs(king.get("route", []))
	if path.is_empty():
		king["travel_state"] = "stationary"
		return
	var here := position(state)
	var pace := int(repo.bal("king_travel_km_per_day")) * 1000
	var left := MarchRoute.length_from(here, path)
	var days := int(ceil(left / float(maxi(pace, 1))))
	var step := int(ceil(left / float(maxi(days, 1))))
	if days <= 1:
		king["x_m"] = int(path.back().x)
		king["y_m"] = int(path.back().y)
		king["route"] = []
		king["travel_state"] = "stationary"
		return
	var walked := MarchRoute.walk(here, path, step)
	king["x_m"] = (walked["at"] as Vector2i).x
	king["y_m"] = (walked["at"] as Vector2i).y
	king["route"] = MarchRoute.to_pairs(walked["path"])
	king["travel_state"] = "travelling"


static func present(repo: DataRepository, state: GameState, battle_id: int) -> bool:
	var battle: Dictionary = {}
	for candidate: Dictionary in state.battles:
		if int(candidate.get("id", -1)) == battle_id:
			battle = candidate
			break
	if battle.is_empty():
		return false
	var radius := int(repo.bal("king_command_radius_m"))
	return Vector2(position(state)).distance_to(Vector2i(int(battle.get("place_x_m", 0)),
		int(battle.get("place_y_m", 0)))) <= radius


## A battle's passive royal morale support; derived on read, never stored.
static func morale_support(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or ArmySystem.is_foe(state, code):
		return 0
	var battle := BattleSystem.battle_of(state, code)
	if battle.is_empty() or not present(repo, state, int(battle.get("id", -1))):
		return 0
	return int(repo.bal("king_battle_morale_support"))


## The king withdraws safely without changing the battle or its regiments.
static func safe_departure(repo: DataRepository, state: GameState, battle_id: int) -> Dictionary:
	if not present(repo, state, battle_id):
		return {"status": "error", "error": "The king is not present at this battle."}
	var battle := BattleSystem.battle_by_id(state, battle_id)
	var battle_position := Vector2i(int(battle.get("place_x_m", position(state).x)),
		int(battle.get("place_y_m", position(state).y)))
	var candidates: Array = []
	var realm := repo.resolve_realm("player_realm")
	var burgs: Array = repo.burgs.keys()
	burgs.sort()
	for code: String in burgs:
		var burg: Dictionary = repo.burgs[code]
		if MapOwnership.owner_of(repo, state, String(burg.get("province_code", ""))) != realm:
			continue
		var px := Vector2(float(burg.get("x", 0.0)), float(burg.get("y", 0.0)))
		var metres := ArmySystem.pack_to_metres(repo, px)
		var route := ArmySystem.route_m_of(repo, battle_position, [], metres)
		var length := MarchRoute.length_from(battle_position, route)
		if length > 0.0:
			candidates.append({"distance": int(ceil(length)), "code": code, "route": route})
	var king: Dictionary = state.king_state
	king["x_m"] = battle_position.x
	king["y_m"] = battle_position.y
	king["follow_code"] = ""
	king["route"] = []
	king["travel_state"] = "safe_departure"
	king["reason"] = "the king withdraws safely from battle"
	if not candidates.is_empty():
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["distance"]) != int(b["distance"]):
				return int(a["distance"]) < int(b["distance"])
			return String(a["code"]) < String(b["code"]))
		king["route"] = MarchRoute.to_pairs(candidates[0]["route"])
		king["travel_state"] = "safe_departure"
		king["safe_battle_id"] = battle_id
		king["safe_destination"] = String(candidates[0]["code"])
		king["safe_origin_m"] = [battle_position.x, battle_position.y]
	return {"status": "ok"}


## Fill the only safe legacy default: the capital bound to this campaign's
## saved world. Old location prose and map selection are not coordinates.
static func ensure(repo: DataRepository, state: GameState) -> void:
	if state.king_state.is_empty():
		state.king_state = initial_state(repo)
