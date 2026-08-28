extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_builds_five_ministers_seated() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(s.characters.size(), 5)
	for seat in ["chancellor", "marshal", "steward", "spymaster", "chaplain"]:
		assert_true(s.council.has(seat), seat + " seated")

func test_trait_modifiers_applied() -> void:
	var s := GameState.new_campaign(data, 42)
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
	var s := GameState.new_campaign(data, 42)
	var c: Character = s.characters[s.council["chaplain"]]
	c.change_opinion(-5, "rt", 1)
	var c2 := Character.from_dict(c.to_dict())
	assert_eq(c2.display_name, "Father Odo")
	assert_eq(c2.opinion, c.opinion)
	assert_eq(c2.opinion_log[0]["reason"], "rt")
	assert_eq(c2.ideology["orthodoxy"], c.ideology["orthodoxy"])
