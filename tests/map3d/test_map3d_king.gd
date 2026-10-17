extends GutTest

const KING_SCRIPT := "res://scripts/map3d/map3d_king.gd"

func _script() -> GDScript:
	assert_true(ResourceLoader.exists(KING_SCRIPT), "independent king layer is installed")
	return load(KING_SCRIPT) as GDScript if ResourceLoader.exists(KING_SCRIPT) else null

func test_king_walks_route_corners_instead_of_cutting_across() -> void:
	var script := _script()
	if script == null:
		return
	var path: Array = [Vector2i(1000, 0), Vector2i(1000, 1000)]
	assert_eq(script.along(Vector2i.ZERO, path, 0.25), Vector2(500, 0))
	assert_eq(script.along(Vector2i.ZERO, path, 0.75), Vector2(1000, 500))
	assert_eq(script.along(Vector2i.ZERO, path, 1.0), Vector2(1000, 1000))

func test_snapshot_is_copied_and_never_writes_live_king() -> void:
	var script := _script()
	if script == null:
		return
	var layer: Node3D = script.new()
	add_child_autofree(layer)
	var king := {"x_m": 1000, "y_m": 2000, "travel_state": "stationary"}
	layer.apply_snapshot({"king": king, "king_path": [Vector2i(3000, 2000)]})
	king["x_m"] = 9999
	assert_eq(layer.position_m(0.5), Vector2(2000, 2000), "snapshot owns its data")
	assert_eq(king["x_m"], 9999, "renderer never mutates source")

func test_stationary_king_stands_independently_of_royal_regiment() -> void:
	var script := _script()
	if script == null:
		return
	var layer: Node3D = script.new()
	add_child_autofree(layer)
	layer.apply_snapshot({"king": {"x_m": 1000, "y_m": 2000}, "king_path": []})
	assert_eq(layer.position_m(1.0), Vector2(1000, 2000))
	assert_eq(layer.action_for(false), "STANDBY")
	layer.observe()
	assert_eq(layer.action_for(false), "OBSERVE")
	assert_eq(layer.action_for(true), "MARCH", "moving cannot play an in-place gesture")

func test_selecting_king_clears_army_selection_and_leaves_armies_independent() -> void:
	var repo := preload("res://tests/suite_data.gd").repo()
	var view := Map3DView.new()
	autofree(view)
	var selection := Map3DSelection.new()
	selection.bind(Map3DContext.new(repo, {}), null, null, view)
	selection.army = "regiment"
	selection.armies = ["regiment"]
	selection.select({"kind": "king"})
	assert_true(selection.king)
	assert_eq(selection.army, "")
	assert_true(selection.armies.is_empty(), "king is never a selected regiment")
	selection.clear()
	assert_false(selection.king)

func test_runtime_king_scene_has_all_actions_without_capture_or_death() -> void:
	var path := "res://scenes/models/characters/king.tscn"
	assert_true(ResourceLoader.exists(path), "dedicated runtime king scene")
	if not ResourceLoader.exists(path): return
	var model := (load(path) as PackedScene).instantiate() as Node3D
	autofree(model)
	var anim := Map3DUnits.find_anim(model)
	assert_not_null(anim)
	if anim == null: return
	for clip: String in ["MARCH", "STANDBY", "OBSERVE", "COMMAND", "INSPIRE"]:
		assert_ne(Map3DUnits.clip_named(anim, clip), "", clip)
	for clip: String in ["MARCH", "STANDBY", "OBSERVE"]:
		assert_eq(anim.get_animation(Map3DUnits.clip_named(anim, clip)).loop_mode, Animation.LOOP_LINEAR, clip + " loops in Godot")
	for clip: String in anim.get_animation_list():
		assert_false("CAPTURE" in clip.to_upper() or "DEATH" in clip.to_upper(), clip)

func test_midday_destination_change_preserves_the_drawn_position() -> void:
	var layer := Map3DKing.new()
	add_child_autofree(layer)
	var repo := preload("res://tests/suite_data.gd").repo()
	var ctx := Map3DContext.new(repo, {})
	var share := [0.0]
	ctx.day_fn = func() -> float: return share[0]
	layer.bind(ctx)
	layer.apply_snapshot({"absolute_day": 1, "king": {"x_m": 0, "y_m": 0, "route": [[1000, 0]]}, "king_path": [Vector2i(1000, 0)]})
	share[0] = 0.5
	assert_eq(layer.position_m(share[0]), Vector2(500, 0))
	layer.apply_snapshot({"absolute_day": 1, "king": {"x_m": 0, "y_m": 0, "route": [[0, 1000]]}, "king_path": [Vector2i(0, 1000)]})
	assert_eq(layer.position_m(share[0]), Vector2(500, 0), "re-aim begins at the last drawn position")
	assert_eq(layer.position_m(1.0), Vector2(0, 1000))

func test_committed_position_change_uses_the_new_physical_position() -> void:
	var layer := Map3DKing.new()
	add_child_autofree(layer)
	var repo := preload("res://tests/suite_data.gd").repo()
	var ctx := Map3DContext.new(repo, {})
	layer.bind(ctx)
	layer.apply_snapshot({"absolute_day": 1, "king": {"x_m": 1000, "y_m": 2000}, "king_path": []})
	layer.apply_snapshot({"absolute_day": 1, "king": {"x_m": 4000, "y_m": 2000}, "king_path": []})
	assert_eq(layer.position_m(0.0), Vector2(4000, 2000), "committed movement or a loaded state is not a route re-aim")
