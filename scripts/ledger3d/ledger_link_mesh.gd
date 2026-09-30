# scripts/ledger3d/ledger_link_mesh.gd
class_name LedgerLinkMesh
extends RefCounted
## The galaxy's links as ONE ribbon mesh (spec 2026-09-30-ledger-galaxy-
## design §5): a quad per link, its four vertices at the two ends; link.gdshader
## widens each quad across the view by its width in SCREEN px, so a link keeps
## its weight at every zoom. Colour runs from the source's end to the far end
## (the clusters' shading), its alpha the drawn opacity. Pure arrays.

const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)


static func arrays(segments: Array) -> Array:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	for s: Dictionary in segments:
		var base := verts.size()
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
		idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


static func mesh(segments: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	if not segments.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(segments), [], {}, FORMAT)
	return m
