class_name SupplyLines
extends RefCounted
## Supply lines (owner 2026-10-07, spec docs/superpowers/specs/2026-10-07-army-
## supply-lines-design.md): ONE per regiment at most, from a realm town, over
## the road to where the column stands each day. A line is ORDERED while the
## courier rides to the town, RIDING while its first wagons are on the road,
## then FLOWING — or CUT on a day a hostile regiment stands by its road (no
## rerouting). GameState.supply_lines; whole numbers; regiment code order.

const ORDERED := "ordered"
const RIDING := "riding"
const FLOWING := "flowing"
const CUT := "cut"
const RATES := [800, 1000, 1200]


static func line(state: GameState, code: String) -> Dictionary:
	return state.supply_lines.get(code, {}) if state != null else {}


static func _burg_px(repo: DataRepository, town: String) -> Vector2:
	var b: Dictionary = repo.burgs.get(town, {})
	return Vector2(float(b.get("x", 0)), float(b.get("y", 0)))


## The road from `town` to the regiment, pack px (the courier's road:
## CourierSystem.path_between), the town first and the column last.
static func road_px(repo: DataRepository, state: GameState, code: String, town: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty() or not repo.burgs.has(town):
		return out
	var from := _burg_px(repo, town)
	var to := ArmySystem.position_of(repo, state, reg)
	out.append(from)
	for p: Array in CourierSystem.path_between(repo, from, to):
		out.append(ArmySystem.metres_to_pack(repo, Vector2i(int(p[0]), int(p[1]))))
	if out[out.size() - 1].distance_to(to) > 0.001:
		out.append(to)
	return out


static func road_km(repo: DataRepository, route: PackedVector2Array) -> int:
	var m := 0.0
	for i in range(1, route.size()):
		m += route[i - 1].distance_to(route[i]) * float(ArmySystem.metres_per_pack_px(repo))
	return int(m / 1000.0)


static func wagon_days(repo: DataRepository, km: int) -> int:
	var per := maxi(1, int(repo.bal("supply_wagon_km_per_day")))
	@warning_ignore("integer_division")  # whole days, rounded up
	return maxi(1, (km + per - 1) / per)


## Every realm town -> "" when it may supply `code` now, else why not
## (data/army_supply_orders.csv pick_far).
static func eligibility(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var out: Dictionary = {}
	var max_days := int(repo.bal("supply_point_max_days"))
	var hint := String((repo.army_supply_orders.get("pick_far", {}) as Dictionary).get("hint", ""))
	for town: String in TownStores.realm_towns(repo, state):
		var days := wagon_days(repo, road_km(repo, road_px(repo, state, code, town)))
		out[town] = "" if days <= max_days else hint.format({
			"town": String(repo.burgs[town].get("label", town)), "days": days, "max": max_days})
	return out


## The hostile regiments' positions (data/army_hostile_stances.csv), [[px, kingdom]].
static func _hostiles(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var realm := repo.resolve_realm("player_realm")
	var rows: Array = repo.world_table("military", "regiments").values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["regiment_code"]) < String(b["regiment_code"]))
	for r: Dictionary in rows:
		var k := String(r["kingdom_code"])
		if k == realm or not Intel.stance_of(repo, k) in repo.army_hostile_stances:
			continue
		out.append([ArmySystem.position_of(repo, state, r), k])
	return out


## Where a hostile regiment stands within supply_cut_reach_m of the road:
## {at: the nearest road point (pack px), by: its kingdom}; {} when clear.
static func cut_point(repo: DataRepository, state: GameState, route: PackedVector2Array) -> Dictionary:
	if route.size() < 2:
		return {}
	var reach := float(repo.bal("supply_cut_reach_m")) / float(ArmySystem.metres_per_pack_px(repo))
	for h: Array in _hostiles(repo, state):
		var p: Vector2 = h[0]
		for i in range(1, route.size()):
			var q := Geometry2D.get_closest_point_to_segment(p, route[i - 1], route[i])
			if q.distance_to(p) <= reach:
				return {"at": q, "by": String(h[1])}
	return {}


static func _new_record(town: String, rate: int, order_id: int) -> Dictionary:
	return {"town": town, "rate": rate, "state": ORDERED, "order_id": order_id, "ready_day": 0,
		"cut_x_m": -1, "cut_y_m": -1, "cut_by": "", "fee_milli": 0, "buy_milli": 0, "warned": "",
		"m_drawn": 0, "m_arrived": 0, "m_claimed": 0, "m_skim": 0, "m_fee": 0, "m_buy": 0, "m_bought": {}}


## ActionSystem's SUPPLY_POINT_SET: a new line waits ORDERED; a line already
## running keeps running and holds the new point as `pending`.
static func order_set(state: GameState, code: String, town: String, rate: int, order_id: int) -> void:
	var ln := line(state, code)
	if ln.is_empty():
		state.supply_lines[code] = _new_record(town, rate, order_id)
	else:
		ln["pending"] = {"town": town, "rate": rate, "order_id": order_id}


## A supply courier delivered (CourierSystem._deliver). An older order than
## the line's newest is set aside.
static func deliver(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var code := String(c["target"])
	var order: Dictionary = c["order"]
	var id := int(c["id"])
	var ev := {"type": "delivered", "courier": id, "regiment": code, "weather": ""}
	match String(order["action_code"]):
		"SUPPLY_CARRY_SET":
			var entry: Dictionary = state.regiments.get(code, {})
			if entry.is_empty() or int(entry.get("carry_order_id", 0)) > id:
				ev["type"] = "stale"
				return ev
			entry["carry_days"] = int(order["days"])
			entry["carry_order_id"] = id
		"SUPPLY_POINT_SET":
			var ln := line(state, code)
			var p: Dictionary = ln.get("pending", {}) if not ln.is_empty() else {}
			if not p.is_empty() and int(p["order_id"]) == id:
				ln = _new_record(String(p["town"]), int(p["rate"]), id)
				state.supply_lines[code] = ln
			elif ln.is_empty() or int(ln["order_id"]) != id:
				ev["type"] = "stale"
				return ev
			ln["state"] = RIDING
			var km := road_km(repo, road_px(repo, state, code, String(ln["town"])))
			ln["ready_day"] = state.absolute_day() + wagon_days(repo, km)
		"SUPPLY_POINT_CLEAR":
			var ln := line(state, code)
			if ln.is_empty() or int(ln["order_id"]) > id:
				ev["type"] = "stale"
				return ev
			state.supply_lines.erase(code)
	return ev
