# tests/ledger3d/test_ledger_link_mesh.gd
extends GutTest
## Every link of the galaxy is one quad of ONE mesh, widened on screen by
## link.gdshader (spec 2026-09-30-ledger-galaxy-design §5).

func _seg(a: Vector3, b: Vector3) -> Dictionary:
	return {"id": "x", "a": a, "b": b, "ca": Color(1, 0, 0, 0.5), "cb": Color(0, 0, 1, 0.5),
		"width_px": 3.0, "shift_px": 2.0, "dashed": true, "speed": 0.6, "glow": 2}


func test_a_link_is_one_quad_coloured_end_to_end() -> void:
	var arr := LedgerLinkMesh.arrays([_seg(Vector3.ZERO, Vector3(10, 0, 0)), _seg(Vector3(1, 1, 1), Vector3(2, 2, 2))])
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	assert_eq(v.size(), 8)
	assert_eq(idx.size(), 12)
	assert_eq(v[0], Vector3.ZERO)
	assert_eq(v[2], Vector3(10, 0, 0))
	assert_eq(c[0], Color(1, 0, 0, 0.5), "the source's end in its colour")
	assert_eq(c[3], Color(0, 0, 1, 0.5), "the far end in the other's")


func test_each_vertex_knows_the_other_end_and_its_side() -> void:
	var arr := LedgerLinkMesh.arrays([_seg(Vector3.ZERO, Vector3(10, 0, 0))])
	var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	assert_eq(Vector3(c0[0], c0[1], c0[2]), Vector3(10, 0, 0), "a's vertices point at b")
	assert_eq(Vector3(c0[8], c0[9], c0[10]), Vector3.ZERO, "b's vertices point at a")
	assert_eq([c0[3], c0[7]], [-1.0, 1.0], "a: left, right")
	assert_eq([c0[11], c0[15]], [1.0, -1.0], "b: flipped, so both ends push the same side")


func test_width_shift_speed_dash_and_glow_travel_with_the_vertex() -> void:
	var arr := LedgerLinkMesh.arrays([_seg(Vector3.ZERO, Vector3(10, 0, 0))])
	var c1: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM1]
	assert_eq([c1[0], c1[1], c1[2]], [3.0, 2.0, 2.0], "width, shift, glow at a")
	assert_eq(c1[9], -2.0, "the shift flips with the side at b")
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	assert_eq(uv2[0], Vector2(0.6, 1.0), "speed, dashed")


func test_the_mesh_carries_both_custom_channels() -> void:
	var m := LedgerLinkMesh.mesh([_seg(Vector3.ZERO, Vector3(10, 0, 0))])
	assert_eq(m.get_surface_count(), 1)
	assert_true(m.surface_get_format(0) & (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) != 0)
	assert_true(m.surface_get_format(0) & (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) != 0)


## Owner 2026-10-01 (a bigger wobble): each vertex carries its own end's star
## and the far end's — seed, drawn radius, selected — so link.gdshader moves
## both ends by their stars' own wobble.
func test_each_vertex_carries_both_ends_stars() -> void:
	var seg := _seg(Vector3.ZERO, Vector3(10, 0, 0))
	seg["a_star"] = Color(0.25, 0.5, 1.5, 1.0)
	seg["b_star"] = Color(0.75, 0.125, 0.5, 0.0)
	var arr := LedgerLinkMesh.arrays([seg])
	var c2: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM2]
	var c3: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM3]
	assert_eq(c2.size(), 16)
	assert_eq(Array(c2.slice(0, 4)), [0.25, 0.5, 1.5, 1.0], "a's vertices: a's own star")
	assert_eq(Array(c3.slice(0, 4)), [0.75, 0.125, 0.5, 0.0], "a's vertices: the far star, b")
	assert_eq(Array(c2.slice(8, 12)), [0.75, 0.125, 0.5, 0.0], "b's vertices: b's own star")
	assert_eq(Array(c3.slice(12, 16)), [0.25, 0.5, 1.5, 1.0], "b's vertices: the far star, a")
	var m := LedgerLinkMesh.mesh([seg])
	for ch: int in [Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT]:
		assert_true(m.surface_get_format(0) & (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << ch) != 0)


func test_no_segments_is_an_empty_mesh() -> void:
	assert_eq(LedgerLinkMesh.mesh([]).get_surface_count(), 0)


func test_moving_the_ends_rewrites_only_the_positions() -> void:
	var segs := [_seg(Vector3.ZERO, Vector3(10, 0, 0)), _seg(Vector3(1, 1, 1), Vector3(2, 2, 2))]
	var arr := LedgerLinkMesh.arrays(segs)
	var moved := [[Vector3(5, 0, 0), Vector3(10, 0, 0)], [Vector3(1, 1, 1), Vector3(3, 3, 3)]]
	var want := LedgerLinkMesh.arrays([_seg(moved[0][0], moved[0][1]), _seg(moved[1][0], moved[1][1])])
	LedgerLinkMesh.move_ends(arr, moved)
	for k: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3,
			Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
		assert_eq(arr[k], want[k], "array %d as if built afresh" % k)
