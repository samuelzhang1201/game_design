extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Foreign realms follow their ruler (spec 2026-10-12-development-axes §6).
## Hand values: start 100, target = 100 + preference x 5, step 5 a month.

var repo: DataRepository
var s: GameState
var realm: String


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	realm = _foreign()[0]


func _foreign() -> Array:
	var out: Array = []
	var player := repo.resolve_realm("player_realm")
	for r: String in DevelopmentSystem.realms(repo, s):
		if r != player:
			out.append(r)
	return out


## Give the realm's ruler one test trait leaning `ren` / `chiv`.
func _lean(ren: int, chiv: int) -> void:
	repo.traits["t_lean"] = {"trait_code": "t_lean", "dev_renaissance": ren, "dev_chivalry": chiv}
	DevelopmentSystem.ruler_of(repo, s, realm).traits = ["crowned_head", "t_lean"]


func _line(lines: Array, axis: String) -> Dictionary:
	for l: Dictionary in lines:
		if String(l["realm"]) == realm and String(l["axis"]) == axis:
			return l
	return {}


func test_ai_steps_toward_target() -> void:
	_lean(80, 0)
	s.development[realm]["renaissance"] = 100
	var l := _line(DevelopmentSystem.ai_lines(repo, s), "renaissance")
	assert_eq(int(l["delta"]), 5, "target 500, step 5")
	s.development[realm]["renaissance"] = 497
	l = _line(DevelopmentSystem.ai_lines(repo, s), "renaissance")
	assert_eq(int(l["delta"]), 3, "497 -> 500, not 502")


func test_step_follows_the_balance_key() -> void:
	_lean(80, 0)
	repo.balance["dev_ai_step"] = 10.0
	var l := _line(DevelopmentSystem.ai_lines(repo, s), "renaissance")
	assert_eq(int(l["delta"]), 10)


func test_negative_preference_steps_down() -> void:
	_lean(-20, 0)
	var l := _line(DevelopmentSystem.ai_lines(repo, s), "renaissance")
	assert_eq(int(l["delta"]), -5, "target 0, from 100 one step down")
	s.development[realm]["renaissance"] = 2
	l = _line(DevelopmentSystem.ai_lines(repo, s), "renaissance")
	assert_eq(int(l["delta"]), -2)


func test_zero_preference_holds_at_start() -> void:
	_lean(0, 0)
	var lines := DevelopmentSystem.ai_lines(repo, s)
	assert_true(_line(lines, "renaissance").is_empty())
	assert_true(_line(lines, "chivalry").is_empty())


func test_realm_without_ruler_holds_and_does_not_error() -> void:
	s.characters.erase(DevelopmentSystem.ruler_of(repo, s, realm).id)
	assert_null(DevelopmentSystem.ruler_of(repo, s, realm))
	var lines := DevelopmentSystem.ai_lines(repo, s)
	assert_true(_line(lines, "renaissance").is_empty())
	DevelopmentSystem.settle_month(repo, s)
	assert_eq(DevelopmentSystem.score(s, realm, "renaissance"), 100)


func test_ruler_lookup_uses_kingdom_and_crowned_head() -> void:
	var foreign := _foreign()
	assert_eq(foreign.size(), 3)
	var seen: Array = []
	for r: String in foreign:
		var c := DevelopmentSystem.ruler_of(repo, s, r)
		assert_not_null(c, "ruler of " + r)
		assert_true(c.traits.has("crowned_head"))
		assert_false(seen.has(c.id))
		seen.append(c.id)
	assert_null(DevelopmentSystem.ruler_of(repo, s, repo.resolve_realm("player_realm")))


func test_the_three_rulers_differ() -> void:
	var lean: Dictionary = {}
	for r: String in _foreign():
		var c := DevelopmentSystem.ruler_of(repo, s, r)
		lean[c.id] = [DevelopmentSystem.preference(repo, c, "renaissance"),
			DevelopmentSystem.preference(repo, c, "chivalry")]
	assert_gt(lean["char_king_osric"][1], 0)
	assert_lte(lean["char_king_osric"][0], 0)
	assert_gt(lean["char_queen_isabeau"][0], 0)
	assert_lte(absi(lean["char_emperor"][0]), 10)
	assert_lte(absi(lean["char_emperor"][1]), 10)


func _scores(g: GameState) -> Dictionary:
	return g.development.duplicate(true)


func test_same_seed_same_scores_after_twelve_months() -> void:
	var a := SuiteData.campaign(repo, 7)
	var b := SuiteData.campaign(repo, 7)
	var ea := TickEngine.new(repo)
	var eb := TickEngine.new(repo)
	for i in 12:
		ea.advance(a)
		eb.advance(b)
	assert_eq(_scores(a), _scores(b))
	var moved := false
	for r: String in _foreign():
		for axis: String in DevelopmentSystem.AXES:
			if DevelopmentSystem.score(a, r, axis) != 100:
				moved = true
	assert_true(moved, "a foreign realm has moved in a year")


func test_ai_lines_carry_reasons() -> void:
	_lean(80, -40)
	var lines := DevelopmentSystem.ai_lines(repo, s)
	var up := _line(lines, "renaissance")
	var down := _line(lines, "chivalry")
	var name := DevelopmentSystem.ruler_of(repo, s, realm).display_name
	assert_eq(String(up["reason"]), "%s favours renaissance" % name)
	assert_eq(String(down["reason"]), "%s turns from chivalry" % name)


func test_foreign_lines_are_not_the_players_outcome() -> void:
	_lean(80, 0)
	var before := s.recent_outcomes.size()
	var out := DevelopmentSystem.settle_month(repo, s)
	var foreign := out.filter(func(l: Dictionary) -> bool: return String(l["realm"]) == realm)
	assert_false(foreign.is_empty())
	for o: Dictionary in s.recent_outcomes.slice(before):
		for e: Dictionary in o["effects"]:
			assert_ne(String(e["reason"]), String(foreign[0]["reason"]))
