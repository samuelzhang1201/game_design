extends GutTest
## HEIGHTS on the 3D map (owner 2026-09-19, spec 2026-09-19-map3d-heights).

const FIXTURE := "user://test_map3d_heights_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}

func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()

func before_each() -> void:
	Game.start_campaign(42)

func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v

func test_heights_is_a_theme_of_its_own() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	assert_eq(v.manor_theme(), "heights")
	assert_true(v.heat_on())
	assert_null(v.cell_lut(), "no manor colours under HEIGHTS")
	v.set_manor_theme("manors")
	assert_false(v.heat_on())
	v.set_manor_theme("")
	assert_false(v.heat_on())

func test_under_heights_land_still_means_its_province() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var picked := v.pick_at(v.size * 0.5)
	assert_ne(String(picked.get("kind", "")), "manor", "manors are picked only under MANORS")
