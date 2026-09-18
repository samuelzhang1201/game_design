class_name ManorEconomy
extends RefCounted
## A manor's MONTH in whole gold (spec 2026-09-14 §4): tax, the tariff its
## town pays, and the goods it makes — its chief good, its buildings' and
## its settlement's lines — each rounded to whole units and valued at
## goods_economy.csv prices into the strategic or the civil pool. THE ONLY
## ROUNDING IN THE ECONOMY HAPPENS HERE; provinces and the realm are sums.
## Nothing is stored: a line is a pure function of the pack, the state's
## buildings, focus and ledger figures, and the tick. Iteration is by good
## code, ascending, so a line is the same integers on every machine.

## "repo id|good" -> PackedInt32Array, index tick -> per-mille growth.
static var _growth: Dictionary = {}

static func forget() -> void:
	_growth.clear()

## A good's growth index at a tick, per mille: 1000 at tick 0, compounding
## growth_permille a month in INTEGERS (next = round(prev x (1000 + g) /
## 1000)), tabulated once per good as ticks pass. Integer, so a save ticks
## to the same numbers on every machine (invariant 2, architecture R-7).
static func growth_index(repo: DataRepository, good: String, tick: int) -> int:
	var g := int(repo.goods_economy_of(good)["growth_permille"])
	var key := "%d|%s" % [repo.get_instance_id(), good]
	var table: PackedInt32Array = _growth.get(key, PackedInt32Array([1000]))
	while table.size() <= tick:
		var prev := table[table.size() - 1]
		@warning_ignore("integer_division")  # whole per-mille, rounded half up (invariant 11)
		table.append((prev * (1000 + g) + 500) / 1000)
	_growth[key] = table
	return table[maxi(tick, 0)]

## What the chief good yields this month: {good, units} — people / 1000 x
## yield_per_1000 x land value x the settling-in ramp x (1 + the buildings'
## output bonus) x growth, rounded. {"", 0} for land that works nothing.
static func focus_units(repo: DataRepository, state: GameState, cell: int, people: int,
		tick: int) -> Dictionary:
	var code := MapManors.focus_of(repo, state, cell)
	var row: Dictionary = repo.manor_focus.get(code, {})
	if row.is_empty():
		return {"good": "", "units": 0}
	var good := String(row.get("good_code", ""))
	var exact := float(people) / 1000.0 * float(row.get("yield_per_1000", 0)) \
		* MapManors.land_value_of(repo, cell) * MapManors.focus_ramp(repo, state, cell) \
		* (1.0 + MapManors.building_bonus(repo, state, cell, "output_bonus")) \
		* float(growth_index(repo, good, tick)) / 1000.0
	return {"good": good, "units": int(roundf(exact))}

## The manor's month: {people, tax, tariff, strategic, civil, units}.
## `tax` INCLUDES the tariff (the tariff is also given on its own for the
## card). tax = round(people / 1000 x manor_tax_per_1000 x tax_rate /
## tax_rate_base x (1 + Σ tax_bonus)); tariff = round(town goods' gold x
## tariff_rate x tariff_per_sales_tax / 100); a town's lines are the pack's
## production rows for its burg, each x growth x (1 + Σ output_bonus).
static func line_of(repo: DataRepository, state: GameState, cell: int, tick: int) -> Dictionary:
	var people := MapManors.people_of(repo, state, cell)
	var m := state.metrics
	var tax_rate := float(m.get("tax_rate", repo.bal("tax_rate_base")))
	var tax := int(roundf(float(people) / 1000.0 * repo.bal("manor_tax_per_1000")
		* tax_rate / repo.bal("tax_rate_base")
		* (1.0 + MapManors.building_bonus(repo, state, cell, "tax_bonus"))))
	var units: Dictionary = {}
	var f := focus_units(repo, state, cell, people, tick)
	if int(f["units"]) > 0:
		units[f["good"]] = int(f["units"])
	var made := MapManors.building_output_of(repo, state, cell)
	var made_codes: Array = made.keys()
	made_codes.sort()
	for good: String in made_codes:
		var u := int(roundf(float(made[good]) * float(growth_index(repo, good, tick)) / 1000.0))
		if u > 0:
			units[good] = int(units.get(good, 0)) + u
	var out_bonus := 1.0 + MapManors.building_bonus(repo, state, cell, "output_bonus")
	var town: Dictionary = (MapEconomy.manors(repo).get(cell, {}) as Dictionary).get("goods", {})
	var town_codes: Array = town.keys()
	town_codes.sort()
	var town_gold := 0
	for good: String in town_codes:
		var u := int(roundf(float(town[good]) * float(growth_index(repo, good, tick)) / 1000.0 * out_bonus))
		if u <= 0:
			continue
		units[good] = int(units.get(good, 0)) + u
		town_gold += u * int(repo.goods_economy_of(good)["price_gold"])
	var tariff := 0
	if town_gold > 0:
		tariff = int(roundf(float(town_gold) * float(m.get("tariff_rate", 0.0))
			* repo.bal("tariff_per_sales_tax") / 100.0))
	var strategic := 0
	var civil := 0
	var codes: Array = units.keys()
	codes.sort()
	for good: String in codes:
		var ge := repo.goods_economy_of(good)
		var gold := int(units[good]) * int(ge["price_gold"])
		if String(ge["pool"]) == "strategic":
			strategic += gold
		else:
			civil += gold
	return {"people": people, "tax": tax + tariff, "tariff": tariff,
		"strategic": strategic, "civil": civil, "units": units}
