# scripts/ledger3d/ledger_link_mesh.gd
class_name LedgerLinkMesh
extends RefCounted
## The galaxy's links as ONE ribbon mesh (spec 2026-09-30-ledger-galaxy-
## design §5): a quad per link, its four vertices at the two ends; link.gdshader
## widens each quad across the view by its width in SCREEN px, so a link keeps
## its weight at every zoom. Colour runs from the source's end to the far end
## (the clusters' shading), its alpha the drawn opacity. Each vertex also
## carries its own end's star and the far end's — seed, drawn radius and
## whether it is the selected one (CUSTOM2 here, CUSTOM3 there) — so the shader
## moves both ends by the very wobble their stars are drawn with (owner
## 2026-10-01: a larger wobble must not leave a link's end behind). Pure arrays.

const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)


## One end's star as a vertex reads it: [seed x, seed y, drawn radius,
## selected]. A segment with no star data (`a_star` / `b_star` absent) holds
## still.
static func _star(s: Dictionary, key: String) -> Array:
	var c: Color = s.get(key, Color(0, 0, 0, 0))
	return [c.r, c.g, c.b, c.a]


static func arrays(segments: Array) -> Array:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var c2 := PackedFloat32Array()
	var c3 := PackedFloat32Array()
	var idx := PackedInt32Array()
	for s: Dictionary in segments:
		var base := verts.size()
		var star_a := _star(s, "a_star")
		var star_b := _star(s, "b_star")
		for end in 2:
			var here: Vector3 = s["a"] if end == 0 else s["b"]
			var there: Vector3 = s["b"] if end == 0 else s["a"]
			var end_sign := 1.0 if end == 0 else -1.0
			for k in 2:
				var side := -1.0 if k == 0 else 1.0
				verts.append(here)
				cols.append(s["ca"] if end == 0 else s["cb"])
				uvs.append(Vector2(float(end), float(k)))
				uv2.append(Vector2(float(s["speed"]), 1.0 if bool(s["dashed"]) else 0.0))
				c0.append_array([there.x, there.y, there.z, side * end_sign])
				c1.append_array([float(s["width_px"]), float(s["shift_px"]) * end_sign, float(s["glow"]), 0.0])
				c2.append_array(star_a if end == 0 else star_b)
				c3.append_array(star_b if end == 0 else star_a)
		idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_CUSTOM2] = c2
	arr[Mesh.ARRAY_CUSTOM3] = c3
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Moves every link's two ends in arrays already built by `arrays` (the same
## segments, in the same order): `ends` holds [a, b] per segment. Only the
## positions and the far ends change, so a chart that is settling re-lays its
## links without restyling them.
static func move_ends(arr: Array, ends: Array) -> void:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	for k in ends.size():
		var a: Vector3 = ends[k][0]
		var b: Vector3 = ends[k][1]
		var v := k * 4
		verts[v] = a
		verts[v + 1] = a
		verts[v + 2] = b
		verts[v + 3] = b
		for j in 4:
			var there := b if j < 2 else a
			var at := (v + j) * 4
			c0[at] = there.x
			c0[at + 1] = there.y
			c0[at + 2] = there.z
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_CUSTOM0] = c0


## A mesh of arrays built by `arrays` (empty when there are no segments).
static func mesh_of(arr: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	if not (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, FORMAT)
	return m


static func mesh(segments: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	if not segments.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(segments), [], {}, FORMAT)
	return m
