extends GutTest
const Command := preload("res://scripts/engine/battle_command.gd")

func _state() -> GameState:
	var state := GameState.new()
	for row: Array in [["A", 16, 40], ["B", 15, 90], ["C", 16, 40]]:
		var character := Character.new()
		character.id = row[0]
		character.skills["sk_martial"] = row[1]
		character.attributes["prestige"] = row[2]
		state.characters[character.id] = character
	return state

func test_selection_uses_martial_then_prestige_then_stable_id() -> void:
	var state := _state()
	var ids: Array[String] = ["C", "B", "A"]
	assert_eq(Command.select(state, ids, ""), "A")
	assert_eq(ids, ["C", "B", "A"], "selection must not reorder caller eligibility")
	assert_eq(Command.select(state, ["A", "C", "B"], ""), "A")
	state.characters["C"].attributes["prestige"] = 41
	assert_eq(Command.select(state, ids, ""), "C")

func test_valid_nominee_overrides_automatic_ranking() -> void:
	assert_eq(Command.select(_state(), ["A", "B", "C"], "B"), "B")

func test_invalid_nominee_is_not_silently_replaced() -> void:
	assert_eq(Command.select(_state(), ["A", "B", "C"], "unknown"), "")
	assert_eq(Command.select(_state(), ["A", "C"], "B"), "")
	assert_eq(Command.select(_state(), ["unknown", "A"], "unknown"), "")

func test_missing_characters_cannot_be_selected() -> void:
	assert_eq(Command.select(_state(), ["unknown", "A"], ""), "A")
	assert_eq(Command.select(_state(), ["unknown"], ""), "")
	assert_eq(Command.select(_state(), [], ""), "")
