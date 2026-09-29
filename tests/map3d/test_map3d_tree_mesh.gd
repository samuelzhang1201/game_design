extends GutTest
## Map3DTreeMesh: the woods' clumps (look route 2026-09-30), built from
## numbers alone — the same (kind, variant) is always the same mesh.


func _verts(m: ArrayMesh) -> PackedVector3Array:
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_every_kind_builds_at_both_levels() -> void:
	for kind in [Map3DTreeMesh.BROADLEAF, Map3DTreeMesh.CONIFER, Map3DTreeMesh.LONE]:
		for lod in 2:
			assert_gt(_verts(Map3DTreeMesh.clump(kind, lod, 0)).size(), 0, "kind %d lod %d" % [kind, lod])


func test_a_clump_is_the_same_every_time() -> void:
	var a := _verts(Map3DTreeMesh.clump(Map3DTreeMesh.BROADLEAF, 0, 1))
	var b := _verts(Map3DTreeMesh.clump(Map3DTreeMesh.BROADLEAF, 0, 1))
	assert_eq(a, b)
	assert_ne(a, _verts(Map3DTreeMesh.clump(Map3DTreeMesh.BROADLEAF, 0, 0)), "variants differ")


func test_the_far_clump_is_much_cheaper() -> void:
	for kind in [Map3DTreeMesh.BROADLEAF, Map3DTreeMesh.CONIFER]:
		var near := _verts(Map3DTreeMesh.clump(kind, 0, 0)).size()
		var far := _verts(Map3DTreeMesh.clump(kind, 1, 0)).size()
		assert_lt(far * 3, near, "kind %d: %d far vs %d near" % [kind, far, near])


func test_a_crown_is_lit_on_top_and_dark_beneath() -> void:
	var arrays := Map3DTreeMesh.clump(Map3DTreeMesh.BROADLEAF, 0, 0).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var hi := 0
	var lo := 0
	for i in verts.size():
		if verts[i].y > verts[hi].y:
			hi = i
		if cols[i] != Map3DTreeMesh.TRUNK and verts[i].y < verts[lo].y:
			lo = i
	assert_gt(cols[hi].get_luminance(), cols[lo].get_luminance())
