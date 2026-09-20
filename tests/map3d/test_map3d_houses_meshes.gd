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
