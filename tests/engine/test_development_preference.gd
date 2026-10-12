extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A ruler's hidden development preference and the opinion a decree earns him
## (spec 2026-10-12-development-axes §6). Hand values: key 6 per 100.

var repo: DataRepository
var s: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)


func _char_with(traits: Array) -> Character:
	var c: Character = s.characters[String(s.council.values()[0])]
	c.traits = traits
	return c


func _set_traits(a: String, ra: int, b: String = "", rb: int = 0) -> Array:
	repo.traits[a] = {"trait_code": a, "dev_renaissance": ra, "dev_chivalry": 0}
	var out: Array = [a]
	if b != "":
		repo.traits[b] = {"trait_code": b, "dev_renaissance": rb, "dev_chivalry": 0}
		out.append(b)
	return out


func test_preference_sums_and_clamps() -> void:
	var c := _char_with(_set_traits("t_a", 60, "t_b", 70))
	assert_eq(DevelopmentSystem.preference(repo, c, "renaissance"), 100)
	c.traits = _set_traits("t_a", 60, "t_b", -90)
	assert_eq(DevelopmentSystem.preference(repo, c, "renaissance"), -30)
	c.traits = []
	assert_eq(DevelopmentSystem.preference(repo, c, "renaissance"), 0)


func _isolate(c: Character) -> void:
	# Only this one minister sits on the council.
	var keep := c.id
	for seat: String in s.council.keys():
		if String(s.council[seat]) != keep:
			s.council.erase(seat)


func test_decree_opinion_for_favouring_and_opposing_ministers() -> void:
	var c := _char_with(_set_traits("t_a", 50))
	_isolate(c)
	var before := c.opinion
	var log_n := c.opinion_log.size()
	var out := DevelopmentSystem.decree_opinions(repo, s, "patronage", "scholars")
	assert_eq(out.size(), 1)
	assert_eq(int(out[0]["delta"]), 3)
	assert_eq(String(out[0]["character_id"]), c.id)
	assert_eq(c.opinion, before + 3)
	c.traits = _set_traits("t_a", -50)
	out = DevelopmentSystem.decree_opinions(repo, s, "patronage", "scholars")
	assert_eq(int(out[0]["delta"]), -3)
	c.traits = []
	log_n = c.opinion_log.size()
	out = DevelopmentSystem.decree_opinions(repo, s, "patronage", "scholars")
	assert_eq(out.size(), 0)
	assert_eq(c.opinion_log.size(), log_n)


func test_decree_reason_is_nonempty() -> void:
	var c := _char_with(_set_traits("t_a", 50))
	_isolate(c)
	var out := DevelopmentSystem.decree_opinions(repo, s, "patronage", "scholars")
	var reason := String(out[0]["reason"])
	assert_ne(reason, "")
	assert_string_contains(reason, "favours renaissance development")
	assert_eq(String(c.opinion_log.back()["reason"]), reason)


func test_undecreed_or_neutral_law_changes_no_opinion() -> void:
	var c := _char_with(_set_traits("t_a", 50))
	_isolate(c)
	var out := DevelopmentSystem.decree_opinions(repo, s, "tax_rate", "10")
	assert_eq(out.size(), 0)


func test_preference_is_not_in_save_state() -> void:
	var c := _char_with(_set_traits("t_a", 50))
	for k: String in c.to_dict().keys():
		assert_false(k.contains("preference"))


func test_law_set_orders_carry_the_opinion_in_drift() -> void:
	var c := _char_with(_set_traits("t_a", 50))
	_isolate(c)
	s.metrics["treasury"] = 5000.0
	var actions := ActionSystem.new(repo)
	var req := ActionRequest.make("LAW_SET", {"law": "patronage", "value": "scholars"})
	if actions.validate(req, s) != "":
		pending("patronage cannot be decreed in this fixture")
		return
	var out := actions.execute(req, s)
	var found := false
	for d: Dictionary in out["drift"]:
		if String(d["reason"]).begins_with("decreed"):
			found = true
	assert_true(found)
