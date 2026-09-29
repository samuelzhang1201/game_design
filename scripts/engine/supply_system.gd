class_name SupplySystem
extends RefCounted
## Supply lines (spec 2026-09-30-ledger-supply-design §3): each land
## regiment of the realm is refilled every month to army_supply_target_months
## of its own use, shipped from the depot (CourierSystem.origin) over the
## road network to where it stands NOW; the road loses
## army_supply_loss_permille_per_100km per 100 km (capped). A garrison in a
## province the crown controls draws through its town: no road, no loss.
## The crown's strategic goods pay first, then the lord's; a short pool is
## shared by need. Whole numbers, code order. plan() is the one function
## the tick, the regiment card and the LEDGER read.


static func loss_of(repo: DataRepository, km: int) -> int:
	@warning_ignore("integer_division")
	var loss := km * int(repo.bal("army_supply_loss_permille_per_100km")) / 100
	return mini(loss, int(repo.bal("army_supply_loss_cap_permille")))


## Units to ship so that `short` arrive after a `loss` per mille.
static func ship_for(short: int, loss: int) -> int:
	if short <= 0:
		return 0
	var keep := 1000 - loss
	@warning_ignore("integer_division")
	return (short * 1000 + keep - 1) / keep


static func gold_for(repo: DataRepository, units: int) -> int:
	@warning_ignore("integer_division")
	return (units * int(repo.bal("army_supply_gold_permille")) + 999) / 1000


static func share(avail: int, golds: Array) -> Array:
	var total := 0
	for g: int in golds:
		total += g
	if total <= avail:
		return golds.duplicate()
	var out: Array = []
	for g: int in golds:
		@warning_ignore("integer_division")
		out.append(maxi(avail, 0) * g / total)
	return out


## The town a garrison draws on: a regiment under a GARRISON order standing
## in a province the crown controls draws on that province's capital town.
static func stronghold_of(repo: DataRepository, state: GameState, code: String) -> String:
	if ArmySystem.order_of(repo, state, code) != ArmySystem.ORDER_GARRISON:
		return ""
	var cell := MapEconomy.cell_at(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)))
	if cell < 0:
		return ""
	var prov := MapManors.province_of(repo, cell, state)
	if prov == "" or not MapManors.crown_controls(repo, state, prov):
		return ""
	return String((repo.provinces.get(prov, {}) as Dictionary).get("capital_burg", ""))


static func line_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var town := stronghold_of(repo, state, code)
	if town != "":
		return {"length_km": 0, "loss_permille": 0, "garrison": true, "stronghold": town}
	var from := CourierSystem.origin(repo, state)
	var to := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var metres := 0.0
	var path := CourierSystem.path_between(repo, from, to)
	if path.size() >= 2:
		for i in range(1, path.size()):
			metres += Vector2(float(path[i - 1][0]), float(path[i - 1][1])).distance_to(
				Vector2(float(path[i][0]), float(path[i][1])))
	else:
		metres = Vector2(ArmySystem.pack_to_metres(repo, from)).distance_to(Vector2(ArmySystem.pack_to_metres(repo, to)))
	var km := int(metres / 1000.0)
	return {"length_km": km, "loss_permille": loss_of(repo, km), "garrison": false, "stronghold": ""}


static func _land_codes(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for c in state.regiments.keys():
		var reg := ArmySystem.regiment(repo, String(c))
		if not reg.is_empty() and String(reg.get("is_naval", "0")) != "1":
			out.append(String(c))
	out.sort()
	return out


static func plan(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	var golds: Array = []
	for code: String in _land_codes(repo, state):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code))
		var target := use * int(repo.bal("army_supply_target_months"))
		var short := maxi(target - int(state.regiments[code]["supplies"]), 0)
		var line := line_of(repo, state, code)
		var loss := int(line["loss_permille"])
		var ship := ship_for(short, loss)
		var gold := gold_for(repo, ship)
		golds.append(gold)
		rows.append({"code": code, "need": short, "ship": ship, "gold": gold, "paid": 0, "delivered": 0,
			"loss_permille": loss, "length_km": int(line["length_km"]), "garrison": bool(line["garrison"]),
			"stronghold": String(line["stronghold"])})
	var avail := maxi(int(state.metrics.get("strategic", 0.0)), 0) + maxi(int(state.metrics.get("lord_strategic", 0.0)), 0)
	var paid := share(avail, golds)
	var price := int(repo.bal("army_supply_gold_permille"))
	for i in rows.size():
		var row: Dictionary = rows[i]
		row["paid"] = int(paid[i])
		@warning_ignore("integer_division")
		var units := int(row["ship"]) if int(paid[i]) >= int(row["gold"]) else int(paid[i]) * 1000 / maxi(price, 1)
		@warning_ignore("integer_division")
		row["delivered"] = mini(units * (1000 - int(row["loss_permille"])) / 1000, int(row["need"]))
	return rows


## The month's shipment: supplies land on each regiment now; the pool lines
## are returned for the tick to apply with its report (crown first, then
## the lord).
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var total := 0
	for row: Dictionary in plan(repo, state):
		total += int(row["paid"])
		var entry: Dictionary = state.regiments[String(row["code"])]
		entry["supplies"] = int(entry["supplies"]) + int(row["delivered"])
	if total == 0:
		return []
	var crown := mini(maxi(int(state.metrics.get("strategic", 0.0)), 0), total)
	var lines: Array = []
	if crown > 0:
		lines.append({"metric": "strategic", "delta": -crown, "reason": "supplies sent to the host"})
	if total - crown > 0:
		lines.append({"metric": "lord_strategic", "delta": -(total - crown), "reason": "supplies sent to the host"})
	return lines


## Any land regiment under army_supply_warn_permille (TriggerDsl host_hungry).
static func any_hungry(repo: DataRepository, state: GameState) -> bool:
	for code: String in _land_codes(repo, state):
		if ArmySystem.bars_of(repo, state, code).y < int(repo.bal("army_supply_warn_permille")):
			return true
	return false
