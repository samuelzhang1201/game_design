class_name CourierCard
extends RefCounted
## A courier's fact card for the left column (spec 2026-09-27-courier-core §2,
## invariant 10), shaped like MapObjects' cards: title, subtitle, painting,
## fields. The painting is courier_art.csv's, omitted until sub-project D
## installs one.

const GROUND := {"road": "On the road", "trail": "On a trail", "offroad": "Across country", "sea": "By sea"}


static func courier(state: GameState, id: int) -> Dictionary:
	if state == null:
		return {}
	for c: Dictionary in state.couriers:
		if int(c["id"]) == id:
			return c
	return {}


static func title(repo: DataRepository, state: GameState, id: int) -> String:
	var c := courier(state, id)
	if c.is_empty():
		return "A courier"
	return "Courier to " + String(ArmySystem.regiment(repo, String(c["target"])).get("label", c["target"]))


## Calendar's date of an absolute day.
static func date_of(abs_day: int) -> String:
	var d := maxi(abs_day, 1) - 1
	@warning_ignore("integer_division")  # whole months
	return Calendar.date_string(d / Calendar.DAYS_PER_TICK + 1, d % Calendar.DAYS_PER_TICK + 1)


## "Rain ×0.85", or just "Clear": the province and manor cards say what the
## factor is for; a courier's card is about his ride.
static func weather_short(repo: DataRepository, kind: String) -> String:
	var permille := Weather.speed_permille(repo, kind)
	if permille >= 1000:
		return Weather.label_of(repo, kind)
	return "%s ×%.2f" % [Weather.label_of(repo, kind), float(permille) / 1000.0]


static func card(repo: DataRepository, state: GameState, id: int) -> Dictionary:
	var c := courier(state, id)
	if c.is_empty():
		return {}
	var realm := repo.resolve_realm("player_realm")
	var kind := String(c["kind"])
	var order := String((c["order"] as Dictionary).get("action_code", ""))
	var here := Vector2i(int(c["x_m"]), int(c["y_m"]))
	var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), state.absolute_day())
	var path: Array = c["path"]
	var ground := String(path[0][2]) if not path.is_empty() else "offroad"
	var days := CourierSystem.days_left(repo, state, c)
	return {
		"kind": "courier", "id": int(c["id"]), "title": title(repo, state, id),
		"subtitle": "%s courier of %s" % [kind.capitalize(),
			String((repo.kingdoms.get(realm, {}) as Dictionary).get("label", ""))],
		"kingdom_code": realm, "initial": "C",
		"painting": String((repo.courier_art.get(kind, {}) as Dictionary).get("painting", "")),
		"stats": [], "rates": [], "features": [], "production": [], "actions": [],
		"fields": [
			# short: the fixed left column wraps a long value line by line, and
			# the title already names the regiment (fix round 1, 2026-09-28)
			["Carrying", "Orders to march" if order == "ARMY_MARCH" else "Orders to stand"],
			["Rode out", date_of(int(c["issued"]))],
			["Arrives", "in about %d day%s" % [days, "" if days == 1 else "s"]],
			["Ground", String(GROUND.get(ground, ground))],
			["Weather", weather_short(repo, wx)],
		],
		"known": "courier",
		"center": ArmySystem.metres_to_pack(repo, here),
		"ask": "",
	}
