class_name MarchPlan
extends RefCounted
## The march confirm's figures (spec 2026-10-07-march-waypoints ruling 6), read
## only: for each carried load of data/army/army_carry_loads.csv, the day the column
## would arrive (the courier's ride, then the march at that load's pace along
## its route), the supplies a train of that load holds, the days they last, and
## how many days of the march its stores would not cover. It sets out with the
## full load when it stands in a realm town (the town tops it up, SupplyLines),
## else with what it holds now; a supply line is not counted.


## [{days, label, pace_permille, arrive, march, units, lasts, set_out, short}],
## one a load, in the table's order. `waypoints` in pack px.
static func carry_rows(repo: DataRepository, state: GameState, code: String, dest_px: Vector2,
		waypoints: Array) -> Array:
	var reg := ArmySystem.regiment(repo, code, state)
	var entry := ArmySystem.state_of(repo, state, code)
	var out: Array = []
	if reg.is_empty() or entry.is_empty():
		return out
	var use := ArmySystem.supply_use(repo, reg, state)
	var ride := CourierSystem.eta_days(repo, state, CourierSystem.ORDINARY, code) \
		if CourierSystem.carries_orders(reg) and not KingSystem.can_command(repo, state, code) else 0
	var topped := SupplyLines.home_town(repo, state, code) != ""
	var held := int(entry.get("supplies", 0))
	for row: Dictionary in repo.army_carry_loads:
		var days := int(row["days"])
		var arrive := CourierSystem.arrival_days(repo, state, code, dest_px, Vector2(-1, -1), ride, waypoints, days)
		var march := maxi(0, arrive - ride)
		@warning_ignore("integer_division")  # whole units, rounded UP as the town's top-up rounds them
		var units := (use * days + Calendar.DAYS_PER_TICK - 1) / Calendar.DAYS_PER_TICK
		var lasts := ArmySystem.days_in_hand(units, use)
		var set_out := ArmySystem.days_in_hand(units if topped else held, use)
		out.append({"days": days, "label": String(row["label"]), "pace_permille": int(row["pace_permille"]),
			"arrive": arrive, "march": march, "units": units, "lasts": lasts, "set_out": set_out,
			"short": maxi(0, march - set_out)})
	return out


## The rows of a march drawn for SEVERAL regiments (spec 2026-10-08-war-room-
## draw-orders ruling 9): `per` code -> its carry_rows; one row a load, its
## arrival the LAST to arrive, its supplies the sum of the trains, its
## shortfall the worst — the regiments' own rows say each.
static func group_rows(per: Dictionary) -> Array:
	var codes: Array = per.keys()
	codes.sort()
	var out: Array = []
	for code: String in codes:
		var rows: Array = per[code]
		for i in rows.size():
			var r: Dictionary = rows[i]
			if i >= out.size():
				out.append(r.duplicate())
				continue
			var o: Dictionary = out[i]
			o["arrive"] = maxi(int(o["arrive"]), int(r["arrive"]))
			o["march"] = maxi(int(o["march"]), int(r["march"]))
			o["units"] = int(o["units"]) + int(r["units"])
			o["short"] = maxi(int(o["short"]), int(r["short"]))
			o["set_out"] = mini(int(o["set_out"]), int(r["set_out"]))
			o["lasts"] = mini(int(o["lasts"]), int(r["lasts"]))
	return out
