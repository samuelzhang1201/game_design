extends GutTest
## Regions/locations (data/regions.csv, data/locations.csv): free movement
## within a region, occupant resolution, save persistence.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func test_data_loads_and_every_occupant_exists_in_roster() -> void:
	assert_true(data.regions.has("crown_district"))
	assert_gte(data.locations.size(), 10)
	for code in data.locations:
		var row: Dictionary = data.locations[code]
		assert_true(data.regions.has(String(row["region_code"])),
			String(code) + " belongs to a real region")
		for id in String(row["occupants"]).split("|", false):
			assert_true(state.characters.has(id),
				"%s occupant %s exists in the roster" % [code, id])

func test_campaign_starts_at_council_chamber() -> void:
	assert_eq(state.current_location, "council_chamber")
	var here := LocationSystem.occupants(data, state, state.current_location)
	assert_eq(here.size(), 5, "the five ministers hold the chamber")

func test_move_within_region_is_free_no_tick() -> void:
	var tick_before := state.tick
	assert_true(LocationSystem.can_move(data, state, "mustering_field"))
	state.current_location = "mustering_field"
	assert_eq(state.tick, tick_before, "movement costs no time")
	assert_has(LocationSystem.occupants(data, state, "mustering_field"),
		"char_princess", "Nora drills on the field")

func test_unknown_location_rejected() -> void:
	assert_false(LocationSystem.can_move(data, state, "the_moon"))

func test_reachable_lists_whole_region() -> void:
	assert_eq(LocationSystem.reachable(data, state).size(), data.locations.size(),
		"one region for now: everywhere is reachable")

func test_location_survives_save_round_trip() -> void:
	state.current_location = "high_street"
	var restored := GameState.from_dict(state.to_dict())
	assert_eq(restored.current_location, "high_street")

func test_pre_location_save_defaults_to_council_chamber() -> void:
	var d := state.to_dict()
	d.erase("current_location")
	assert_eq(GameState.from_dict(d).current_location, "council_chamber")
