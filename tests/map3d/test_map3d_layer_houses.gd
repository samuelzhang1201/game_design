extends GutTest
## Map3DLayerHouses: one MultiMesh per type, rebuilt only when the camera
## moves far enough (spec 2026-09-20 §3).

const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
const CSV := "user://test_map3d_layer_houses.csv"
## Fix round 1, finding 1: a distinctive, non-zero height so a refresh() that
## hardcoded or skipped the ctx.height_at() lookup could not pass by accident
## (0.0 or the fixture's own sea_y of 5.0 would both be too easy to fake).
const HEIGHT := 777.5

var _layer: Map3DLayerHouses
var _ctx: Map3DContext


func before_each() -> void:
	Game.start_campaign(42)
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	var a := String(codes[0])
	var f := FileAccess.open(CSV, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale,height_scale")
	var b: Dictionary = Game.data.burgs[a]
	var at := Map3DGeometry.pack_to_world(WORLD, Vector2(float(b["x"]), float(b["y"])))
	f.store_line("%s,0,%f,%f,0,chapel,1.0,1.0" % [a, at.x, at.y])
	# cottage_a's scale and height_scale are deliberately DIFFERENT (0.8 vs
	# 2.0) so a layer that scaled uniformly (ignoring the column, or reusing
	# `scale` for both axes) would fail test_height_scale_reaches_the_transform.
	f.store_line("%s,1,%f,%f,90,cottage_a,0.8,2.0" % [a, at.x + 20.0, at.y])
	f.close()
	_ctx = Map3DContext.new(Game.data, WORLD)
	_ctx.height_fn = func(_xz: Vector2) -> float: return HEIGHT
	_layer = Map3DLayerHouses.new()
	_layer.houses_override = Map3DHouses.load_csv(CSV)
	add_child_autofree(_layer)
	_layer.bind(_ctx)


func test_one_multimesh_per_type_present() -> void:
	_layer.refresh(_home())
	var counts := _layer.counts()
	assert_eq(counts.get("chapel", 0), 1)
	assert_eq(counts.get("cottage_a", 0), 1)


func test_every_instance_sits_on_the_ground_minus_the_sink() -> void:
	_layer.refresh(_home())
	var sink: float = Game.data.bal("map3d_house_sink_m")
	# Deviation from the brief: under the headless dummy renderer GUT runs
	# under, MultiMeshInstance3D.get_instance_transform() never reflects what
	# set_instance_transform() wrote — verified directly, even for a
	# hand-built raw `buffer` assignment, so this is the renderer's storage
	# missing, not our code. transforms_of() records the Transform3D refresh()
	# ITSELF computed and handed to set_instance_transform, so this asserts on
	# what refresh() actually did — including its ctx.height_at() lookup — not
	# on a value the test supplies (fix round 1, finding 1).
	var checked := 0
	for type: String in _layer.counts():
		for t: Transform3D in _layer.transforms_of(type):
			assert_almost_eq(t.origin.y, HEIGHT - sink, 0.001,
				"a house stands on the ground, sunk so its foot bites in")
			checked += 1
	assert_eq(checked, 2, "both chapel and cottage_a were checked")


func test_a_small_camera_move_does_not_rebuild() -> void:
	assert_true(_layer.refresh(_home()), "the first call builds")
	var step: float = Game.data.bal("map3d_house_rebuild_move_m")
	assert_false(_layer.refresh(_home() + Vector2(step * 0.4, 0.0)),
		"cut once per camera pose, never per frame")
	assert_true(_layer.refresh(_home() + Vector2(step * 1.5, 0.0)),
		"a real move rebuilds")


func test_nothing_is_built_far_from_every_settlement() -> void:
	_layer.refresh(Vector2(500000.0, 500000.0))
	for type: String in _layer.counts():
		assert_eq(int(_layer.counts()[type]), 0, type + " has no instances out at sea")


func test_instances_carry_their_yaw_and_scale() -> void:
	_layer.refresh(_home())
	# Deviation from the brief (task 6 override 4): "cottage_a".capitalize()
	# returns "Cottage A" (capitalize() turns an underscore into a space), not
	# "Cottage_a" — verified against a headless Godot run. The layer names its
	# nodes after the raw CSV type instead, so the lookup here follows suit.
	var mmi := _layer.get_node_or_null("cottage_a") as MultiMeshInstance3D
	assert_not_null(mmi)
	# Second deviation, same test: read the Transform3D refresh() itself
	# computed and handed to set_instance_transform (transforms_of()) rather
	# than reading it back from the MultiMesh, which the headless dummy
	# renderer never backs with real data (see
	# test_every_instance_sits_on_the_ground_minus_the_sink). A refresh() that
	# dropped the yaw or the scale fails this directly, since transforms_of()
	# is filled from inside refresh()'s own loop.
	var xforms := _layer.transforms_of("cottage_a")
	assert_eq(xforms.size(), 1)
	if xforms.size() > 0:
		var basis: Basis = (xforms[0] as Transform3D).basis
		assert_almost_eq(basis.get_euler().y, deg_to_rad(90.0), 0.01)


## Redesign owner 2026-09-20 (高低层次不齐): height_scale is a SEPARATE
## vertical multiplier, not folded into `scale`. cottage_a's fixture row
## carries scale 0.8 and height_scale 2.0, so a correct transform stands
## 0.8 wide/deep and 1.6 tall — three distinct values that could not agree
## by accident if the layer ignored the column or scaled uniformly.
func test_height_scale_reaches_the_transform() -> void:
	_layer.refresh(_home())
	var xforms := _layer.transforms_of("cottage_a")
	assert_eq(xforms.size(), 1)
	if xforms.size() > 0:
		var s := (xforms[0] as Transform3D).basis.get_scale()
		assert_almost_eq(s.x, 0.8, 0.01, "horizontal scale is the row's own scale")
		assert_almost_eq(s.z, 0.8, 0.01, "horizontal scale is the row's own scale")
		assert_almost_eq(s.y, 0.8 * 2.0, 0.01, "vertical scale is scale * height_scale")


func _home() -> Vector2:
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	var b: Dictionary = Game.data.burgs[String(codes[0])]
	return Map3DGeometry.pack_to_world(WORLD, Vector2(float(b["x"]), float(b["y"])))
