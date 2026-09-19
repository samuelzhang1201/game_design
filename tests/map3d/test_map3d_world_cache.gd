extends GutTest
## The world cache (spec 2026-09-20 §3): a screen switch frees the view but
## not its 44 MB world; the next view re-parents it. At most one world, lent
## to one view at a time (Ruling 13).

const FIXTURE := "user://test_map3d_cache_world.tscn"
const OTHER := "user://test_map3d_cache_other.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	for path: String in [FIXTURE, OTHER]:
		var root := Node3D.new()
		root.set_meta("map3d_world", WORLD)
		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, path)
		root.free()


func after_each() -> void:
	Map3DWorldCache.clear()


func _view(path: String = FIXTURE) -> Map3DView:
	var v := Map3DView.create(Game.data, path)
	v.size = Vector2(800, 450)
	add_child(v)
	v.activate()
	return v


func _world_of(v: Map3DView) -> Node:
	return v.viewport().get_node("WorldSlot").get_child(0)


func test_a_new_view_reuses_the_last_views_world() -> void:
	var v1 := _view()
	var w1 := _world_of(v1)
	v1.free()
	assert_eq(Map3DWorldCache.held(), FIXTURE)
	assert_false(Map3DWorldCache.lent())
	assert_true(is_instance_valid(w1), "kept, not freed")
	var v2 := _view()
	assert_true(is_same(_world_of(v2), w1), "re-parented, not reloaded")
	assert_true(Map3DWorldCache.lent())
	v2.free()


func test_a_second_live_view_gets_its_own_world() -> void:
	var v1 := _view()
	var v2 := _view()
	assert_false(is_same(_world_of(v1), _world_of(v2)), "never one world in two views")
	var w2 := _world_of(v2)
	v2.free()
	assert_false(is_instance_valid(w2), "the spare copy is dropped")
	assert_true(Map3DWorldCache.lent(), "v1 still holds the cached one")
	v1.free()


func test_another_pack_drops_the_old_world() -> void:
	var v1 := _view()
	var w1 := _world_of(v1)
	v1.free()
	var v2 := _view(OTHER)
	assert_false(is_instance_valid(w1), "one world at most")
	assert_eq(Map3DWorldCache.held(), OTHER)
	v2.free()


## GameRoot's swap queue_frees the old screen and builds the new one in the
## same frame: the old view hands its world over first (release_world), or
## the new view would find it still lent and reload.
func test_a_released_view_hands_its_world_to_the_next_in_the_same_frame() -> void:
	var v1 := _view()
	var w1 := _world_of(v1)
	v1.release_world()
	assert_false(v1.is_loaded(), "the old view no longer draws the world")
	var v2 := _view()
	assert_true(is_same(_world_of(v2), w1), "handed over, not reloaded")
	v1.free()
	assert_true(is_instance_valid(w1), "the dying view gives nothing back")
	assert_true(is_same(_world_of(v2), w1))
	assert_true(Map3DWorldCache.lent())
	v2.free()
