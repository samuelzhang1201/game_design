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


## The record for a `pending` point replacing `old`: ORDERED, the month's
## counters of the line it follows carried over so the marshal's report keeps them.
static func _renewed(old: Dictionary, pending: Dictionary) -> Dictionary:
	var rec := _new_record(String(pending["town"]), int(pending["rate"]), int(pending["order_id"]))
	for k: String in ["m_drawn", "m_arrived", "m_claimed", "m_skim", "m_fee", "m_buy", "fee_milli", "buy_milli"]:
		rec[k] = int(old.get(k, 0))
	rec["m_bought"] = (old.get("m_bought", {}) as Dictionary).duplicate(true)
	return rec


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
	var ev := CourierSystem._event("delivered", c)
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
				ln = _renewed(ln, p)
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
			var held: Dictionary = ln.get("pending", {})
			if not held.is_empty() and int(held["order_id"]) > id:
				# a newer SET is still riding: the wagons stop, the new point waits
				state.supply_lines[code] = _renewed(ln, held)
			else:
				state.supply_lines.erase(code)
	return ev


## Draws up to `units` from `town` (spec §3.3): crown, lord, then the house's
## stock BOUGHT at value × (1000 + supply_buy_markup_permille) / 1000 while
## the treasury can pay, the price accrued in milligold on `acc["buy_milli"]`
## (owed, not yet charged) and whole gold taken as it crosses — never past
## what the treasury holds. {got, house, house_gold}.
static func _draw(repo: DataRepository, state: GameState, town: String, units: int, acc: Dictionary) -> Dictionary:
	var got := TownStores.take(state, town, "crown", units)
	got += TownStores.take(state, town, "lord", units - got)
	var want := units - got
	var bought := 0
	var paid := 0
	if want > 0:
		@warning_ignore("integer_division")  # whole milligold a unit
		var milli_each := int(repo.bal("army_supply_gold_permille")) * (1000 + int(repo.bal("supply_buy_markup_permille"))) / 1000
		var owed := int(acc.get("buy_milli", 0))
		var purse := maxi(int(state.metrics.get("treasury", 0.0)) * 1000 - owed, 0)
		@warning_ignore("integer_division")  # whole units the purse covers
		var afford := purse / maxi(milli_each, 1)
		bought = TownStores.take(state, town, "house", mini(want, afford))
		var milli := owed + bought * milli_each
		@warning_ignore("integer_division")  # whole gold, the rest carried
		paid = milli / 1000
		acc["buy_milli"] = milli % 1000
		if paid > 0:
			state.metrics["treasury"] = float(state.metrics["treasury"]) - float(paid)
	return {"got": got + bought, "house": bought, "house_gold": paid}


## The units a regiment may still take today: up to `target`, never past
## army_supply_max_days after today's meal.
static func _room(repo: DataRepository, supplies: int, use: int, day: int, target: int) -> int:
	var bite := ArmySystem.day_bite(use, day)
	return maxi(mini(target, ArmySystem.max_units(repo, use) + bite) - supplies, 0)


## A land regiment standing in a realm town is topped up to its carried load
## from that town, free of cartage and road (spec §3.2 step 4).
static func _refill_in_town(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> void:
	var held := ArmySystem.held_town_of(repo, reg, state)
	if held == "" or not TownStores.is_realm_town(repo, state, held):
		return
	var entry: Dictionary = state.regiments[code]
	var use := ArmySystem.supply_use(repo, reg, state)
	@warning_ignore("integer_division")  # whole units
	var target := use * ArmySystem.carry_of(repo, entry) / Calendar.DAYS_PER_TICK + ArmySystem.day_bite(use, state.day)
	var room := _room(repo, int(entry["supplies"]), use, state.day, target)
	if room <= 0:
		return
	var acc := {"buy_milli": int(entry.get("buy_milli", 0))}
	var d := _draw(repo, state, held, room, acc)
	entry["buy_milli"] = int(acc["buy_milli"])
	entry["supplies"] = int(entry["supplies"]) + int(d["got"])


## A flowing line's day (spec §3.2 step 3, §3.4): the day's quota at its
## rate, drawn, thinned by the road and the marshal, its cartage charged.
static func _deliver_line(repo: DataRepository, state: GameState, code: String, reg: Dictionary,
		ln: Dictionary, km: int) -> void:
	var entry: Dictionary = state.regiments[code]
	var use := ArmySystem.supply_use(repo, reg, state)
	@warning_ignore("integer_division")  # the rate's whole units
	var quota := ArmySystem.day_bite(use * int(ln["rate"]) / 1000, state.day)
	var send := mini(quota, _room(repo, int(entry["supplies"]), use, state.day,
		ArmySystem.max_units(repo, use) + ArmySystem.day_bite(use, state.day)))
	if send <= 0:
		return
	var d := _draw(repo, state, String(ln["town"]), send, ln)
	var got := int(d["got"])
	var g := Governance.factors(repo, state, "supply_line")
	@warning_ignore("integer_division")  # whole units
	var skimmed := got * int(g["skim"]) / 1000
	var keep := 1000 - SupplySystem.loss_of(repo, km)
	@warning_ignore("integer_division")  # whole units, the road then the marshal
	var arrived := (got - skimmed) * keep / 1000 * int(g["efficiency"]) / 1000
	@warning_ignore("integer_division")  # his word: as if nothing were skimmed
	var claimed := got * keep / 1000 * int(g["efficiency"]) / 1000
	entry["supplies"] = int(entry["supplies"]) + arrived
	var milli := int(ln["fee_milli"]) + got * km * int(repo.bal("supply_cart_milligold_per_unit_km"))
	@warning_ignore("integer_division")  # whole gold, the rest carried
	var fee := milli / 1000
	ln["fee_milli"] = milli % 1000
	if fee > 0:
		state.metrics["treasury"] = float(state.metrics["treasury"]) - float(fee)
	ln["m_drawn"] = int(ln["m_drawn"]) + got
	ln["m_arrived"] = int(ln["m_arrived"]) + arrived
	ln["m_claimed"] = int(ln["m_claimed"]) + claimed
	ln["m_skim"] = int(ln["m_skim"]) + skimmed
	ln["m_fee"] = int(ln["m_fee"]) + fee
	ln["m_buy"] = int(ln["m_buy"]) + int(d["house_gold"])
	if int(d["house"]) > 0:
		var house := MapManors.controller_of(repo, state, String(repo.burgs[String(ln["town"])]["province_code"]))
		var bought: Dictionary = ln["m_bought"]
		bought[house] = int(bought.get(house, 0)) + int(d["house"])


## The order ids the couriers on the road carry now.
static func _riding_orders(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for c: Dictionary in state.couriers:
		out[int(c["id"])] = true
	return out


## The day's supply for every regiment of the realm, in code order
## (TickEngine._end_day, after the couriers ride, before the host eats):
## the town refills, then each line's state, interception and delivery.
## An ORDERED line, or a `pending` point, whose courier no longer rides (lost
## on the road) is dropped. Returns the day's events
## {type, regiment, town, by?, at?} for the dispatches.
static func day_step(repo: DataRepository, state: GameState) -> Array:
	TownStores.reconcile(repo, state)
	var events: Array = []
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		_refill_in_town(repo, state, code, reg)
	var riding := _riding_orders(state)
	var lines: Array = state.supply_lines.keys()
	lines.sort()
	for c in lines:
		var code := String(c)
		var ln: Dictionary = state.supply_lines[code]
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or not state.regiments.has(code):
			state.supply_lines.erase(code)
			continue
		var town := String(ln["town"])
		if not TownStores.is_realm_town(repo, state, town) \
				or (String(ln["state"]) == ORDERED and not riding.has(int(ln["order_id"]))):
			state.supply_lines.erase(code)
			events.append({"type": "cancelled", "regiment": code, "town": town})
			continue
		if ln.has("pending") and not riding.has(int((ln["pending"] as Dictionary)["order_id"])):
			ln.erase("pending")
		if String(ln["state"]) == ORDERED:
			continue
		if String(ln["state"]) == RIDING:
			if state.absolute_day() < int(ln["ready_day"]):
				continue
			ln["state"] = FLOWING
			events.append({"type": "opened", "regiment": code, "town": town})
		var route := road_px(repo, state, code, town)
		var cut := cut_point(repo, state, route)
		if not cut.is_empty():
			if String(ln["state"]) != CUT:
				var at := ArmySystem.pack_to_metres(repo, cut["at"])
				ln["cut_x_m"] = at.x
				ln["cut_y_m"] = at.y
				ln["cut_by"] = String(cut["by"])
				events.append({"type": "cut", "regiment": code, "town": town, "by": String(cut["by"]),
					"at": cut["at"]})
			ln["state"] = CUT
			continue
		if String(ln["state"]) == CUT:
			ln["state"] = FLOWING
			ln["cut_x_m"] = -1
			ln["cut_y_m"] = -1
			ln["cut_by"] = ""
			events.append({"type": "restored", "regiment": code, "town": town})
		_deliver_line(repo, state, code, reg, ln, road_km(repo, route))
	events.append_array(_warnings(repo, state))
	TownStores.sync_metrics(repo, state)
	return events


## Low and empty regiments, and supply towns running short — each said once
## until it recovers (the `supply_warn` mark on the regiment, `warned` on the line).
static func _warnings(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var low := int(repo.bal("army_supply_low_days"))
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var entry: Dictionary = state.regiments[code]
		var days := ArmySystem.days_in_hand(int(entry["supplies"]), ArmySystem.supply_use(repo, reg, state))
		var now := "empty" if int(entry["supplies"]) <= 0 else ("low" if days < low else "")
		if now != String(entry.get("supply_warn", "")):
			entry["supply_warn"] = now
			if now != "":
				out.append({"type": now, "regiment": code, "town": String(line(state, code).get("town", ""))})
	var warn_days := int(repo.bal("supply_warn_town_days"))
	var draw: Dictionary = {}
	var keys: Array = state.supply_lines.keys()
	keys.sort()
	for code: String in keys:
		var ln: Dictionary = state.supply_lines[code]
		if String(ln["state"]) != FLOWING:
			continue
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), state)
		@warning_ignore("integer_division")  # the month's whole units
		draw[String(ln["town"])] = int(draw.get(String(ln["town"]), 0)) + use * int(ln["rate"]) / 1000
	var towns: Array = draw.keys()
	towns.sort()
	for t: String in towns:
		var st := TownStores.stock_of(state, t)
		@warning_ignore("integer_division")  # whole days
		var holds := (int(st["crown"]) + int(st["lord"]) + int(st["house"])) * Calendar.DAYS_PER_TICK / maxi(int(draw[t]), 1)
		for code: String in keys:
			var ln: Dictionary = state.supply_lines[code]
			if String(ln["town"]) != t:
				continue
			var short := holds < warn_days
			if short and String(ln.get("warned", "")) != "town_low":
				out.append({"type": "town_low", "regiment": code, "town": t, "days": holds})
			ln["warned"] = "town_low" if short else ""
	return out
