extends GutTest
## Map packs (data/maps.csv + data/maps/<id>/). Authored content names realm
## SLOTS, never the kingdom codes a particular Azgaar export generated, so a
## new map is a data drop rather than a content rewrite.

func _fresh() -> DataRepository:
	var repo := DataRepository.load_all("res://data")
	assert_not_null(repo, "data load failed: " + DataRepository.last_error)
	return repo

func test_default_pack_loads_with_its_world_and_art() -> void:
	var repo := _fresh()
	assert_eq(repo.map_id, repo.default_map_id(), "opens on the default pack")
	assert_false(repo.kingdoms.is_empty(), "pack supplies kingdoms")
	assert_false(repo.provinces.is_empty(), "pack supplies provinces")
	assert_false(repo.burgs.is_empty(), "pack supplies burgs")
	assert_true(ResourceLoader.exists(repo.map_texture_path),
		"map render exists at the path maps.csv gives: " + repo.map_texture_path)
	assert_true(ResourceLoader.exists(repo.index_texture_path),
		"hit-test bitmap exists: " + repo.index_texture_path)

func test_every_binding_points_at_a_kingdom_this_pack_has() -> void:
	var repo := _fresh()
	assert_false(repo.realm_bindings.is_empty(), "pack binds its realm slots")
	for slot: String in repo.realm_bindings:
		var code := String(repo.realm_bindings[slot])
		assert_true(repo.kingdoms.has(code),
			"slot '%s' binds to '%s', which must exist on this map" % [slot, code])

## The point of the whole exercise: authored rows carry a slot, and what the
## engine sees downstream is a concrete kingdom_code from the loaded pack.
func test_authored_realms_resolve_through_the_pack() -> void:
	var repo := _fresh()
	var player := {}
	for r in repo.roles:
		if String(r["id"]) == "you":
			player = r
	assert_false(player.is_empty(), "roles.csv has the player")
	assert_eq(String(player["kingdom_slot"]), "player_realm",
		"the authored value is a slot, not a map's kingdom code")
	assert_eq(String(player["kingdom"]), repo.resolve_realm("player_realm"),
		"what the engine reads is the resolved code")
	assert_true(repo.kingdoms.has(String(player["kingdom"])),
		"and that code is a real kingdom on this map")

## Regression guard. If someone re-introduces a literal kingdom code into an
## authored CSV, swapping maps silently orphans that row — catch it here.
func test_no_authored_csv_names_a_map_kingdom_directly() -> void:
	var repo := _fresh()
	for spec in [["res://data/roles.csv", "kingdom"],
			["res://data/founding_council.csv", "kingdom"],
			["res://data/facts.csv", "subject"]]:
		var rows := DataRepository.parse_csv(String(spec[0]), [String(spec[1])])
		for r in rows:
			var v := String(r[String(spec[1])])
			assert_false(repo.kingdoms.has(v),
				"%s: '%s' is a raw kingdom code from this map — use a realm slot"
					% [String(spec[0]).get_file(), v])

## Re-resolving must read the pristine authored slot, never a code a previous
## map already resolved, or the second map swap would silently keep map one's
## realms.
func test_reloading_a_pack_re_resolves_from_the_authored_slot() -> void:
	var repo := _fresh()
	assert_true(repo.load_map(repo.map_id), "same pack reloads")
	var player := {}
	for r in repo.roles:
		if String(r["id"]) == "you":
			player = r
	assert_eq(String(player["kingdom_slot"]), "player_realm",
		"the slot survives resolution and stays re-resolvable")
	assert_true(repo.kingdoms.has(String(player["kingdom"])),
		"and still resolves to a real kingdom")

func test_unknown_map_fails_loudly() -> void:
	var repo := _fresh()
	var before := repo.map_id
	assert_false(repo.load_map("no_such_map"), "refuses an uninstalled pack")
	assert_ne(DataRepository.last_error, "", "and says why")
	assert_eq(repo.map_id, before, "leaving the loaded pack untouched")

## The save names its world (SAVE_VERSION 2): reloading must restore the same
## map, not whichever one happens to be default.
func test_save_carries_the_map_id() -> void:
	Game.start_campaign(42)
	assert_eq(Game.state.map_id, Game.data.map_id, "a campaign records its map")
	var round_tripped := GameState.from_dict(Game.state.to_dict())
	assert_eq(round_tripped.map_id, Game.state.map_id, "and it survives the save")
