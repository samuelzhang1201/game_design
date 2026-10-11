class_name CourierCard
extends RefCounted
## A courier's fact card for the left column (spec 2026-09-27-courier-core §2,
## invariant 10), shaped like MapObjects' cards: title, subtitle, painting,
## fields. The painting is courier_art.csv's, omitted until sub-project D
## installs one.

const GROUND := {"road": "On the road", "trail": "On a trail", "offroad": "Across country", "river": "On the river", "sea": "By water"}


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
	if String(c["kind"]) == CourierSystem.SPY:
		return "Spy bound for " + Intel.place_label(repo, state, ArmySystem.metres_to_pack(repo,
			Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"]))))
	if String(CourierSystem.first_order(c).get("action_code", "")) == LawSystem.ACTION:
		return "Decree to " + LawSystem.place_label(repo, state, String(c["target"]))
	var to_town := String(CourierSystem.first_order(c).get("to_town", ""))
	if to_town != "":
		return "Courier to " + String((repo.burgs.get(to_town, {}) as Dictionary).get("label", to_town))
	return "Courier to " + String(ArmySystem.regiment(repo, String(c["target"]), state).get("label", c["target"]))


## What a courier carries, an order after another in the sequence they run
## ("Supply orders for … · Orders to carry 10 days · Orders to march").
static func carrying_words(repo: DataRepository, state: GameState, c: Dictionary) -> String:
	var out: PackedStringArray = []
	for o: Dictionary in CourierSystem.orders_of(c):
		var order := String(o.get("action_code", ""))
		var said := "Orders to march" if order == "ARMY_MARCH" else "Orders to stand"
		if order == "ARMY_STANCE":
			var stance := String(o.get("stance", ""))
			said = "Stance orders: " + String((repo.battle_stances.get(stance, {}) as Dictionary).get("label", stance))
		elif order == "ARMY_SEAT":
			said = "Orders to take the seat"
		elif order == "SUPPLY_CARRY_SET":
			said = "Orders to carry %d days" % int(o.get("days", 0))
		elif order.begins_with("SUPPLY_"):
			said = "Supply orders for " + String(ArmySystem.regiment(repo, String(c["target"]), state).get("label", c["target"]))
		elif order == LawSystem.ACTION:
			said = decree_words(repo, o)
		out.append(said)
	return " · ".join(out)


## What a decree's courier carries: "Decree: <law> → <value>".
static func decree_words(repo: DataRepository, order: Dictionary) -> String:
	var law := String(order.get("law", ""))
	return "Decree: %s → %s" % [String((repo.laws.get(law, {}) as Dictionary).get("label", law)),
		LawSystem.value_label(repo, String(order.get("value", "")))]


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


## The card's painting: the foul-weather one when the weather here slows a
## rider to courier_paint_foul_permille or less and that art is installed,
## else the kind's own (spec 2026-09-28-courier-art §4).
static func painting_for(repo: DataRepository, kind: String, weather: String) -> String:
	var own := GameArt.path(GameArt.COURIER_PAINTINGS, kind)
	var foul := GameArt.path(GameArt.COURIER_PAINTINGS, "foul")
	var row: Dictionary = repo.weather_kinds.get(weather, {})
	if foul != "" and not row.is_empty() \
			and int(row.get("speed_permille", 1000)) <= int(repo.bal("courier_paint_foul_permille")):
		return foul
	return own


static func card(repo: DataRepository, state: GameState, id: int) -> Dictionary:
	var c := courier(state, id)
	if c.is_empty():
		return {}
	var realm := repo.resolve_realm("player_realm")
	var kind := String(c["kind"])
	var here := Vector2i(int(c["x_m"]), int(c["y_m"]))
	var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), state.absolute_day())
	var path: Array = c["path"]
	var ground := String(path[0][2]) if not path.is_empty() else "offroad"
	var days := CourierSystem.days_left(repo, state, c)
	var is_spy := kind == CourierSystem.SPY
	var carrying := carrying_words(repo, state, c)
	return {
		"kind": "courier", "id": int(c["id"]), "title": title(repo, state, id),
		"subtitle": ("Spy of %s" % String((repo.kingdoms.get(realm, {}) as Dictionary).get("label", ""))) if is_spy \
			else "%s courier of %s" % [kind.capitalize(),
			String((repo.kingdoms.get(realm, {}) as Dictionary).get("label", ""))],
		"kingdom_code": realm, "initial": "C",
		"painting": painting_for(repo, kind, wx),
		"stats": [], "rates": [], "features": [], "production": [], "actions": [],
		"fields": [
			# short: the fixed left column wraps a long value line by line, and
			# the title already names the regiment (fix round 1, 2026-09-28)
			["Carrying", "A spy's errand" if is_spy else carrying],
			["Ordered", date_of(int(c["issued"]))],
			["Arrives", "in about %d day%s" % [days, "" if days == 1 else "s"]],
			["Ground", String(GROUND.get(ground, ground))],
			["Weather", weather_short(repo, wx)],
		],
		"known": "courier",
		"center": ArmySystem.metres_to_pack(repo, here),
		"ask": "",
	}
