class_name SupplySystem
extends RefCounted
## The supply helpers the cards, the WAR ROOM and the LEDGER read (spec
## 2026-10-07-army-supply-lines): the road's loss, the garrison test, and a
## regiment's line as it stands. The daily step is SupplyLines.day_step.


static func loss_of(repo: DataRepository, km: int) -> int:
	@warning_ignore("integer_division")
	var loss := km * int(repo.bal("army_supply_loss_permille_per_100km")) / 100
	return mini(loss, int(repo.bal("army_supply_loss_cap_permille")))


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
## state, rate, length_km, loss_permille, garrison, garrison_town}.
static func line_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var held := garrisoned_in(repo, state, code)
	var ln := SupplyLines.line(state, code)
	var out := {"town": "", "state": "", "rate": 0, "length_km": 0, "loss_permille": 0,
		"garrison": held != "", "garrison_town": held}
	if ln.is_empty():
		return out
	var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, state, code, String(ln["town"])))
	out["town"] = String(ln["town"])
	out["state"] = String(ln["state"])
	out["rate"] = int(ln["rate"])
	out["length_km"] = km
	out["loss_permille"] = loss_of(repo, km)
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
