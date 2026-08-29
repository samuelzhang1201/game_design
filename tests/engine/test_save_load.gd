extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_save_load_round_trip_hash_equal() -> void:
	var engine := TickEngine.new(data)
	var s := GameState.new_campaign(data, 42)
	for i in 5:
		engine.advance(s)
	engine.actions.execute(ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}), s)
	var path := "user://test_save.json"
	assert_true(SaveLoad.save_game(s, path))
	var loaded := SaveLoad.load_game(path)
	assert_not_null(loaded)
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(s))

## Saves are versioned (GameState.SAVE_VERSION): the current version round
## trips, a save from a NEWER build is refused (null) rather than half-loaded,
## and a pre-versioning save (no field) still loads as version 1.
func test_save_version_written_and_newer_save_refused() -> void:
	var s := GameState.new_campaign(data, 42)
	var d := s.to_dict()
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	var unversioned := d.duplicate(true)
	unversioned.erase("version")
	assert_not_null(GameState.from_dict(unversioned),
		"a pre-versioning save must still load")
	var newer := d.duplicate(true)
	newer["version"] = GameState.SAVE_VERSION + 1
	assert_null(GameState.from_dict(newer),
		"a save from a newer build must be refused, not half-loaded")

## Regression: a save taken mid-turn, with a pending action_request in
## recent_outcomes (params carry an engine-created int, e.g. {"delta": 2}),
## must hash identically after a load. Before the to_dict() normalization
## fix, JSON's int->float round-trip made the loaded state's canonical JSON
## diverge from the in-memory state's, so this failed.
func test_save_load_hash_equal_with_pending_outcome() -> void:
	var engine := TickEngine.new(data)
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 2}), s)
	var path := "user://test_save_pending.json"
	assert_true(SaveLoad.save_game(s, path))
	var loaded := SaveLoad.load_game(path)
	assert_not_null(loaded)
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(s))
