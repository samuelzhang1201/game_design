extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
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

func test_a_photo_card_clump_is_two_triangles_a_crown_from_its_own_cells() -> void:
	# owner 2026-10-01: the woods as photo cards (tree_card.gdshader)
	var cells := PackedInt32Array([3, 7])
	var m := Map3DTreeMesh.cards(Map3DTreeMesh.BROADLEAF, 0, cells)
	var arrays := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 8 * 6, "eight crowns, two triangles each")
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	for i in verts.size():
		var cell := int(round(custom[i * 4 + 3]))
		assert_true(cells.has(cell), "every card wears a cell of its own kind")
		assert_gt(custom[i * 4 + 2], 4.0, "a card is a whole tree, metres across")
	# every vertex sits at a crown's centre: the box must still hold the cards
	# the vertex box only spans the centres: culling reads the custom box
	assert_gt(m.custom_aabb.size.x, m.get_aabb().size.x + 8.0,
		"the clump's culling box holds its cards, not just their centres")


func test_a_species_clump_wears_its_own_row() -> void:
	# owner 2026-10-10 (树木的品种过于单一): data/map3d_tree_species.csv
	var repo := SuiteData.repo()
	var drawn := 0
	for r: Dictionary in repo.map3d_tree_species:
		if int(r["enabled"]) != 1:
			continue
		drawn += 1
		var cells := Array(String(r["cells"]).split("|", false)).map(func(c: String) -> int: return int(c))
		assert_false(cells.is_empty(), "%s: an enabled species wears atlas cells" % r["name"])
		var m := Map3DTreeMesh.species_cards(r, 0)
		var arrays := m.surface_get_arrays(0)
		var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), int(r["crowns"]) * 6, String(r["name"]))
		for i in custom.size() / 4:
			assert_true(cells.has(int(round(custom[i * 4 + 3]))), "%s wears its own cells" % r["name"])
	assert_gt(drawn, 6, "more than a broadleaf, a conifer and a lone tree")


func test_a_species_has_map3d_tree_variants_layouts_that_differ() -> void:
	var repo := SuiteData.repo()
	var row: Dictionary = repo.map3d_tree_species[0]
	var seen := {}
	for v in int(repo.bal("map3d_tree_variants")):
		seen[_verts(Map3DTreeMesh.species_cards(row, v))] = true
	assert_eq(seen.size(), int(repo.bal("map3d_tree_variants")))
	assert_ne(_verts(Map3DTreeMesh.species_cards(repo.map3d_tree_species[1], 0)), _verts(Map3DTreeMesh.species_cards(row, 0)),
		"two species never share a layout")


func test_a_clump_tint_stays_in_its_species_range() -> void:
	var lo := Color("#a0b0c0")
	var hi := Color("#c0d0e0")
	for i in 50:
		var c := Map3DLayerTrees.tint_of([lo, hi], i * 7919)
		assert_between(c.r, lo.r, hi.r)
		assert_between(c.g, lo.g, hi.g)
		assert_between(c.b, lo.b, hi.b)
