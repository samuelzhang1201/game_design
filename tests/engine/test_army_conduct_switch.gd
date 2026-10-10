extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const H := preload("res://tests/engine/conduct_helpers.gd")
## ArmyConduct switching (spec 2026-10-10-foraging-and-desertion §3.3 steps 1-6):
## the start and stop lines, the unlawful incident once a month, grey land and
## Havoc, hand-computed from the balance defaults (start 3 days / 25 morale / 5
## training, obey 2 / 20 / 3, stop 10 days and 40 morale, legitimacy 3,
## grievance 10 or 5 protected).

var repo: DataRepository
var state: GameState
var code: String
var foreign: String


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 11)
	code = H.land_unit(repo, state)
	foreign = H.foreign_province(repo, state)
	state.tick = 5
	state.day = 1
	state.metrics["legitimacy"] = 50.0
	state.conduct_marks.clear()
	state.grievance.clear()
	_put(code, 20, 50, 50)
	_law(code, "plunder", "forbid")


## A unit with `days` whole days in hand, the given morale and training.
func _put(c: String, days: int, morale: int, training: int) -> void:
	var reg := ArmySystem.regiment(repo, c, state)
	var use := ArmySystem.supply_use(repo, reg, state)
	var entry: Dictionary = state.regiments[c]
	var s := 0
	while ArmySystem.days_in_hand(s, use) < days:
		s += 1
	entry["supplies"] = s
	entry["morale"] = morale
	entry["training"] = training
	entry["forage"] = ""
	assert_eq(ArmySystem.days_in_hand(s, use), days)


func _law(c: String, law: String, value: String) -> void:
	var key: String = LawSystem.UNIT_PREFIX + c
	var row: Dictionary = state.law_in_force.get(key, {})
	row[law] = {"value": value, "decree_id": 1}
	state.law_in_force[key] = row


func _forage(c: String) -> String:
	return String(state.regiments[c].get("forage", ""))


func _types(events: Array) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		out.append(String(e["type"]))
	return out


func test_allow_is_on_in_enemy_land() -> void:
	_law(code, "plunder", "allow")
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "law")
	state.regiments[code]["forage"] = "law"
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "law")
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.HOME), "")


func test_each_line_starts_a_forbid_unit() -> void:
	_put(code, 2, 50, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_put(code, 20, 24, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_put(code, 20, 50, 4)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_put(code, 20, 50, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "")


func test_stop_needs_both() -> void:
	_put(code, 10, 39, 50)
	state.regiments[code]["forage"] = "desperate"
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_put(code, 10, 40, 50)
	state.regiments[code]["forage"] = "desperate"
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "")
	_put(code, 9, 40, 50)
	state.regiments[code]["forage"] = "desperate"
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")


func test_law_unit_under_forbid_is_rejudged() -> void:
	_put(code, 20, 50, 50)
	state.regiments[code]["forage"] = "law"
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "")
	_put(code, 2, 50, 50)
	state.regiments[code]["forage"] = "law"
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")


func test_obey_command_lowers_the_lines() -> void:
	_put(code, 2, 50, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_put(code, 20, 24, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_put(code, 20, 50, 4)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_law(code, "obey_command", "on")
	assert_eq(ArmyConduct.lines(repo, state, code), {"days": 2, "morale": 20, "training": 3})
	_put(code, 2, 50, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "")
	_put(code, 1, 50, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_put(code, 20, 20, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "")
	_put(code, 20, 19, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")
	_put(code, 20, 50, 3)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "")
	_put(code, 20, 50, 2)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.ENEMY), "desperate")


func test_grey_land_only_at_zero_supply() -> void:
	var kingdom := MapOwnership.owner_of(repo, state, foreign)
	_put(code, 1, 50, 50)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.GREY), "")
	var ev := ArmyConduct.switch(repo, state, code, foreign, Forage.GREY)
	assert_eq(_forage(code), "")
	assert_eq(ev.size(), 0)
	_put(code, 0, 50, 50)
	ev = ArmyConduct.switch(repo, state, code, foreign, Forage.GREY)
	assert_eq(_forage(code), "desperate")
	assert_eq(_types(ev), ["forage_incident"])
	assert_eq(ev[0]["regiment"], code)
	assert_eq(ev[0]["province"], foreign)
	assert_eq(ev[0]["kingdom"], kingdom)
	assert_almost_eq(float(state.metrics["legitimacy"]), 47.0, 0.001)
	assert_eq(int(state.grievance[kingdom]), 10)
	assert_true(state.hazards.has("forage_" + foreign))


func test_grey_grievance_halves_with_protect_women() -> void:
	var kingdom := MapOwnership.owner_of(repo, state, foreign)
	_law(code, "protect_women", "on")
	_put(code, 0, 50, 50)
	ArmyConduct.switch(repo, state, code, foreign, Forage.GREY)
	assert_eq(int(state.grievance[kingdom]), 5)


func test_enemy_start_files_unlawful_no_grievance_no_hazard() -> void:
	_put(code, 2, 50, 50)
	var ev := ArmyConduct.switch(repo, state, code, foreign, Forage.ENEMY)
	assert_eq(_types(ev), ["forage_unlawful"])
	assert_almost_eq(float(state.metrics["legitimacy"]), 47.0, 0.001)
	assert_true(state.grievance.is_empty())
	assert_false(state.hazards.has("forage_" + foreign))


func test_none_and_home_never() -> void:
	var home := H.home_province(repo, state)
	_put(code, 0, 0, 0)
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.NONE), "")
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.HOME), "")
	state.regiments[code]["forage"] = "desperate"
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.HOME), "")
	assert_eq(ArmyConduct.wants(repo, state, code, Forage.NONE), "")
	var ev := ArmyConduct.switch(repo, state, code, home, Forage.HOME)
	assert_eq(_forage(code), "")
	assert_eq(ev.size(), 0)


func test_incident_once_per_unit_per_month() -> void:
	_put(code, 2, 50, 50)
	var ev := ArmyConduct.switch(repo, state, code, foreign, Forage.ENEMY)
	assert_eq(ev.size(), 1)
	assert_almost_eq(float(state.metrics["legitimacy"]), 47.0, 0.001)
	# stops, then restarts the next day
	_put(code, 20, 50, 50)
	state.regiments[code]["forage"] = "desperate"
	ArmyConduct.switch(repo, state, code, foreign, Forage.ENEMY)
	assert_eq(_forage(code), "")
	state.day = 2
	_put(code, 2, 50, 50)
	ev = ArmyConduct.switch(repo, state, code, foreign, Forage.ENEMY)
	assert_eq(_forage(code), "desperate")
	assert_eq(ev.size(), 0)
	assert_almost_eq(float(state.metrics["legitimacy"]), 47.0, 0.001)
	# a new month charges again
	_put(code, 20, 50, 50)
	state.regiments[code]["forage"] = "desperate"
	ArmyConduct.switch(repo, state, code, foreign, Forage.ENEMY)
	state.tick += 1
	_put(code, 2, 50, 50)
	ev = ArmyConduct.switch(repo, state, code, foreign, Forage.ENEMY)
	assert_eq(ev.size(), 1)
	assert_almost_eq(float(state.metrics["legitimacy"]), 44.0, 0.001)


func test_mark_once() -> void:
	assert_true(ArmyConduct.mark_once(repo, state, "k"))
	assert_false(ArmyConduct.mark_once(repo, state, "k"))
	assert_eq(int(state.conduct_marks["k"]), state.tick)
	state.tick += 1
	assert_true(ArmyConduct.mark_once(repo, state, "k"))


func test_lay_hazard_is_idempotent() -> void:
	ArmyConduct.lay_hazard(repo, state, foreign)
	var h: Dictionary = state.hazards["forage_" + foreign]
	assert_eq(h["kind"], "Raided")
	assert_eq(h["source"], "forage")
	assert_eq(int(h["start"]), state.tick)
	assert_eq(int(h["end"]), state.tick + int(Hazards.kind_of(repo, "Raided").get("months")))
	assert_eq(h["cells"], MapManors.manors_of_province(repo, foreign, state))
	var rev := state.hazards_rev
	state.tick += 1
	ArmyConduct.lay_hazard(repo, state, foreign)
	assert_eq(state.hazards_rev, rev)
	assert_eq(int(state.hazards["forage_" + foreign]["start"]), state.tick - 1)


func _pair() -> String:
	var all := H.land_units(repo, state)
	assert_gte(all.size(), 2)
	var other := String(all[1])
	for k: String in ["x_m", "y_m"]:
		state.regiments[other][k] = state.regiments[code][k]
	_put(other, 20, 50, 50)
	return other


func test_havoc_spreads_unless_forbidden() -> void:
	var other := _pair()
	var here := ArmySystem.province_of(repo, state, ArmySystem.regiment(repo, code, state))
	assert_eq(ArmySystem.province_of(repo, state, ArmySystem.regiment(repo, other, state)), here)
	_put(code, 2, 50, 50)
	var ev := ArmyConduct.switch(repo, state, code, here, Forage.ENEMY)
	assert_eq(_forage(code), "desperate")
	assert_eq(_forage(other), "desperate")
	assert_eq(_types(ev), ["forage_unlawful", "forage_havoc"])
	assert_eq(ev[1]["province"], here)
	assert_eq(ev[1]["regiment"], code)
	assert_almost_eq(float(state.metrics["legitimacy"]), 47.0, 0.001)
	# no_havoc on: only the first
	state.metrics["legitimacy"] = 50.0
	state.conduct_marks.clear()
	state.regiments[code]["forage"] = ""
	state.regiments[other]["forage"] = ""
	_law(code, "no_havoc", "on")
	_put(code, 2, 50, 50)
	ev = ArmyConduct.switch(repo, state, code, here, Forage.ENEMY)
	assert_eq(_forage(code), "desperate")
	assert_eq(_forage(other), "")
	assert_eq(_types(ev), ["forage_unlawful"])


func test_follower_not_restarted() -> void:
	var other := _pair()
	var here := ArmySystem.province_of(repo, state, ArmySystem.regiment(repo, code, state))
	state.regiments[other]["forage"] = "law"
	_put(code, 2, 50, 50)
	var ev := ArmyConduct.switch(repo, state, code, here, Forage.ENEMY)
	assert_eq(_forage(other), "law")
	# the follower files nothing of its own (a third unit of the province may
	# still spread Havoc, which is the starter's one havoc event)
	assert_eq(_types(ev).count("forage_unlawful"), 1)
	assert_eq(_types(ev).count("forage_incident"), 0)
	for e: Dictionary in ev:
		assert_eq(e["regiment"], code)
	assert_almost_eq(float(state.metrics["legitimacy"]), 47.0, 0.001)
