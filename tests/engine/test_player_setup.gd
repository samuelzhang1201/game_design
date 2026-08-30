extends GutTest
## Character creation (main menu): the chosen name/family/flag applies to the
## player and the family name is inherited by every role of the royal house.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func test_setup_renames_player_and_royal_house() -> void:
	state.apply_player_setup({"first_name": "Edmund", "family_name": "Blackwood",
		"flag": "moon"})
	var you: Character = state.characters["you"]
	assert_eq(you.display_name, "King Edmund Blackwood")
	assert_eq(you.family_name, "Blackwood")
	# House Valorin roles inherit the new family name, in name and house.
	var tomas: Character = state.characters["char_duke_tomas"]
	assert_eq(tomas.family_name, "Blackwood")
	assert_eq(tomas.display_name, "Duke Tomas Blackwood")
	assert_eq(state.characters["char_lady_ysolde"].family_name, "Blackwood")
	# Nora keeps her late mother's O-kala name; the queen keeps Weighhouse.
	assert_eq(state.characters["char_princess"].family_name, "O-kala")
	assert_eq(state.characters["char_queen"].family_name, "Weighhouse")

func test_setup_survives_save_round_trip() -> void:
	state.apply_player_setup({"first_name": "Edmund", "family_name": "Blackwood",
		"flag": "moon"})
	var restored := GameState.from_dict(state.to_dict())
	assert_eq(String(restored.player_setup["flag"]), "moon")
	assert_eq(restored.characters["you"].display_name, "King Edmund Blackwood")
	assert_eq(restored.characters["char_duke_tomas"].family_name, "Blackwood")

func test_empty_setup_changes_nothing() -> void:
	var before: String = state.characters["you"].display_name
	state.apply_player_setup({})
	assert_eq(state.characters["you"].display_name, before)

func test_partial_setup_fills_missing_half_from_founding_name() -> void:
	state.apply_player_setup({"family_name": "Blackwood"})
	assert_eq(state.characters["you"].display_name, "King Aldric Blackwood")
