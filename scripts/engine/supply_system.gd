class_name SupplySystem
extends RefCounted
## The supply helpers the cards, the WAR ROOM and the LEDGER read (spec
## 2026-10-07-army-supply-lines): the road's loss, the garrison test, and a
## regiment's line as it stands. The daily step is SupplyLines.day_step.


static func loss_of(repo: DataRepository, km: int) -> int:
	@warning_ignore("integer_division")
	var loss := km * int(repo.bal("army_supply_loss_permille_per_100km")) / 100
	return mini(loss, int(repo.bal("army_supply_loss_cap_permille")))


## A line's whole loss: its length's (loss_of) and its marks' (mark_loss),
## held to army_supply_loss_cap_permille.
static func total_loss(repo: DataRepository, km: int, mark_permille: int) -> int:
	return mini(loss_of(repo, km) + maxi(mark_permille, 0), int(repo.bal("army_supply_loss_cap_permille")))


## What the brigands and pirates along a route take (spec
## 2026-10-07-war-room-p2-tactical-layer §1.2): each hazard mark
## (data/war_mark_hazards.csv) whose reach the route (pack px) passes through,
## once per mark, in code order — {permille, hazards: [{code, label, permille}]}.
## Pirates need no water test: their marks stand at sea, so a road within their
## reach runs along the coast they raid.
static func mark_loss(repo: DataRepository, route: PackedVector2Array) -> Dictionary:
	var hazards: Array = []
	var total := 0
	if route.size() < 2:
		return {"permille": 0, "hazards": hazards}
	var per_px := WarMarks.km_per_px(repo)
	var codes: Array = repo.markers.keys()
	codes.sort()
	for code: String in codes:
		var m: Dictionary = repo.markers[code]
		var hz: Dictionary = repo.war_mark_hazards.get(String(m.get("type", "")), {})
		if hz.is_empty():
			continue
		var at := Vector2(float(m["x"]), float(m["y"]))
		if _poly_distance(route, at) * per_px <= float(hz["reach_km"]):
			total += int(hz["permille"])
			hazards.append({"code": code, "label": String(m.get("label", code)), "permille": int(hz["permille"])})
	return {"permille": total, "hazards": hazards}


## What the active hazards a route crosses take (spec 2026-10-07-war-room-p2
## §2.3): each hazard with a supply_loss_permille once, id order, sampled along
## the route every war_hazard_sample_km; a hazard the crown does not know is
## not named ("trouble on the road").
static func hazard_loss(repo: DataRepository, state: GameState, route: PackedVector2Array) -> Dictionary:
	var hazards: Array = []
	var total := 0
	if state == null or route.size() < 2:
		return {"permille": 0, "hazards": hazards}
	var step := repo.bal("war_hazard_sample_km") / WarMarks.km_per_px(repo)
	var hit: Dictionary = {}
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for j in n + 1:
			for id: String in Hazards.at_point(repo, state, a.lerp(b, float(j) / float(n))):
				hit[id] = true
	var ids: Array = hit.keys()
	ids.sort()
	for id: String in ids:
		var h: Dictionary = state.hazards[id]
		var p := int(Hazards.kind_of(repo, String(h["kind"])).get("supply_loss_permille", 0))
		if p <= 0:
			continue
		total += p
		hazards.append({"code": id, "permille": p,
			"label": String(h["label"]) if Hazards.known(repo, state, id) else "trouble on the road"})
	return {"permille": total, "hazards": hazards}


## The nearest a polyline comes to a point, pack px.
static func _poly_distance(poly: PackedVector2Array, at: Vector2) -> float:
	var best := INF
	for i in poly.size() - 1:
		best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, poly[i], poly[i + 1])))
	return best


## What the brigands, the pirates and the active hazards along a land
## regiment's road take (mark_loss + hazard_loss, once each), {permille,
## hazards}; a fleet's road is no road they can rob (spec 2026-10-07-war-room-
## p2 §1.2). `route` is the line's road (SupplyLines.road_px).
static func road_loss(repo: DataRepository, state: GameState, code: String, route: PackedVector2Array) -> Dictionary:
	if String(ArmySystem.regiment(repo, code).get("is_naval", "0")) == "1":
		return {"permille": 0, "hazards": []}
	var out := mark_loss(repo, route)
	var through := hazard_loss(repo, state, route)
	out["permille"] = int(out["permille"]) + int(through["permille"])
	(out["hazards"] as Array).append_array(through["hazards"])
	return out


static func gold_for(repo: DataRepository, units: int) -> int:
	@warning_ignore("integer_division")
	return (units * int(repo.bal("army_supply_gold_permille")) + 999) / 1000


## The town a regiment is GARRISONED in (spec 2026-10-06-army-location-and-
## town-defence §4): under a GARRISON order, the town of its own kingdom it
## stands IN (ArmySystem.held_town_of) — what earns the garrison's morale and
## the LEDGER's "garrisons in" thread. "" otherwise: a column halted in the
## open is a field camp.
static func garrisoned_in(repo: DataRepository, state: GameState, code: String) -> String:
	if ArmySystem.order_of(repo, state, code) != ArmySystem.ORDER_GARRISON:
		return ""
	return ArmySystem.held_town_of(repo, ArmySystem.regiment(repo, code), state)


## A regiment's line as it stands, for the cards: {town ("" with none),
## state, rate, length_km, loss_permille (the road's and its robbers',
## total_loss), hazards (road_loss's names), garrison, garrison_town}.
static func line_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var held := garrisoned_in(repo, state, code)
	var ln := SupplyLines.line(state, code)
	var out := {"town": "", "state": "", "rate": 0, "length_km": 0, "loss_permille": 0,
		"garrison": held != "", "garrison_town": held, "hazards": []}
	if ln.is_empty():
		return out
	var route := SupplyLines.road_px(repo, state, code, String(ln["town"]))
	var km := SupplyLines.road_km(repo, route)
	var robbed := road_loss(repo, state, code, route)
	out["town"] = String(ln["town"])
	out["state"] = String(ln["state"])
	out["rate"] = int(ln["rate"])
	out["length_km"] = km
	out["loss_permille"] = total_loss(repo, km, int(robbed["permille"]))
	out["hazards"] = robbed["hazards"]
	return out


## The supply road a regiment is fed along, pack px from its supply town to
## where it stands (the WAR ROOM's ink, the 3D map's line); empty with none.
static func route_px(repo: DataRepository, state: GameState, code: String) -> PackedVector2Array:
	var ln := SupplyLines.line(state, code)
	if ln.is_empty():
		return PackedVector2Array()
	return SupplyLines.road_px(repo, state, code, String(ln["town"]))


static func _land_codes(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for c in state.regiments.keys():
		var reg := ArmySystem.regiment(repo, String(c))
		if not reg.is_empty() and String(reg.get("is_naval", "0")) != "1":
			out.append(String(c))
	out.sort()
	return out


## The month a line will run at today's rate, read by the LEDGER, the audit
## and the WAR ROOM (spec 2026-10-07-army-supply-lines §2.3): one row per
## line, code order. `delivered` is the truth after the road and the
## marshal's efficiency and skim; `claimed` his word. Memoised by
## LedgerResolvers as before.
static func plan(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	var g := Governance.factors(repo, state, "supply_line")
	var eff := int(g["efficiency"])
	var skim := int(g["skim"])
	var codes: Array = state.supply_lines.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty():
			continue
		var ln: Dictionary = state.supply_lines[code]
		var line := line_of(repo, state, code)
		@warning_ignore("integer_division")
		var need := ArmySystem.supply_use(repo, reg, state) * int(ln["rate"]) / 1000
		var keep := 1000 - int(line["loss_permille"])
		@warning_ignore("integer_division")
		var skimmed := need * skim / 1000
		@warning_ignore("integer_division")
		var delivered := (need - skimmed) * keep / 1000 * eff / 1000
		@warning_ignore("integer_division")
		var claimed := need * keep / 1000 * eff / 1000
		rows.append({"code": code, "town": String(ln["town"]), "rate": int(ln["rate"]), "state": String(ln["state"]),
			"length_km": int(line["length_km"]), "loss_permille": int(line["loss_permille"]),
			"need": need, "paid": TownStores.gold_of_units(repo, need), "delivered": delivered,
			"claimed": claimed, "skimmed": TownStores.gold_of_units(repo, skimmed),
			"efficiency": eff, "skim": skim, "governor": String(g["governor"])})
	return rows


## Any land regiment whose supply SCORE is under army_supply_warn_permille
## (TriggerDsl host_hungry).
static func any_hungry(repo: DataRepository, state: GameState) -> bool:
	for code: String in _land_codes(repo, state):
		var reg := ArmySystem.regiment(repo, code)
		var score := ArmySystem.supply_score(repo, int(state.regiments[code]["supplies"]),
			ArmySystem.supply_use(repo, reg, state))
		if score < int(repo.bal("army_supply_warn_permille")):
			return true
	return false
