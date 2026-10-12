class_name Map3DUnitGlow
extends RefCounted
## A selected regiment piece's glow (owner 2026-10-10: the selection is a faint
## glow under the piece, never a box or a number): a flat quad, child of the
## piece's formation node, lying on its SEAT under the figures — the node is
## tilted to the seat's plane, so the quad is too — depth-tested so the figures
## draw over it. Its look is `scenes/map3d/materials/unit_select_glow.tres`
## (+ `unit_select_glow.gdshader`); its size is balance map3d_unit_glow_ratio ×
## the formation's half EXTENT, an ellipse (a line of four is long and thin),
## so it stays inside the footprint the seat raised the piece clear of and
## never cuts into a slope (the grid is draped on the heightmap, see `place`). The band is narrow: `map3d_unit_glow_inner` to
## `map3d_unit_glow_peak`, set per piece as instance uniforms.

const MATERIAL := preload("res://scenes/map3d/materials/unit_select_glow.tres")
const NAME := "Glow"


## The piece's glow node, made on first use (no owner: never saved).
static func node_of(repo: DataRepository, piece: Dictionary) -> MeshInstance3D:
	var host: Node3D = piece["node"]
	var glow := host.get_node_or_null(NAME) as MeshInstance3D
	if glow != null:
		return glow
	var quad := PlaneMesh.new()  # lies in its XZ plane
	var half: Vector2 = piece["extent"] * repo.bal("map3d_unit_glow_ratio")
	quad.size = half * 2.0
	glow = MeshInstance3D.new()
	glow.name = NAME
	glow.mesh = quad
	glow.material_override = MATERIAL
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.set_instance_shader_parameter("half_m", half)
	glow.set_instance_shader_parameter("inner", repo.bal("map3d_unit_glow_inner"))
	glow.set_instance_shader_parameter("peak", repo.bal("map3d_unit_glow_peak"))
	glow.visible = false
	host.add_child(glow)
	return glow


## Shown or hidden, and DRAPED on the ground: the quad's grid is laid over the
## heightmap under the piece (`height_at`, world XZ -> metres), so on a slope
## the ring lies on the slope's own face, never a flat plane floating over its
## low side. Each point sits map3d_unit_glow_lift of the piece's height over the
## ground; `k` is the piece's scale. Re-draped only when the piece is re-seated.
static func place(repo: DataRepository, height_at: Callable, piece: Dictionary, on: bool, k: float) -> void:
	var host: Node3D = piece["node"]
	var glow := host.get_node_or_null(NAME) as MeshInstance3D
	if not on:
		if glow != null:
			glow.visible = false
		return
	glow = node_of(repo, piece)
	var key := [piece.get("seat_key", []), host.transform]
	if not glow.visible or piece.get("glow_key", []) != key:
		piece["glow_key"] = key
		glow.position = Vector3.ZERO
		glow.mesh = draped(repo, height_at, host.transform, piece["extent"] * repo.bal("map3d_unit_glow_ratio"),
			float(piece["height_m"]) * k * repo.bal("map3d_unit_glow_lift"))
	glow.visible = true


## The glow's mesh in the piece's local frame: a GRID x GRID lattice over the
## quad (local half extent `half`), each vertex dropped onto the ground under
## its world position plus `lift_m`; UV 0..1 across the quad (the shader's).
static func draped(repo: DataRepository, height_at: Callable, host_xf: Transform3D, half: Vector2,
		lift_m: float) -> ArrayMesh:
	var n := int(repo.bal("map3d_unit_glow_grid"))
	var inv := host_xf.affine_inverse()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			var u := float(i) / n
			var v := float(j) / n
			var local := Vector3((u * 2.0 - 1.0) * half.x, 0.0, (v * 2.0 - 1.0) * half.y)
			var w := host_xf * local
			verts.append(inv * Vector3(w.x, float(height_at.call(Vector2(w.x, w.z))) + lift_m, w.z))
			uvs.append(Vector2(u, v))
			normals.append(Vector3.UP)
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Whether the piece's glow shows (tests).
static func shown(piece: Dictionary) -> bool:
	var glow := (piece["node"] as Node3D).get_node_or_null(NAME) as Node3D
	return glow != null and glow.visible
