extends GutTest
## MarkMesh (owner 2026-09-13, the decor rework): marks become quads in
## native px, standing on their point, in y order, tinted by vertex colour.

func _atlas() -> MarkAtlas:
	var wide := Image.create(20, 10, false, Image.FORMAT_RGBA8)
	var tall := Image.create(10, 20, false, Image.FORMAT_RGBA8)
	return MarkAtlas.build({"wide": wide, "tall": tall}, 2)

func test_marks_become_standing_quads_in_y_order() -> void:
	var atlas := _atlas()
	var mesh := MarkMesh.build([
		{"pos": Vector2(100, 300), "texture": "tall", "height": 40.0, "color": Color.RED},
		{"pos": Vector2(50, 100), "texture": "wide", "height": 10.0, "color": Color.GREEN},
		{"pos": Vector2(0, 0), "texture": "missing", "height": 10.0},
	], atlas, 0.85)
	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(MarkMesh.quad_count(mesh), 2, "the mark with no art is skipped")
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(verts.size(), 8)
	assert_eq(indices.size(), 12)
	# First quad: the wide mark at y 100 (drawn first, it is higher up).
	# Height 10, aspect 2 -> 20 wide; it stands 8.5 above its point.
	assert_eq(verts[0], Vector2(50 - 10, 100 - 8.5), "top-left")
	assert_eq(verts[2], Vector2(50 + 10, 100 + 1.5), "bottom-right")
	assert_eq(colors[0], Color.GREEN)
	assert_eq(uvs[0], (atlas.uv["wide"] as Rect2).position)
	assert_eq(uvs[2], (atlas.uv["wide"] as Rect2).end)
	# Second: the tall mark, 40 high, 20 wide.
	assert_eq(verts[4], Vector2(100 - 10, 300 - 34.0))
	assert_eq(verts[6], Vector2(100 + 10, 300 + 6.0))
	assert_eq(colors[4], Color.RED)
	assert_eq(Array(indices.slice(0, 6)), [0, 1, 2, 0, 2, 3])

func test_no_marks_is_an_empty_mesh() -> void:
	var mesh := MarkMesh.build([], _atlas())
	assert_eq(mesh.get_surface_count(), 0)
	assert_eq(MarkMesh.quad_count(mesh), 0)
	assert_eq(MarkMesh.quad_count(null), 0)

## A mark may mirror (its uv runs right to left) and turn about its point.
func test_marks_mirror_and_turn() -> void:
	var atlas := _atlas()
	var mesh := MarkMesh.build([
		{"pos": Vector2(0, 0), "texture": "wide", "height": 10.0, "flip": true},
		{"pos": Vector2(0, 100), "texture": "wide", "height": 10.0, "angle": PI / 2.0},
	], atlas, 0.85)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var r: Rect2 = atlas.uv["wide"]
	assert_almost_eq(uvs[0].x, r.end.x, 0.0001, "mirrored: the left corner takes the right edge")
	assert_almost_eq(uvs[1].x, r.position.x, 0.0001)
	assert_eq(verts[0], Vector2(-10, -8.5), "unturned")
	# Turned a quarter: the top-left corner (-10, -8.5) about (0, 100) lands at (8.5, 90).
	assert_almost_eq(verts[4].x, 8.5, 0.001)
	assert_almost_eq(verts[4].y, 90.0, 0.001)
