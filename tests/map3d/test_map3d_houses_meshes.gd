extends GutTest
## Every house type names a mesh that exists and loads, at the size its row
## claims (spec 2026-09-20 §2). The same shape as the existing
## "every named texture exists" tests.

const MANIFEST := "res://assets/map3d_houses/houses.json"


func before_all() -> void:
	Game.start_campaign(42)


func test_every_type_has_a_mesh_on_disk() -> void:
	for type: String in Game.data.map3d_houses:
		var path := String(Game.data.map3d_houses[type]["mesh"])
		assert_true(ResourceLoader.exists(path), type + " has a mesh at " + path)


func test_every_mesh_loads_and_carries_geometry() -> void:
	for type: String in Game.data.map3d_houses:
		var path := String(Game.data.map3d_houses[type]["mesh"])
		var scene := load(path) as PackedScene
		assert_not_null(scene, type + " loads as a PackedScene")
		if scene == null:
			continue
		var node := scene.instantiate()
		var mesh := _first_mesh(node)
		assert_not_null(mesh, type + " holds a mesh")
		if mesh != null:
			assert_gt(mesh.get_surface_count(), 0, type + " has a surface")
		node.free()


func test_every_mesh_stands_on_its_origin_at_the_claimed_size() -> void:
	for type: String in Game.data.map3d_houses:
		var row: Dictionary = Game.data.map3d_houses[type]
		var scene := load(String(row["mesh"])) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate()
		var mesh := _first_mesh(node)
		if mesh != null:
			var aabb := mesh.get_aabb()
			assert_almost_eq(aabb.position.y, 0.0, 0.05,
				type + " stands ON its origin — no base plate, nothing sunk into the mesh")
			assert_almost_eq(aabb.size.y, float(row["height_m"]), 0.6,
				type + " is as tall as its row claims")
			assert_lt(maxf(aabb.size.x, aabb.size.z), float(row["footprint_m"]) + 0.6,
				type + " fits the footprint its row claims")
			assert_gt(maxf(aabb.size.x, aabb.size.z), float(row["footprint_m"]) - 0.6,
				type + " actually FILLS the footprint its row claims, not just narrower than it " +
				"(2026-09-21: join_and_normalise used to scale x/y and z independently by " +
				"min(fp/span, ht/tall) tied together, so the taller ratio always won and left " +
				"every mesh 12-25% narrower than its declared footprint — an upper-only bound " +
				"never caught that)")
		node.free()


func test_the_manifest_covers_every_type() -> void:
	assert_true(FileAccess.file_exists(MANIFEST), "houses.json exists")
	var raw := FileAccess.get_file_as_string(MANIFEST)
	var man: Dictionary = JSON.parse_string(raw)
	assert_not_null(man, "houses.json parses")
	for type: String in Game.data.map3d_houses:
		assert_true(man.has(type), "houses.json knows " + type)


func test_the_manifests_tris_is_the_meshs_real_triangle_count() -> void:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	var man: Dictionary = JSON.parse_string(raw)
	for type: String in Game.data.map3d_houses:
		if not man.has(type):
			continue
		var path := String(Game.data.map3d_houses[type]["mesh"])
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate()
		var mesh := _first_mesh(node)
		if mesh != null:
			var claimed: int = int(man[type]["tris"])
			assert_eq(_mesh_tris(mesh), claimed,
				type + "'s houses.json tris must equal the mesh's real triangle count, not its face count")
		node.free()


func test_every_mesh_is_watertight_and_consistently_wound() -> void:
	## Catches the class of defect a bounding-box check cannot: a face left
	## unclosed (an edge used by only one triangle) or a face wound the
	## wrong way relative to its neighbour (an edge two triangles both walk
	## in the SAME direction, instead of the one-forward-one-back a closed,
	## consistently outward-facing solid always has). 2026-09-21: three
	## rendered tiles (cottage_a, longhouse, townhouse_b) showed a dark
	## gash/hole the owner suspected was exactly this; this test came back
	## clean on all three (see the report for what the real cause was and
	## why this check is still worth keeping as a permanent regression net).
	for type: String in Game.data.map3d_houses:
		var row: Dictionary = Game.data.map3d_houses[type]
		var scene := load(String(row["mesh"])) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate()
		var mesh := _first_mesh(node)
		if mesh != null:
			var result := _manifold_check(mesh)
			assert_eq(int(result["open_boundary_edges"]), 0,
				type + " has an open/uncapped face — an edge used by only one triangle")
			assert_eq(int(result["winding_conflicts"]), 0,
				type + " has two triangles sharing an edge with the SAME winding — one of them is flipped")
		node.free()


func _manifold_check(mesh: Mesh) -> Dictionary:
	# A directed-edge census over quantized vertex POSITIONS, not indices:
	# glTF re-export duplicates vertices per face, so position is the only
	# stable identity left. A properly closed, consistently outward-wound
	# solid has every edge walked exactly once forward and once backward
	# by its two triangles; an edge walked only once is a hole, and an
	# edge walked twice in the SAME direction is a local winding conflict.
	var edge_dir := {}
	var edge_any := {}
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var n := indices.size() / 3 if indices.size() > 0 else verts.size() / 3
		for tri in range(n):
			var tri_verts: Array[Vector3] = []
			for k in range(3):
				var idx := tri * 3 + k
				var vi := indices[idx] if indices.size() > 0 else idx
				tri_verts.append(verts[vi])
			for k in range(3):
				var a: Vector3 = tri_verts[k]
				var b: Vector3 = tri_verts[(k + 1) % 3]
				var ka := "%.3f,%.3f,%.3f" % [a.x, a.y, a.z]
				var kb := "%.3f,%.3f,%.3f" % [b.x, b.y, b.z]
				var dkey: String = ka + ">" + kb
				edge_dir[dkey] = int(edge_dir.get(dkey, 0)) + 1
				var ukey: String = (ka + "<>" + kb) if ka < kb else (kb + "<>" + ka)
				edge_any[ukey] = int(edge_any.get(ukey, 0)) + 1
	var open_boundary := 0
	var winding_conflicts := 0
	for ukey: String in edge_any:
		var count: int = edge_any[ukey]
		if count == 1:
			open_boundary += 1
		elif count == 2:
			var parts := ukey.split("<>")
			var fwd: String = parts[0] + ">" + parts[1]
			var bwd: String = parts[1] + ">" + parts[0]
			if int(edge_dir.get(fwd, 0)) != 1 or int(edge_dir.get(bwd, 0)) != 1:
				winding_conflicts += 1
	return {"open_boundary_edges": open_boundary, "winding_conflicts": winding_conflicts}


func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _mesh_tris(mesh: Mesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(s)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() > 0:
			total += indices.size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += verts.size() / 3
	return total
