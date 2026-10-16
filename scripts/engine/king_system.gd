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


## Fill the only safe legacy default: the capital bound to this campaign's
## saved world. Old location prose and map selection are not coordinates.
static func ensure(repo: DataRepository, state: GameState) -> void:
	if state.king_state.is_empty():
		state.king_state = initial_state(repo)
