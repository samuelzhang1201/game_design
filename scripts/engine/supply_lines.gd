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
	var reg := ArmySystem.regiment(repo, code, state)
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


## About what a line of rate `rate` costs a day on the road to `town`, in
## MILLIGOLD (the card's and the rate menu's one formula): the month's draw at
## that rate over the road's km, a day of thirty; `km` < 0 measures the road now.
static func day_fee_milli(repo: DataRepository, state: GameState, code: String, town: String,
		rate: int, km := -1) -> int:
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code, state), state)
	var length := km if km >= 0 else road_km(repo, road_px(repo, state, code, town))
	@warning_ignore("integer_division")
	return use * rate / 1000 * length * int(repo.bal("supply_cart_milligold_per_unit_km")) / Calendar.DAYS_PER_TICK


## Milligold read in tenths of a gold ("0.4") — for display only.
static func gold_words(milli: int) -> String:
	return "%.1f" % (float(milli) / 1000.0)


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
	var rows: Array = ArmySystem.roster(repo, state).values()
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
		"arrive_milli": 0, "claim_milli": 0, "skim_milli": 0,
		"m_drawn": 0, "m_arrived": 0, "m_claimed": 0, "m_skim": 0, "m_fee": 0, "m_buy": 0, "m_bought": {}}


const MONTH_KEYS := ["m_drawn", "m_arrived", "m_claimed", "m_skim", "m_fee", "m_buy"]


## A line leaves state.supply_lines (cleared, cancelled, purged): its month's
## counters are folded into the regiment's entry under the same keys, so the
## marshal's report still tells of its cartage and its skim is still banked.
static func _retire(state: GameState, code: String) -> void:
	var ln := line(state, code)
	var entry: Dictionary = state.regiments.get(code, {})
	if not ln.is_empty() and not entry.is_empty():
		for k: String in MONTH_KEYS:
			entry[k] = int(entry.get(k, 0)) + int(ln.get(k, 0))
		_merge_bought(entry, ln.get("m_bought", {}))
	state.supply_lines.erase(code)


## `bought` (house -> units) added into the record's m_bought.
static func _merge_bought(rec: Dictionary, bought: Dictionary) -> void:
	var mine: Dictionary = rec.get("m_bought", {})
	add_houses(mine, bought)
	rec["m_bought"] = mine


static func add_houses(into: Dictionary, bought: Dictionary) -> void:
	for house: String in bought:
		into[house] = int(into.get(house, 0)) + int(bought[house])


## The record for a `pending` point replacing `old`: ORDERED, the month's
## counters of the line it follows carried over so the marshal's report keeps them.
static func _renewed(old: Dictionary, pending: Dictionary) -> Dictionary:
	var rec := _new_record(String(pending["town"]), int(pending["rate"]), int(pending["order_id"]))
	for k: String in ["m_drawn", "m_arrived", "m_claimed", "m_skim", "m_fee", "m_buy", "fee_milli", "buy_milli",
			"arrive_milli", "claim_milli", "skim_milli"]:
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
## the line's newest is set aside; a SET for the town a flowing or cut line
## already draws on changes only its rate.
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
			if not p.is_empty() and int(p["order_id"]) == id and String(p["town"]) == String(ln["town"]) \
					and String(ln["state"]) in [FLOWING, CUT]:
				# a new rate from the same town: the wagons already roll (final review 3)
				ln["rate"] = int(p["rate"])
				ln["order_id"] = id
				ln.erase("pending")
				return ev
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
				_retire(state, code)
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


## The realm town a land regiment stands in, which tops it up each day
## (ArmySystem.held_town_of, a town of the realm); "" in the field or afloat.
static func home_town(repo: DataRepository, state: GameState, code: String) -> String:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return ""
	var held := ArmySystem.held_town_of(repo, reg, state)
	return held if held != "" and TownStores.is_realm_town(repo, state, held) else ""


## Where a regiment's daily top-up comes from, for the cards: {town: its home
## town ("" in the field), from: that town; while the town's stores are dry
## (the entry's `supply_dry` mark), the depot, or "" when the realm's other
## towns fed it too (`supply_fed`)}.
static func refill_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var town := home_town(repo, state, code)
	var entry: Dictionary = state.regiments.get(code, {}) if state != null else {}
	if town == "" or String(entry.get("supply_dry", "")) != town:
		return {"town": town, "from": town}
	return {"town": town, "from": String(entry.get("supply_fed", TownStores.depot(repo, state)))}


## The cards' words for refill_of: "" in the field, "<town> tops it up", or
## "<town>'s stores are empty: it is fed from <depot | the realm's stores>".
static func refill_words(repo: DataRepository, state: GameState, code: String) -> String:
	var r := refill_of(repo, state, code)
	if String(r["town"]) == "":
		return ""
	var town := String(repo.burgs[String(r["town"])].get("label", r["town"]))
	if String(r["from"]) == String(r["town"]):
		return "%s tops it up" % town
	return "%s's stores are empty: it is fed from %s" % [town, fed_from_words(repo, String(r["from"]))]


## A dry town's feeder in words: the depot's name, or "the realm's stores" ("").
static func fed_from_words(repo: DataRepository, from: String) -> String:
	if from == "":
		return "the realm's stores"
	return String((repo.burgs.get(from, {}) as Dictionary).get("label", from))


## A land regiment standing in a realm town is topped up to its carried load
## each day, free of cartage and road (spec §3.2 step 4), from: its own town
## (crown, lord, the houses' stock bought); then the depot (crown, lord);
## then the CROWN's stock of the other realm towns, nearest first (owner
## 2026-10-07, option A). Nothing past its own town is bought. The first day
## its town falls short returns a `town_dry` event {depot, realm: the other
## towns were drawn}, said once until its town fills it again (`supply_dry`);
## `supply_fed` keeps where it was fed from last (the depot, "" the realm's).
static func _refill_in_town(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> Dictionary:
	var entry: Dictionary = state.regiments[code]
	var held := home_town(repo, state, code)
	if held == "":
		_wet(entry)
		return {}
	var use := ArmySystem.supply_use(repo, reg, state)
	@warning_ignore("integer_division")  # whole units, rounded UP so the days in hand read the load (not one short)
	var target := (use * ArmySystem.carry_of(repo, entry) + Calendar.DAYS_PER_TICK - 1) / Calendar.DAYS_PER_TICK \
		+ ArmySystem.day_bite(use, state.day)
	var room := _room(repo, int(entry["supplies"]), use, state.day, target)
	if room <= 0:
		return {}
	var acc := {"buy_milli": int(entry.get("buy_milli", 0))}
	var d := _draw(repo, state, held, room, acc)
	entry["buy_milli"] = int(acc["buy_milli"])
	entry["supplies"] = int(entry["supplies"]) + int(d["got"])
	_count_buy(repo, state, entry, held, d)
	var rest := room - int(d["got"])
	if rest <= 0:
		_wet(entry)
		return {}
	var dep := TownStores.depot(repo, state)
	var got := 0
	if dep != held:
		got = TownStores.take(state, dep, "crown", rest)
		got += TownStores.take(state, dep, "lord", rest - got)
	var realm := 0
	if got < rest:   # only now: the other towns' order is read
		for t: String in TownStores.nearest_first(repo, state, held):
			if t != dep:
				realm += TownStores.take(state, t, "crown", rest - got - realm)
			if got + realm >= rest:
				break
	if got + realm <= 0:
		return {}
	entry["supplies"] = int(entry["supplies"]) + got + realm
	entry["supply_fed"] = "" if realm > 0 else dep
	if String(entry.get("supply_dry", "")) == held:
		return {}
	entry["supply_dry"] = held
	return {"type": "town_dry", "regiment": code, "town": held, "depot": dep, "realm": realm > 0}


## Its own town feeds it again (or it has left town): the dry marks go.
static func _wet(entry: Dictionary) -> void:
	entry.erase("supply_dry")
	entry.erase("supply_fed")


## The month's purchases from the houses on `rec` (a line, or a regiment
## entry for its refills in town) for the marshal's report: m_buy (gold
## paid), m_bought (house -> units).
static func _count_buy(repo: DataRepository, state: GameState, rec: Dictionary, town: String, d: Dictionary) -> void:
	rec["m_buy"] = int(rec.get("m_buy", 0)) + int(d["house_gold"])
	if int(d["house"]) <= 0:
		return
	var house := MapManors.controller_of(repo, state, String(repo.burgs[town]["province_code"]))
	if not rec.has("m_bought"):
		rec["m_bought"] = {}
	var bought: Dictionary = rec["m_bought"]
	bought[house] = int(bought.get(house, 0)) + int(d["house"])


## Adds `thou` thousandths of a unit to the remainder `key` carried on `ln`
## and returns the whole units now due (the rest stays carried).
static func _carry(ln: Dictionary, key: String, thou: int) -> int:
	var t := int(ln.get(key, 0)) + thou
	ln[key] = t % 1000
	@warning_ignore("integer_division")  # whole units, the rest carried
	return t / 1000


## A flowing line's day (spec §3.2 step 3, §3.4): the day's quota at its
## rate, drawn, thinned by the road (`loss`, per mille: its length's and its
## robbers', SupplySystem.total_loss) and the marshal, its cartage charged.
static func _deliver_line(repo: DataRepository, state: GameState, code: String, reg: Dictionary,
		ln: Dictionary, km: int, loss: int) -> void:
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
	var eff := int(g["efficiency"])
	var keep := 1000 - loss
	# In thousandths of a unit, each remainder carried on the line, so a
	# month's small daily draws come to what SupplySystem.plan projects: the
	# skim off the draw, then the road and the marshal on the rest.
	var skim_thou := got * int(g["skim"])
	@warning_ignore("integer_division")  # thousandths, floored once a day
	var arrive_thou := (got * 1000 - skim_thou) * keep * eff / 1_000_000
	@warning_ignore("integer_division")  # his word: as if nothing were skimmed
	var claim_thou := got * keep * eff / 1000
	var skimmed := _carry(ln, "skim_milli", skim_thou)
	var arrived := _carry(ln, "arrive_milli", arrive_thou)
	var claimed := _carry(ln, "claim_milli", claim_thou)
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
	_count_buy(repo, state, ln, String(ln["town"]), d)


## The order ids the couriers on the road carry now.
static func _riding_orders(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for c: Dictionary in state.couriers:
		out[int(c["id"])] = true
	return out


## An ORDERED line whose own courier no longer rides (lost on the road): a
## `pending` point whose courier still rides becomes the order waited on; a
## SET courier still riding for this line's town (a CLEAR that overwrote its
## id was lost) is waited on again; else {} — nothing is coming.
static func _still_ordered(state: GameState, code: String, ln: Dictionary, riding: Dictionary) -> Dictionary:
	if riding.has(int(ln["order_id"])):
		return ln
	var p: Dictionary = ln.get("pending", {})
	if not p.is_empty() and riding.has(int(p["order_id"])):
		var rec := _renewed(ln, p)
		state.supply_lines[code] = rec
		return rec
	var newest := 0
	for c: Dictionary in state.couriers:
		var o: Dictionary = c.get("order", {})
		if String(c.get("target", "")) == code and String(o.get("action_code", "")) == "SUPPLY_POINT_SET" \
				and String(o.get("to_town", "")) == String(ln["town"]) and int(c["id"]) > newest:
			newest = int(c["id"])
	if newest > 0:
		ln["order_id"] = newest
		return ln
	return {}


## The day's supply for every regiment of the realm, in code order
## (TickEngine._end_day, after the couriers ride, before the host eats):
## the town refills (a dry town's rest from the depot and the realm), then each line's
## state, interception and delivery. An ORDERED line, or a `pending` point,
## whose courier no longer rides (lost on the road) is dropped
## (_still_ordered). Returns the day's events {type, regiment, town, by?,
## at?, depot?, realm?} for the dispatches; the low / empty /
## town_low warnings are warn_day's, once the host has eaten.
static func day_step(repo: DataRepository, state: GameState) -> Array:
	TownStores.reconcile(repo, state)
	var events: Array = []
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code, state)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var dry := _refill_in_town(repo, state, code, reg)
		if not dry.is_empty():
			events.append(dry)
	var riding := _riding_orders(state)
	var lines: Array = state.supply_lines.keys()
	lines.sort()
	for c in lines:
		var code := String(c)
		var ln: Dictionary = state.supply_lines[code]
		var reg := ArmySystem.regiment(repo, code, state)
		if reg.is_empty() or not state.regiments.has(code):
			_retire(state, code)
			continue
		var town := String(ln["town"])
		if String(ln["state"]) == ORDERED and TownStores.is_realm_town(repo, state, town):
			ln = _still_ordered(state, code, ln, riding)
			if ln.is_empty():   # its courier was lost: the town never heard of it
				_retire(state, code)
				events.append({"type": "order_lost", "regiment": code, "town": town})
				continue
		if not TownStores.is_realm_town(repo, state, String(ln["town"])):
			_retire(state, code)
			events.append({"type": "cancelled", "regiment": code, "town": town})
			continue
		town = String(ln["town"])
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
		# the road's length and its robbers (main's marks and hazards, spec
		# 2026-10-07-war-room-p2 §1.2, §2.3) read once a line a day
		var km := road_km(repo, route)
		var robbed := SupplySystem.road_loss(repo, state, code, route)
		_deliver_line(repo, state, code, reg, ln, km, SupplySystem.total_loss(repo, km, int(robbed["permille"])))
	TownStores.sync_metrics(repo, state)
	return events


## Low and empty regiments, and supply towns running short — each said once
## until it recovers (the `supply_warn` mark on the regiment, `warned` on the
## line). TickEngine._end_day, after the host has eaten the day.
static func warn_day(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var low := int(repo.bal("army_supply_low_days"))
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code, state)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var entry: Dictionary = state.regiments[code]
		var use := ArmySystem.supply_use(repo, reg, state)
		if use <= 0:
			continue   # it eats nothing: never low, never empty
		var days := ArmySystem.days_in_hand(int(entry["supplies"]), use)
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
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code, state), state)
		@warning_ignore("integer_division")  # the month's whole units
		draw[String(ln["town"])] = int(draw.get(String(ln["town"]), 0)) + use * int(ln["rate"]) / 1000
	var towns: Array = draw.keys()
	towns.sort()
	for t: String in towns:
		var holds := TownStores.days_of_stock(state, t, int(draw[t]))
		for code: String in keys:
			var ln: Dictionary = state.supply_lines[code]
			if String(ln["town"]) != t:
				continue
			var short := holds < warn_days
			if short and String(ln.get("warned", "")) != "town_low":
				out.append({"type": "town_low", "regiment": code, "town": t, "days": holds})
			ln["warned"] = "town_low" if short else ""
	return out


## The month's close (TickEngine.advance): a row per land regiment for the
## marshal's report, the skims banked (Governance.add_skims), the month's
## counters reset. The in-town refills of a regiment's own entry count with
## its line's purchases. The carried remainders (*_milli) are fractions still
## owed, and cross the month.
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	var gov := Governance.governor_of(repo, state, "supply_line")
	var upg := TownStores.units_per_gold(repo)
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code, state)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var entry: Dictionary = state.regiments[code]
		var ln := line(state, code)
		var use := ArmySystem.supply_use(repo, reg, state)
		# The month's counters: the line's own plus those folded onto the entry
		# (its refills in town, a line retired mid-month).
		var sum: Dictionary = {}
		for k: String in MONTH_KEYS:
			sum[k] = int(ln.get(k, 0)) + int(entry.get(k, 0))
		var bought: Dictionary = {}
		add_houses(bought, ln.get("m_bought", {}))
		add_houses(bought, entry.get("m_bought", {}))
		var skimmed := TownStores.gold_of_units(repo, int(sum["m_skim"]))
		var route := PackedVector2Array() if ln.is_empty() else road_px(repo, state, code, String(ln["town"]))
		var km := road_km(repo, route)
		var robbed := SupplySystem.road_loss(repo, state, code, route)
		rows.append({"code": code, "town": String(ln.get("town", "")), "rate": int(ln.get("rate", 0)),
			"days": ArmySystem.days_in_hand(int(entry["supplies"]), use), "carry": ArmySystem.carry_of(repo, entry),
			"km": km, "loss_permille": SupplySystem.total_loss(repo, km, int(robbed["permille"])),
			"robbers": (robbed["hazards"] as Array).map(func(h: Dictionary) -> String: return String(h["label"])),
			"drawn": int(sum["m_drawn"]), "arrived": int(sum["m_arrived"]),
			"claimed": int(sum["m_claimed"]), "fee": int(sum["m_fee"]),
			"buy": int(sum["m_buy"]), "bought": bought,
			"skimmed": skimmed, "governor": gov})
		if not ln.is_empty():
			for k: String in MONTH_KEYS:
				ln[k] = 0
			ln["m_bought"] = {}
		for k: String in MONTH_KEYS:
			entry[k] = 0
		# the fraction of a gold not yet banked is still owed, and stays
		entry["m_skim"] = int(sum["m_skim"]) % upg
		entry["m_bought"] = {}
	Governance.add_skims(state, rows, "supply_line")
	return rows
