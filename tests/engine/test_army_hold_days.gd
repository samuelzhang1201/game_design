extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A line held day after day (spec 2026-10-11-war-room-front-line-design §3,
## the architect's T3.1 / T3.2): hold_days counts the days settled in hold,
## not marching and in no battle, capped at camp_after_days; a march, another
## stance or a battle resets it; a camp is only in the field; it saves as an int.

var repo: DataRepository
var s: GameState
var code := ""


func before_each() -> void:
	repo = SuiteData.repo()
	repo.balance["camp_after_days"] = 5.0
	s = SuiteData.campaign(repo, 7)
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break
	var e: Dictionary = s.regiments[code]
	e["order"] = ArmySystem.ORDER_GARRISON
	e["stance"] = "hold"
	# in the field: off any town's seat or camp
	e["x_m"] = 1
	e["y_m"] = 1
	e["dest_x_m"] = 1
	e["dest_y_m"] = 1
	e.erase("camp_town")
	for t: String in s.town_seat.keys():
		if String(s.town_seat[t]) == code:
			s.town_seat.erase(t)


func test_five_days_held_make_a_camp_and_the_count_is_capped() -> void:
	for d in 4:
		ArmySystem.hold_day(repo, s)
	assert_eq(int(s.regiments[code]["hold_days"]), 4)
	assert_false(ArmySystem.camped(repo, s, code))
	ArmySystem.hold_day(repo, s)
	assert_eq(int(s.regiments[code]["hold_days"]), 5)
	assert_true(ArmySystem.camped(repo, s, code))
	for d in 3:
		ArmySystem.hold_day(repo, s)
	assert_eq(int(s.regiments[code]["hold_days"]), 5, "capped")


func test_a_march_a_stance_or_a_battle_resets_the_count() -> void:
	for d in 5:
		ArmySystem.hold_day(repo, s)
	var e: Dictionary = s.regiments[code]
	e["order"] = ArmySystem.ORDER_MARCH
	ArmySystem.hold_day(repo, s)
	assert_false(e.has("hold_days"), "a march")
	e["order"] = ArmySystem.ORDER_GARRISON
	e["stance"] = "steady"
	ArmySystem.hold_day(repo, s)
	assert_false(e.has("hold_days"), "another stance")
	e["stance"] = "hold"
	s.battles.append({"id": 1, "att": [code], "def": ["foe"]})
	ArmySystem.hold_day(repo, s)
	assert_false(e.has("hold_days"), "a battle")
	s.battles.clear()
	ArmySystem.hold_day(repo, s)
	assert_eq(int(e["hold_days"]), 1, "counting again from one")
	repo.balance["camp_after_days"] = 0.0
	ArmySystem.hold_day(repo, s)
	assert_false(e.has("hold_days"), "0 never counts")
	assert_false(ArmySystem.camped(repo, s, code))


func test_no_camp_beside_a_town_and_the_count_saves_as_an_int() -> void:
	for d in 5:
		ArmySystem.hold_day(repo, s)
	assert_true(ArmySystem.camped(repo, s, code))
	var held := ""
	for t: String in repo.burgs:
		if ArmyGround.holds(repo, s, repo.resolve_realm("player_realm"), t):
			held = t
			break
	assert_ne(held, "", "the crown holds a town")
	s.regiments[code]["camp_town"] = held
	assert_false(ArmySystem.camped(repo, s, code), "camped round a town already")
	s.regiments[code].erase("camp_town")
	assert_true(ArmySystem.camped(repo, s, code), "back in the field")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), false)
	assert_eq(typeof(back.regiments[code]["hold_days"]), TYPE_INT)
	assert_eq(int(back.regiments[code]["hold_days"]), 5)
