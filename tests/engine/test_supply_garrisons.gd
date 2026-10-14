extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Home garrisons are fed (final review 1, spec 2026-10-07-army-supply-lines
## §3.2 step 4): a campaign left to run a YEAR with no orders keeps every
## land unit of the realm camped by a town above army_supply_low_days, the
## towns that run dry topped up from the depot and then the crown's stores in
## the other realm towns (owner 2026-10-07, option A), and the two pools equal
## to the towns all the while.

## "" when every camped land unit holds army_supply_low_days and the pools are
## the towns', else what is wrong.
func _check(repo: DataRepository, s: GameState, low: int) -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c), s)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		# camped by a town of the realm (ArmyGround.camped_by, spec
		# 2026-10-07-army-split-and-ground §4.1): every camped unit, the seat's
		# and the camp's beyond the town's reach alike, is fed by its town
		var town := ArmyGround.camped_by(repo, s, String(c))
		if town == "":
			continue
		# a BESIEGED town feeds its camp from its own stores alone and its supply
		# lines are cut by design (guide/siege.md): the invasion's siege, which the
		# unit clearance now lets run longer before the town falls, is not this
		# test's premise (the home garrisons in peace)
		if SiegeSystem.besieged(s, town):
			continue
		var days := ArmySystem.days_in_hand(int(s.regiments[c]["supplies"]), ArmySystem.supply_use(repo, reg, s))
		if days < low:
			return "%s has %d days on tick %d day %d" % [c, days, s.tick, s.day]
	for pool: String in TownStores.METRIC:
		var towns := TownStores.gold_of_units(repo, TownStores.total(s, pool))
		if towns != int(s.metrics[TownStores.METRIC[pool]]):
			return "%s: the towns hold %d, the metric reads %d" % [pool, towns, int(s.metrics[TownStores.METRIC[pool]])]
	return ""

func test_a_year_with_no_orders_starves_no_home_garrison() -> void:
	var repo := SuiteData.repo()
	var s := SuiteData.campaign(repo, 42)
	RealmEconomy.forget()
	var engine := TickEngine.new(repo)
	var low := int(repo.bal("army_supply_low_days"))
	engine.advance(s)   # the reign's opening tick
	var wrong := ""
	for m in Calendar.TICKS_PER_YEAR:
		for d in Calendar.DAYS_PER_TICK - 1:
			engine.advance_day(s)
			wrong = _check(repo, s, low)
			if wrong != "":
				break
		if wrong != "":
			break
		engine.advance(s)
		wrong = _check(repo, s, low)
		if wrong != "":
			break
	assert_eq(wrong, "")
	assert_eq(s.tick, 1 + Calendar.TICKS_PER_YEAR, "a year run")
	RealmEconomy.forget()
