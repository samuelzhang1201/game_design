extends GutTest
const People := preload("res://tests/fixtures/military_people.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://scripts/engine/military_roster.gd")
const Play := preload("res://tests/invasion_play.gd")
## The scouting fan and the contact and scout letters (spec 2026-10-14-unit-
## clearance-and-scouting-design §c, owner 2026-10-14): a MARCHING crown land unit
## sees a sector ahead of it (data/army/army_scouting.csv: infantry 15 km,
## cavalry 30, a 120 degree sweep), inclusive at the radius and at +-60 degrees;
## a foe in it is told in a SCOUT letter (credible), a foe within battle_contact_km
## of any land unit of ours in a CONTACT letter (the truth column); one letter an
## episode (scout_report_gap_days 3). Hand-placed units, whole metres, no
## random number.

var repo: DataRepository
var s: GameState
var far := Vector2i.ZERO      # open ground, every held town far off
var horse := ""               # a crown unit of cavalry
var foot := ""                # a crown unit of infantry
var foe := ""                 # a foe unit, moved about by the tests
var other := ""               # another, left far away


func before_each() -> void:
	horse = ""
	foot = ""
	repo = SuiteData.open_country(SuiteData.repo())
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()
	s = SuiteData.campaign(repo, 11)
	s.tick = 1
	s.day = 5
	Intel.dev_all = false
	repo.balance["player_sight_km"] = 1.0       # the circle out of the way: only sectors and contact count
	repo.balance["player_sight_estimate_quality"] = 1000.0
	repo.balance["spy_width_best"] = 100.0
	repo.balance["spy_width_worst"] = 450.0
	(repo.intel_facts["foe_troops"] as Dictionary)["round_to"] = 100
	var best := -1
	for h: String in EnemyAi.host_codes(s):
		var at := EnemyAi.home_m(repo, h)
		var d := _nearest_town_m(at)
		if d > best:
			best = d
			far = at
	Play.park_army(repo, s, far)
	var realm := repo.resolve_realm("player_realm")
	for code: String in s.regiments.keys():
		var reg := ArmySystem.regiment(repo, code, s)
		if String(reg.get("is_naval", "0")) == "1" or ArmySystem.personnel_capacity(repo, reg) < 400:
			continue
		var arm := MapObjects.regiment_arm(repo, reg)
		if arm == "cavalry" and (horse == "" or code < horse):
			horse = code
		if arm == "infantry" and (foot == "" or code < foot):
			foot = code
	assert_ne(horse, "", "the pack has a cavalry unit of the crown's")
	assert_ne(foot, "", "and an infantry one")
	assert_eq(String(ArmySystem.regiment(repo, horse, s)["kingdom_code"]), realm)
	var codes: Array = s.foes.keys()
	codes.sort()
	foe = String(codes[0])
	other = String(codes[1])
	for c: String in codes:
		Play.place(repo, s, c, far + Vector2i(900000, 0), ArmySystem.ORDER_STANDBY)   # out of everyone's way


func _nearest_town_m(at: Vector2i) -> int:
	var best := 1 << 40
	for t: String in TownStores.realm_towns(repo, s):
		best = mini(best, int(Vector2(ArmyGround.town_point_m(repo, t) - at).length()))
	return best


## `code` of ours marching east from `at` (a far destination, the straight road).
func _march_east(code: String, at: Vector2i) -> void:
	Play.place(repo, s, code, at, ArmySystem.ORDER_STANDBY)
	ArmySystem.set_march_m(repo, s, code, at + Vector2i(300000, 0))


func _put_foe(at: Vector2i) -> void:
	Play.place(repo, s, foe, at, ArmySystem.ORDER_STANDBY)


func _fan(code: String) -> Dictionary:
	for f: Dictionary in Sighting.sectors(repo, s):
		if String(f["code"]) == code:
			return f
	return {}


func _letters(kind: String) -> Array:
	return Play.letters(s, kind)


func _next_day() -> void:
	s.day += 1


## --- the sector -----------------------------------------------------------------

func test_the_shapes_are_the_table() -> void:
	_march_east(horse, far)
	_march_east(foot, far + Vector2i(0, 20000))
	assert_eq(Sighting.scout_shape(repo, s, horse), {"r_m": 30000, "arc_deg": 120})
	assert_eq(Sighting.scout_shape(repo, s, foot), {"r_m": 15000, "arc_deg": 120})
	assert_eq(Sighting.scout_shape(repo, s, foe), {}, "a foe scouts for no one")


func test_a_standing_unit_sweeps_no_sector() -> void:
	Play.place(repo, s, horse, far, ArmySystem.ORDER_GARRISON)
	assert_eq(Sighting.scout_shape(repo, s, horse), {})
	_put_foe(far + Vector2i(10000, 0))
	assert_eq(Sighting.scouted(repo, s, {}), {}, "a garrison sees no sector")
	assert_false(foe in Sighting.seen_foes(repo, s), "and the circle is 1 km here")


func test_the_cavalry_sector_reaches_30_km_inclusive() -> void:
	_march_east(horse, far)
	assert_eq(ArmySystem.heading_of(repo, s, horse), Vector2.RIGHT)
	_put_foe(far + Vector2i(30000, 0))
	assert_true(foe in Sighting.seen_foes(repo, s), "exactly 30 km: inside")
	_put_foe(far + Vector2i(30001, 0))
	assert_false(foe in Sighting.seen_foes(repo, s), "30001 m: out")


func test_the_infantry_sector_reaches_15_km() -> void:
	_march_east(foot, far)
	_put_foe(far + Vector2i(15000, 0))
	assert_true(foe in Sighting.seen_foes(repo, s))
	_put_foe(far + Vector2i(15001, 0))
	assert_false(foe in Sighting.seen_foes(repo, s))
	_put_foe(far + Vector2i(20000, 0))
	assert_false(foe in Sighting.seen_foes(repo, s), "cavalry's 30 km is not the foot's")


func test_the_sector_is_60_degrees_either_side() -> void:
	_march_east(horse, far)
	var fan := _fan(horse)
	# 10 km out at +60 (south, y down) and -60 degrees: 5000 m along, 8660 across
	assert_true(Sighting.in_sector(far + Vector2i(5000, 8660), fan))
	assert_true(Sighting.in_sector(far + Vector2i(5000, -8660), fan))
	assert_false(Sighting.in_sector(far + Vector2i(5000, 8700), fan), "past 60 degrees")
	assert_false(Sighting.in_sector(far + Vector2i(5000, -8700), fan))
	assert_false(Sighting.in_sector(far + Vector2i(-100, 0), fan), "behind it")
	assert_true(Sighting.in_sector(far, fan), "the apex")


## --- the letters -------------------------------------------------------------------

func test_a_scout_letter_once_an_episode() -> void:
	_march_east(horse, far)
	_put_foe(far + Vector2i(20000, 0))
	Sighting.scout_day(repo, s)
	var ls := _letters("scout")
	assert_eq(ls.size(), 1)
	assert_eq(String(ls[0]["column"]), "credible")
	assert_eq(String(ls[0]["subject"]["kind"]), "point")
	var text := String((ls[0]["facts"] as Array)[0]["text"])
	var reg := ArmySystem.regiment(repo, foe)
	assert_true(text.contains(String(reg["label"])), "the foe's unit: " + text)
	assert_true(text.contains(String(ArmySystem.regiment(repo, horse)["label"])), "which of ours saw it")
	assert_true(text.contains("standing"), "what it is doing")
	assert_false(text.contains("{"), "no template slot left open: " + text)
	var about := Sighting.about(repo, Sighting.men_of(repo, s, foe), 1000, 0)
	assert_true(text.contains(Intel.num(about)), "about its men")
	# the days after: no more while it stays in view
	for d in 6:
		_next_day()
		Sighting.scout_day(repo, s)
	assert_eq(_letters("scout").size(), 1, "one an episode")
	# it leaves the sector for more than the gap, and comes back
	_put_foe(far + Vector2i(0, 90000))
	for d in 5:
		_next_day()
		Sighting.scout_day(repo, s)
	_put_foe(far + Vector2i(20000, 0))
	_next_day()
	Sighting.scout_day(repo, s)
	assert_eq(_letters("scout").size(), 2, "a new episode, a new letter")
	assert_eq(_letters("contact").size(), 0)


func test_a_foe_at_hand_is_a_contact_letter_in_the_truth_column() -> void:
	Play.place(repo, s, horse, far, ArmySystem.ORDER_GARRISON)
	_put_foe(far + Vector2i(3000, 0))
	Sighting.scout_day(repo, s)
	var ls := _letters("contact")
	assert_eq(ls.size(), 1)
	assert_eq(String(ls[0]["column"]), "truth")
	assert_eq(_letters("scout").size(), 0, "not also a scout letter")
	var entry: Dictionary = s.scout_log[foe]
	assert_eq(int(entry["contact"]), s.absolute_day())
	assert_eq(int(entry["scout"]), s.absolute_day())
	_next_day()
	Sighting.scout_day(repo, s)
	assert_eq(_letters("contact").size(), 1, "one an episode")


func test_a_foe_without_men_is_dropped_from_the_log() -> void:
	Play.place(repo, s, horse, far, ArmySystem.ORDER_GARRISON)
	_put_foe(far + Vector2i(3000, 0))
	Sighting.scout_day(repo, s)
	assert_true(s.scout_log.has(foe))
	assert_false(People.move(repo, s, foe, "fit", "dead", ArmySystem.fit_count(repo, s, foe), "scouted_unit_destroyed").has("error"))
	Sighting.scout_day(repo, s)
	assert_false(s.scout_log.has(foe))


func test_scouting_draws_no_random_number_and_the_log_saves() -> void:
	_march_east(horse, far)
	_put_foe(far + Vector2i(20000, 0))
	var before := JSON.stringify(s.rng.to_dict())
	Sighting.scout_day(repo, s)
	assert_eq(JSON.stringify(s.rng.to_dict()), before, "no draw")
	assert_true(s.scout_log.has(foe))
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.scout_log, s.scout_log, "the log is saved")
	var old := s.to_dict()
	old.erase("scout_log")
	assert_eq(GameState.from_dict(old).scout_log, {}, "an old save has none")
	for v: Variant in back.scout_log[foe].values():
		assert_true(v is int, "ints only")


func test_the_contact_letter_comes_before_the_battle_it_leads_to() -> void:
	# The king observes here; remote battle letters are delivered by courier.
	s.king_state["x_m"] = far.x
	s.king_state["y_m"] = far.y
	Play.place(repo, s, horse, far, ArmySystem.ORDER_GARRISON)
	_put_foe(far + Vector2i(3000, 0))
	var engine := TickEngine.new(repo)
	var blocked := engine.resolve_day(s)
	assert_eq(blocked["status"], "blocked")
	var contact := _letters("contact")
	assert_eq(contact.size(), 1, "contact told")
	assert_eq(_letters("battle").size(), 0, "the encounter pauses before fighting")
	engine.resolve_decision(s, String(blocked["decision"]["token"]), "continue")
	assert_eq(engine.resolve_day(s)["status"], "complete")
	var battle := _letters("battle")
	assert_gt(battle.size(), 0, "and a battle fought")
	if not contact.is_empty() and not battle.is_empty():
		assert_lt(int(contact[0]["id"]), int(battle[0]["id"]), "the contact letter first")


func test_a_scout_letter_is_kept_apart_from_the_columns_cap() -> void:
	assert_eq(MissiveLog.keep_group("scout"), "scout")
	assert_eq(MissiveLog.keep_group("contact"), "scout")
	assert_eq(MissiveLog.SCOUT_KINDS, ["scout", "contact"])
	repo.balance["missive_keep_scout"] = 2.0
	for i in 4:
		MissiveLog.add(repo, s, MissiveLog.make("scout", "credible", s.absolute_day(), {}, "t", []))
	assert_eq(_letters("scout").size(), 2, "the oldest leave at missive_keep_scout")
