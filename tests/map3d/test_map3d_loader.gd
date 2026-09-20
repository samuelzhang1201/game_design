extends GutTest
## Swapping map data (spec 2026-09-20 §3): the build holds data plus a
## manifest; the game says honestly why there is no 3D map — missing, stale
## (rebuild), bad — and a pack can keep its 3D build anywhere (maps.csv
## map3d_dir).

const DIR := "user://loader_fixture"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_each() -> void:
	Game.start_campaign(42)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var root := Node3D.new()
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, DIR + "/world.tscn")
	root.free()


func after_each() -> void:
	for f: String in ["world.tscn", "manifest.json"]:
		if FileAccess.file_exists(DIR + "/" + f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	Map3DWorldLoader.clear_warnings()


func _manifest(text: String) -> void:
	var f := FileAccess.open(DIR + "/manifest.json", FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_no_scene_is_missing() -> void:
	assert_eq(Map3DWorldLoader.status("user://nowhere/world.tscn")["state"], "missing")


func test_no_manifest_is_a_legacy_build_that_loads() -> void:
	assert_eq(Map3DWorldLoader.status(DIR + "/world.tscn")["state"], "legacy")
	var w := Map3DWorldLoader.instance(DIR + "/world.tscn")
	assert_not_null(w)
	if w != null:
		w.free()


func test_a_current_manifest_is_ok() -> void:
	_manifest(JSON.stringify({"format_version": Map3DWorldLoader.FORMAT_VERSION, "meta": WORLD,
		"steps_hash": Map3DWorldLoader.steps_hash()}))
	assert_eq(Map3DWorldLoader.status(DIR + "/world.tscn")["state"], "ok")


func test_an_older_pipeline_is_stale() -> void:
	_manifest(JSON.stringify({"format_version": 1, "meta": WORLD}))
	var st := Map3DWorldLoader.status(DIR + "/world.tscn")
	assert_eq(st["state"], "stale")
	assert_string_contains(String(st["why"]), "1")


func test_a_manifest_that_disagrees_with_the_scene_is_stale() -> void:
	var other := WORLD.duplicate()
	other["m_per_px"] = 40.0
	_manifest(JSON.stringify({"format_version": Map3DWorldLoader.FORMAT_VERSION, "meta": other}))
	assert_eq(Map3DWorldLoader.status(DIR + "/world.tscn")["state"], "stale")


func test_a_broken_manifest_is_bad() -> void:
	_manifest("{ not json")
	assert_eq(Map3DWorldLoader.status(DIR + "/world.tscn")["state"], "bad")


func test_json_numbers_still_match_the_meta() -> void:
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(WORLD))
	assert_true(Map3DWorldLoader.same_meta(WORLD, round_trip), "2560 and 2560.0 are one size")


func test_each_notice_says_what_to_run() -> void:
	for state: String in ["missing", "stale", "bad"]:
		var text := Map3DWorldLoader.notice_text(state, "some_pack")
		assert_string_contains(text, "tools/map3d")
		assert_string_contains(text, "build_pack.sh --map some_pack")


func test_a_stale_build_shows_its_notice_and_does_not_load() -> void:
	_manifest(JSON.stringify({"format_version": 1, "meta": WORLD}))
	var v := Map3DView.create(Game.data, DIR + "/world.tscn")
	add_child_autofree(v)
	v.activate()
	assert_false(v.is_loaded())
	assert_true(v.notice().visible)
	assert_string_contains(v.notice().text, "older")


func test_a_pack_can_keep_its_3d_build_elsewhere() -> void:
	var id := Game.data.map_id
	var row: Dictionary = Game.data.maps[id]
	var before := String(row.get("map3d_dir", ""))
	row["map3d_dir"] = "res://elsewhere/" + id
	assert_eq(Map3DView.scene_path_for(id), "res://elsewhere/%s/world.tscn" % id)
	row["map3d_dir"] = before
	assert_eq(Map3DView.scene_path_for(id), "res://assets/map3d/%s/world.tscn" % id)


func test_the_house_table_is_in_the_steps_hash() -> void:
	# a changed house table must report the build stale, not draw the old one
	var before := Map3DWorldLoader.steps_hash()
	var path := "res://data/map3d_houses.csv"
	var original := FileAccess.get_file_as_string(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(original + "\n# probe\n")
	f.close()
	var after := Map3DWorldLoader.steps_hash()
	var g := FileAccess.open(path, FileAccess.WRITE)
	g.store_string(original)
	g.close()
	assert_ne(before, after, "map3d_houses.csv is part of the build's steps hash")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
