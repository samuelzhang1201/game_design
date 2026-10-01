extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

## A character's authored row (founding_council.csv or roles.csv).
func _row(id: String) -> Dictionary:
	for r: Dictionary in data.founding + data.roles:
		if String(r["id"]) == id:
			return r
	return {}

func test_builds_full_roster_with_five_seated() -> void:
	var s := SuiteData.campaign(data, 42)
	# the founding council + the extended roles (data/roles.csv), each once
	assert_eq(s.characters.size(), data.founding.size() + data.roles.size())
	assert_eq(s.council.size(), 5, "only seated ministers occupy council")
	for seat in ["chancellor", "marshal", "steward", "spymaster", "chaplain"]:
		assert_true(s.council.has(seat), seat + " seated")

func test_roster_roles_carry_taxonomy_and_role_metrics() -> void:
	var s := SuiteData.campaign(data, 42)
	var king: Character = s.characters["you"]
	assert_eq(king.category, "player")
	assert_eq(king.family_name, String(_row("you")["family_name"]))
	# Not a literal: the king lives in whatever kingdom the loaded map binds
	# player_realm to, so this survives a map swap.
	assert_eq(king.kingdom, data.resolve_realm("player_realm"))
	assert_true(data.kingdoms.has(king.kingdom), "and it is a real kingdom")
	# The role metrics and the personal data (the story background's ages)
	# come from the authored row.
	for key in ["prestige", "influence", "age"]:
		assert_eq(int(king.attributes[key]), int(_row("you")[key]), key)
	assert_eq(int(s.characters["char_princess"].attributes["age"]), int(_row("char_princess")["age"]))
	var osric: Character = s.characters["char_king_osric"]
	assert_eq(osric.category, "foreign")
	assert_eq(osric.kingdom, data.resolve_realm("raider_realm"))
	# Founding rows gained the same columns.
	var aldwin: Character = s.characters["char_chancellor"]
	assert_eq(aldwin.category, "council")
	assert_eq(int(aldwin.attributes["influence"]), int(_row("char_chancellor")["influence"]))

func test_trait_modifiers_applied() -> void:
	var s := SuiteData.campaign(data, 42)
	var brandt: Character = s.characters[s.council["marshal"]]
	# base temper 65 + wrathful +35 + bold +10 + noble_born +5 + born_soldier +5 = 120 -> clamp 100
	assert_eq(brandt.attributes["temper"], 100)
	# base sk_martial 13 + born_soldier +5 + bold +2 + noble_born +2 + wrathful +1 = 23 -> clamp 20
	assert_eq(brandt.skills["sk_martial"], 20)

func test_opinion_change_logs_reason_and_clamps() -> void:
	var c := Character.new()
	c.opinion = 95
	c.change_opinion(10, "test reason", 3)
	assert_eq(c.opinion, 100)
	assert_eq(c.opinion_log.size(), 1)
	assert_eq(c.opinion_log[0]["reason"], "test reason")

func test_character_round_trip() -> void:
	var s := SuiteData.campaign(data, 42)
	var c: Character = s.characters[s.council["chaplain"]]
	c.change_opinion(-5, "rt", 1)
	var c2 := Character.from_dict(c.to_dict())
	assert_eq(c2.display_name, "Father Odo")
	assert_eq(c2.opinion, c.opinion)
	assert_eq(c2.opinion_log[0]["reason"], "rt")
	assert_eq(c2.ideology["orthodoxy"], c.ideology["orthodoxy"])
