class_name CourierSystem
extends RefCounted
## Couriers (owner 2026-09-27, spec docs/superpowers/specs/2026-09-27-courier-core-design.md):
## an order to a regiment rides from the capital and takes effect only when
## the courier reaches the column. One courier per order, gone on delivery.
## The route is the road network's fastest (RoadGraph); the pace each day is
## the stretch's kind, the height tier it starts on and the province's
## weather (Weather). Whole metres and whole per-mille throughout; couriers
## ride in id order.

const ORDINARY := "ordinary"
const SECRET := "secret"
const SPY := "spy"


## Whether a regiment's orders ride by courier: every land regiment; a fleet
## is exempt in this sub-project (spec §1).
static func carries_orders(reg: Dictionary) -> bool:
	return String(reg.get("is_naval", "0")) != "1"


static func fee_gold(repo: DataRepository, kind: String) -> int:
	return int((repo.courier_kinds.get(kind, {}) as Dictionary).get("fee_gold", 0))


## Clear-road metres a courier of this kind rides in a day.
static func day_budget(repo: DataRepository, kind: String) -> int:
	return int(repo.bal("courier_base_km_per_day")) \
		* int((repo.courier_kinds.get(kind, {}) as Dictionary).get("speed_permille", 1000))


## Where couriers ride from, in pack px: the realm's capital while the realm
## holds its province; else the most populous town of the first province the
## realm holds, in order: the crown's home province, its controlled provinces,
## then any province by code.
static func origin(repo: DataRepository, state: GameState) -> Vector2:
	var realm := repo.resolve_realm("player_realm")
	var cap := String((repo.kingdoms.get(realm, {}) as Dictionary).get("capital_burg", ""))
	if repo.burgs.has(cap) and _holds(repo, state, String(repo.burgs[cap]["province_code"]), realm):
		return _burg_px(repo.burgs[cap])
	var order: Array = []
	var home := MapManors.home_province(repo, state)
	if home != "":
		order.append(home)
	for p: String in MapManors.controlled_provinces(repo, state):
		if not p in order:
			order.append(p)
	var rest := repo.provinces.keys()
	rest.sort()
	for p: String in rest:
		if not p in order:
			order.append(p)
	var codes := repo.burgs.keys()
	codes.sort()
	for p: String in order:
		if not _holds(repo, state, p, realm):
			continue
		var best := ""
		var best_pop := -1
		for b: String in codes:
			var row: Dictionary = repo.burgs[b]
			if String(row["province_code"]) != p:
				continue
			var pop := int(float(row["population"]))
			if pop > best_pop:
				best = b
				best_pop = pop
		if best != "":
			return _burg_px(repo.burgs[best])
	return _burg_px(repo.burgs[cap]) if repo.burgs.has(cap) else Vector2.ZERO


static func _holds(repo: DataRepository, state: GameState, province: String, realm: String) -> bool:
	return MapOwnership.owner_of(repo, state, province) == realm


static func _burg_px(b: Dictionary) -> Vector2:
	return Vector2(float(b["x"]), float(b["y"]))


## The waypoints from one point to another, [x_m, y_m, kind] each (the kind
## of the stretch INTO it): across country to the nearest road node, the
## network's fastest route to the reached node nearest the target, across
## country (or by sea) to the target. Farther than courier_offroad_max_km
## from any node: one straight leg.
static func path_between(repo: DataRepository, from_px: Vector2, to_px: Vector2) -> Array:
	var a := ArmySystem.pack_to_metres(repo, from_px)
	var b := ArmySystem.pack_to_metres(repo, to_px)
	var g := RoadGraph.of_pack(repo)
	var reach := float(repo.bal("courier_offroad_max_km")) * 1000.0
	var start := g.nearest(a)
	if start < 0 or Vector2(a).distance_to(Vector2(g.nodes[start])) > reach:
		return [[b.x, b.y, _leg_kind(repo, a, b)]]
	var tree := g.shortest(start)
	var goal := g.nearest(b, tree["dist"])
	# a start ON the network (the capital is a road node) takes no leg to itself
	var way: Array = [] if g.nodes[start] == a else \
		[[g.nodes[start].x, g.nodes[start].y, _leg_kind(repo, a, g.nodes[start])]]
	way.append_array(g.route(tree, goal))
	way.append([b.x, b.y, _leg_kind(repo, g.nodes[goal], b)])
	return way


## "offroad", or "sea" when any sample every courier_sea_sample_km along the
## leg is off the land grid (MapEconomy.cell_at < 0, the land/sea test
## ActionSystem uses).
static func _leg_kind(repo: DataRepository, a: Vector2i, b: Vector2i) -> String:
	var step := maxf(repo.bal("courier_sea_sample_km") * 1000.0, 1.0)
	var length := Vector2(a).distance_to(Vector2(b))
	for i in range(1, int(length / step) + 1):
		var p := Vector2(a).lerp(Vector2(b), float(i) * step / length)
		if MapEconomy.cell_at(repo, ArmySystem.metres_to_pack(repo, Vector2i(p))) < 0:
			return "sea"
	return "offroad"


## A stretch's pace as a product of per-milles out of 10^9: its kind x the
## height tier where it starts (none at sea) x the weather there.
static func stretch_factor(repo: DataRepository, kind: String, at_m: Vector2i, weather: String) -> int:
	var tier := 1000 if kind == "sea" else RoadGraph.tier_permille(repo, Vector2(at_m))
	return RoadGraph.factor_permille(repo, kind) * tier * Weather.speed_permille(repo, weather)


## Clear-road metres from a point along a path, each stretch at its start's
## weather on `abs_day`.
static func need_along(repo: DataRepository, state: GameState, from_m: Vector2i, path: Array,
		abs_day: int) -> int:
	var need := 0
	var here := from_m
	for p: Array in path:
		var to := Vector2i(int(p[0]), int(p[1]))
		var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), abs_day)
		need += RoadGraph.stretch_need(int(round(Vector2(here).distance_to(Vector2(to)))),
			stretch_factor(repo, String(p[2]), here, wx))
		here = to
	return need


## Whole days to ride `need` clear-road metres, rounded up, at least one.
static func days_for(repo: DataRepository, kind: String, need: int) -> int:
	var b := maxi(1, day_budget(repo, kind))
	@warning_ignore("integer_division")  # whole days, rounded up
	return maxi(1, (need + b - 1) / b)


## Send a courier of `kind` with `order` for regiment `code`. Charges
## nothing: the fee is ActionSystem's ledger line.
static func dispatch(repo: DataRepository, state: GameState, kind: String, code: String,
		order: Dictionary) -> Dictionary:
	var from := origin(repo, state)
	var at := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var home := ArmySystem.pack_to_metres(repo, from)
	var aim := ArmySystem.pack_to_metres(repo, at)
	state.next_courier_id += 1
	var c := {
		"id": state.next_courier_id, "kind": kind, "x_m": home.x, "y_m": home.y,
		"path": path_between(repo, from, at), "target": code, "order": order.duplicate(true),
		"issued": state.absolute_day(), "aim_x_m": aim.x, "aim_y_m": aim.y,
		"days": 0, "day_m": 0, "slow_spell": -1,
	}
	state.couriers.append(c)
	return c


## A spy bound for a point (spec 2026-09-28 §1): A's courier, whose target is
## the point itself; his road is set once and never re-aimed.
static func dispatch_spy(repo: DataRepository, state: GameState, to_px: Vector2) -> Dictionary:
	var from := origin(repo, state)
	var home := ArmySystem.pack_to_metres(repo, from)
	var aim := ArmySystem.pack_to_metres(repo, to_px)
	state.next_courier_id += 1
	var c := {
		"id": state.next_courier_id, "kind": SPY, "x_m": home.x, "y_m": home.y,
		"path": path_between(repo, from, to_px), "target": "",
		"order": {"action_code": "SPY_SEND", "x_m": aim.x, "y_m": aim.y},
		"issued": state.absolute_day(), "aim_x_m": aim.x, "aim_y_m": aim.y,
		"days": 0, "day_m": 0, "slow_spell": -1,
	}
	state.couriers.append(c)
	return c


## Days a courier still has to ride, today's weather held.
static func days_left(repo: DataRepository, state: GameState, c: Dictionary) -> int:
	return days_for(repo, String(c["kind"]), need_along(repo, state,
		Vector2i(int(c["x_m"]), int(c["y_m"])), c["path"], state.absolute_day()))


## The aim ruler's estimate (spec §1): days for a courier sent now to reach
## the regiment, the route and today's weather held. 0 for no regiment.
static func eta_days(repo: DataRepository, state: GameState, kind: String, code: String) -> int:
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty():
		return 0
	var from := origin(repo, state)
	var path := path_between(repo, from, ArmySystem.position_of(repo, state, reg))
	return days_for(repo, kind, need_along(repo, state, ArmySystem.pack_to_metres(repo, from),
		path, state.absolute_day()))


## One DAY on the road for every courier, in id order (TickEngine, before the
## regiments march). Returns the day's events for the news bar.
static func ride_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	var today := state.absolute_day()
	var list: Array = state.couriers.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	var keep: Array = []
	for c: Dictionary in list:
		if _ride(repo, state, c, today, events):
			keep.append(c)
	state.couriers = keep
	return events


## One courier's day; false when he is done (delivered, lost, or out of time).
static func _ride(repo: DataRepository, state: GameState, c: Dictionary, today: int, events: Array) -> bool:
	var code := String(c["target"])
	var reg := ArmySystem.regiment(repo, code)
	if not _is_spy(c) and (reg.is_empty() or ArmySystem.state_of(repo, state, code).is_empty()):
		events.append(_event("lost", c))
		return false
	c["days"] = int(c.get("days", 0)) + 1
	if int(c["days"]) == 1:  # his first day on the road: the news bar says he left
		var e := _event("set_out", c)
		e["capital"] = 1 if _at_capital(repo, c) else 0
		if _is_spy(c):
			e["place"] = Intel.place_label(repo, state, ArmySystem.metres_to_pack(repo,
				Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"]))))
		events.append(e)
	if int(c["days"]) > int(repo.bal("courier_max_days")):
		events.append(_event("fuse", c))
		return false
	if not _is_spy(c):
		_reaim(repo, state, c, reg)
	@warning_ignore("return_value_discarded")  # the budget left matters only to the preview
	_advance(repo, state, c, today, events)
	if (c["path"] as Array).is_empty():
		events.append(SpySystem.observe(repo, state, c) if _is_spy(c) else _deliver(repo, state, c))
		return false
	return true


## A spy courier (SPY_SEND): he rides for a point, not a regiment.
static func _is_spy(c: Dictionary) -> bool:
	return String(c.get("kind", "")) == SPY


## Where a courier's NEXT day on the road takes him: the engine's own ride run
## on a copy, so the map draws him riding it as the day passes instead of a
## day behind (owner 2026-09-28: he stood still a whole day after play was
## pressed). {points: the points he passes in whole metres, ending where the
## day leaves him ([] when he will not ride); share: the share of the day his
## ride takes — under 1 only on the day he reaches the column}. Nothing of
## `state` or `c` is written.
static func ride_ahead(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var before: Array = []
	var copy := _ride_copy(repo, state, c, before)
	if copy.is_empty():
		return {"points": [], "share": 1.0}
	return {"points": passed_points(before, (copy["path"] as Array).size(),
		Vector2i(int(copy["x_m"]), int(copy["y_m"]))), "share": float(copy["ride_share"])}


## `c` after his next day, on a copy ({} when he will not ride), its
## `ride_share` the share of the day's ride he used; `before` receives his road
## as the day starts.
static func _ride_copy(repo: DataRepository, state: GameState, c: Dictionary, before: Array) -> Dictionary:
	var code := String(c["target"])
	var reg := ArmySystem.regiment(repo, code)
	# a spy rides for a point, not a regiment: nothing to lose, nothing to re-aim
	if not _is_spy(c) and (reg.is_empty() or ArmySystem.state_of(repo, state, code).is_empty()):
		return {}
	var copy: Dictionary = c.duplicate(true)
	if not _is_spy(c):
		_reaim(repo, state, copy, reg)
	before.append_array((copy["path"] as Array).duplicate(true))
	# advance_day moves the calendar before the couriers ride, and a tick
	# (day 30 -> day 1) is the next absolute day as well
	var budget := day_budget(repo, String(copy["kind"]))
	var left := _advance(repo, state, copy, state.absolute_day() + 1, [])
	copy["ride_share"] = 1.0 - float(left) / float(budget) if budget > 0 else 1.0
	return copy


## Where the next day leaves a regiment: {m: whole metres; from: the share of
## the day its march starts at — the couriers ride first, so an order one of
## them delivers that day is marched on that day (TickEngine.advance_day),
## from the moment he reaches it}, then ArmySystem.march_ahead. Nothing is
## written.
static func day_ahead_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var from := 0.0
	var entry: Dictionary = (state.regiments.get(code, {}) as Dictionary).duplicate(true)
	var list: Array = state.couriers.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for c: Dictionary in list:
		if String(c["target"]) != code or int(entry.get("order_id", 0)) > int(c["id"]) \
				or int(c.get("days", 0)) + 1 > int(repo.bal("courier_max_days")):
			continue
		var done := _ride_copy(repo, state, c, [])
		if done.is_empty() or not (done["path"] as Array).is_empty():
			continue
		var order: Dictionary = c["order"]
		match String(order.get("action_code", "")):
			"ARMY_MARCH":
				# the round trip through pack px _deliver's set_march takes
				var dest := ArmySystem.pack_to_metres(repo, ArmySystem.metres_to_pack(repo,
					Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"]))))
				entry["order"] = ArmySystem.ORDER_MARCH
				entry["dest_x_m"] = dest.x
				entry["dest_y_m"] = dest.y
			"ARMY_GARRISON":
				entry["order"] = ArmySystem.ORDER_GARRISON
		entry["order_id"] = int(c["id"])
		from = float(done["ride_share"])
	return {"m": ArmySystem.march_ahead(repo, state, code, entry), "from": from}


## The points (whole metres) a courier passed on a day: the waypoints his road
## dropped from its front, then where he stands.
static func passed_points(old_path: Array, new_size: int, now: Vector2i) -> Array:
	var out: Array = []
	for i in range(maxi(old_path.size() - new_size, 0)):
		out.append(Vector2i(int(old_path[i][0]), int(old_path[i][1])))
	out.append(now)
	return out


## One day's ride along `c`'s road, which it writes: his spot, his road, day_m.
## Returns the day's budget left unridden (he arrived with some to spare).
static func _advance(repo: DataRepository, state: GameState, c: Dictionary, today: int, events: Array) -> int:
	var budget := day_budget(repo, String(c["kind"]))
	var here := Vector2i(int(c["x_m"]), int(c["y_m"]))
	var start := here
	var path: Array = c["path"]
	while not path.is_empty() and budget > 0:
		var to := Vector2i(int(path[0][0]), int(path[0][1]))
		var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), today)
		_note_slow(repo, c, wx, today, events)
		var f := stretch_factor(repo, String(path[0][2]), here, wx)
		var length := int(round(Vector2(here).distance_to(Vector2(to))))
		var need := RoadGraph.stretch_need(length, f)
		if need <= budget:
			budget -= need
			here = to
			path.pop_front()
			continue
		@warning_ignore("integer_division")  # whole metres into the stretch
		var adv := budget * f / 1_000_000_000
		if length > 0:
			var way := (Vector2(to) - Vector2(here)) / float(length)
			here = Vector2i(roundi(float(here.x) + way.x * float(adv)), roundi(float(here.y) + way.y * float(adv)))
		budget = 0
	c["day_m"] = int(round(Vector2(start).distance_to(Vector2(here))))
	c["x_m"] = here.x
	c["y_m"] = here.y
	return budget


## The column has moved more than courier_reaim_m since his road was set:
## his last leg now ends where it stands (a column is far slower than a
## courier, so the road itself is not re-planned).
static func _reaim(repo: DataRepository, state: GameState, c: Dictionary, reg: Dictionary) -> void:
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, reg))
	if Vector2(at).distance_to(Vector2(int(c["aim_x_m"]), int(c["aim_y_m"]))) <= repo.bal("courier_reaim_m"):
		return
	c["aim_x_m"] = at.x
	c["aim_y_m"] = at.y
	var path: Array = c["path"]
	if path.is_empty():
		path.append([at.x, at.y, "offroad"])
	else:
		path[path.size() - 1] = [at.x, at.y, String(path[path.size() - 1][2])]


static func _note_slow(repo: DataRepository, c: Dictionary, weather: String, today: int, events: Array) -> void:
	if Weather.speed_permille(repo, weather) >= int(repo.bal("courier_slow_news_permille")):
		return
	var spell := Weather.spell_of(repo, today)
	if int(c.get("slow_spell", -1)) == spell:
		return
	c["slow_spell"] = spell
	events.append(_event("slow", c, weather))


## The order takes effect — unless the column already obeys a NEWER one (a
## higher courier id), in which case this one is set aside.
static func _deliver(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var code := String(c["target"])
	var entry: Dictionary = state.regiments.get(code, {})
	if int(entry.get("order_id", 0)) > int(c["id"]):
		MissiveLog.add(repo, state, MissiveWriter.receipt(repo, state, c, true))
		return _event("stale", c)
	var order: Dictionary = c["order"]
	match String(order.get("action_code", "")):
		"ARMY_MARCH":
			ArmySystem.set_march(repo, state, code, ArmySystem.metres_to_pack(repo,
				Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"]))))
		"ARMY_GARRISON":
			ArmySystem.set_garrison(repo, state, code)
	if state.regiments.has(code):
		state.regiments[code]["order_id"] = int(c["id"])
	MissiveLog.add(repo, state, MissiveWriter.receipt(repo, state, c, false))
	return _event("delivered", c)


## Whether he stands on the capital's own spot — where dispatch puts him when
## the realm holds its capital (origin), and nowhere else it would.
static func _at_capital(repo: DataRepository, c: Dictionary) -> bool:
	var cap := String((repo.kingdoms.get(repo.resolve_realm("player_realm"), {}) as Dictionary).get("capital_burg", ""))
	if not repo.burgs.has(cap):
		return false
	return ArmySystem.pack_to_metres(repo, _burg_px(repo.burgs[cap])) == Vector2i(int(c["x_m"]), int(c["y_m"]))


static func _event(type: String, c: Dictionary, weather: String = "") -> Dictionary:
	return {"type": type, "courier": int(c["id"]), "regiment": String(c["target"]), "weather": weather}


## The newest courier riding for a regiment, {} when none.
static func pending_for(state: GameState, code: String) -> Dictionary:
	var best: Dictionary = {}
	if state == null:
		return best
	for c: Dictionary in state.couriers:
		if String(c["target"]) == code and (best.is_empty() or int(c["id"]) > int(best["id"])):
			best = c
	return best


## The news bar's line for a ride_day event.
static func headline(repo: DataRepository, e: Dictionary) -> String:
	var label := String(ArmySystem.regiment(repo, String(e.get("regiment", ""))).get("label", e.get("regiment", "")))
	match String(e.get("type", "")):
		"set_out":
			if String(e.get("place", "")) != "":
				if int(e.get("capital", 0)) == 1:
					return "A spy leaves the capital for %s." % String(e["place"])
				return "A spy rides for %s." % String(e["place"])
			if int(e.get("capital", 0)) == 1:
				return "A courier leaves the capital for %s." % label
			return "A courier rides for %s." % label
		"spy_report":
			return "The spy at %s reports." % String(e.get("place", "the place"))
		"delivered":
			return "Orders delivered to %s." % label
		"stale":
			return "Older orders to %s came after newer ones and were set aside." % label
		"lost":
			return "Orders to %s undelivered: the regiment is gone." % label
		"fuse":
			return "Orders to %s undelivered: the courier never found them." % label
		"slow":
			return "The courier to %s is held up by %s." % [label, Weather.label_of(repo, String(e.get("weather", ""))).to_lower()]
	return ""
