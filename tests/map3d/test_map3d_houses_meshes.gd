extends GutTest
## Every house type names a mesh that exists and loads, at the size its row
## claims (spec 2026-09-20 §2). The same shape as the existing
## "every named texture exists" tests.

const MANIFEST := "res://assets/3D/buildings/houses.json"


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


## The smallest a house is ever drawn: the bake's rim scale less its
## jitter, times the lowest height_scale (map3d_bake.csv).
var MIN_DRAWN_SCALE: float:
	get:
		var b: Dictionary = Game.data.map3d_bake
		return b["house_edge_scale_min"] * 0.92 * b["house_height_min"]


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
			# the floor is the origin; below it only the stone footing under the
			# walls (owner 2026-09-25), deep enough for the bake's tallest fall
			# (map3d_bake.csv house_max_drop_m) at the smallest a house is drawn
			var footing := -aabb.position.y
			assert_gt(footing * MIN_DRAWN_SCALE, Game.data.map3d_bake["house_max_drop_m"],
				type + "'s footing reaches the bottom of the steepest plot")
			assert_almost_eq(aabb.end.y, float(row["height_m"]), 0.6,
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


## The largest hole a house mesh may carry, in metres across (owner
## 2026-09-22: 水密性前提要重定, after asking "一般游戏的3d模型不能是空壳吗").
## It cannot: a game mesh is a SHELL, only its visible surface exists, and
## demanding a closed solid was the wrong premise — it failed 13 of the 14
## shipped meshes for cracks nobody can see. What IS a defect is a hole big
## enough to look THROUGH at the size a house is drawn. At the closest zoom
## an 18 m building covers 24-50 px, so roughly 0.4 m to a pixel; 1.0 m is
## about two pixels. Measured over the shipped set
## (tools/map3d/census_house_meshes.py), every mesh's largest hole is
## 0.04-0.45 m — decimation cracks, comfortably under this — so the bar is a
## real guard with room, not a rubber stamp of what exists.
const HOLE_MAX_M := 1.0


func test_no_mesh_has_a_hole_you_could_see_through() -> void:
	## Two defects, one census. A FLIPPED FACE — a triangle that disagrees
	## with two or more of its own neighbours about which way is out —
	## renders as a hole you can see through whatever the mesh is made of,
	## and is refused absolutely. An open boundary is only a defect once the
	## hole it bounds is big enough to read: boundary edges are grouped into
	## the holes they actually form and each hole is measured across, rather
	## than counted.
	## 2026-09-21: three rendered tiles (cottage_a, longhouse, townhouse_b)
	## showed a dark gash the owner suspected was exactly this; the census
	## came back clean on all three (the real cause was the UV atlas's
	## undilated black, now flooded by tools/map3d/dilate_house_atlas.py).
	for type: String in Game.data.map3d_houses:
		var row: Dictionary = Game.data.map3d_houses[type]
		var scene := load(String(row["mesh"])) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate()
		var mesh := _first_mesh(node)
		if mesh != null:
			var result := _manifold_check(mesh)
			assert_lt(float(result["biggest_hole_m"]), HOLE_MAX_M,
				"%s's biggest hole is %.2f m across — a shell is fine, a hole you can see through is not"
					% [type, float(result["biggest_hole_m"])])
			assert_eq(int(result["flipped_faces"]), 0,
				"%s has a flipped face — %d of its triangles disagree with two or more of their own neighbours"
					% [type, int(result["flipped_faces"])])
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
	var edge_tris := {}           # undirected key -> the triangles that walk it
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		@warning_ignore("integer_division")
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
				var owners: Array = edge_tris.get(ukey, [])
				owners.append(tri)
				edge_tris[ukey] = owners
	var open_boundary := 0
	var winding_conflicts := 0
	var tri_bad := {}             # triangle -> how many of its edges conflict
	var border_adj := {}          # vertex key -> its boundary neighbours
	for ukey: String in edge_any:
		var count: int = edge_any[ukey]
		var parts := ukey.split("<>")
		if count == 1:
			open_boundary += 1
			# remember the hole's own edges: a count of them says nothing
			# about whether anything can be seen through them, and the
			# boundary of a shell's open underside is as long as the
			# building is round
			for pair: Array in [[parts[0], parts[1]], [parts[1], parts[0]]]:
				var at: Array = border_adj.get(pair[0], [])
				at.append(pair[1])
				border_adj[pair[0]] = at
		elif count == 2:
			var fwd: String = parts[0] + ">" + parts[1]
			var bwd: String = parts[1] + ">" + parts[0]
			if int(edge_dir.get(fwd, 0)) != 1 or int(edge_dir.get(bwd, 0)) != 1:
				winding_conflicts += 1
				for tri: int in edge_tris.get(ukey, []):
					tri_bad[tri] = int(tri_bad.get(tri, 0)) + 1
	# A FLIPPED face disagrees with every neighbour it has, so it shows up on
	# two or three of its own edges. A lone conflicting edge is the census's
	# own false positive: it keys an edge by its ROUNDED POSITION (a glTF
	# re-export duplicates vertices per face, so position is the only stable
	# identity left), and where the remesh leaves two coincident vertices,
	# two unrelated edges collide on one key and can look like a conflict.
	# Measured 2026-09-22 against Blender's own census over the welded
	# topology (tools/map3d/census_house_meshes.py — and it must WELD first,
	# or glTF's per-seam vertex split leaves nothing sharing an edge and the
	# census reports every mesh clean): every shipped mesh is 0 there, while
	# this one reported a single conflict in church's 26,507 triangles.
	# Counting per FACE rather than per edge tells the two apart without
	# loosening anything — a genuinely flipped face still fails.
	var flipped := 0
	for tri: int in tri_bad:
		if int(tri_bad[tri]) >= 2:
			flipped += 1
	return {"open_boundary_edges": open_boundary, "winding_conflicts": winding_conflicts,
		"flipped_faces": flipped, "biggest_hole_m": _biggest_hole_m(border_adj)}


## The widest hole in a shell, in metres: boundary edges walked into the
## connected loops they form, each loop measured by its own bounding box's
## diagonal. One hole a metre across is a defect; a thousand cracks a
## centimetre wide are what a decimated mesh is made of.
func _biggest_hole_m(border_adj: Dictionary) -> float:
	var seen := {}
	var biggest := 0.0
	for start: String in border_adj:
		if seen.has(start):
			continue
		var stack: Array[String] = [start]
		seen[start] = true
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		while not stack.is_empty():
			var at: String = stack.pop_back()
			var xyz := at.split(",")
			var p := Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
			lo = lo.min(p)
			hi = hi.max(p)
			for next: String in border_adj[at]:
				if not seen.has(next):
					seen[next] = true
					stack.append(next)
		biggest = maxf(biggest, (hi - lo).length())
	return biggest


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
			@warning_ignore("integer_division")
			total += indices.size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			@warning_ignore("integer_division")
			total += verts.size() / 3
	return total
