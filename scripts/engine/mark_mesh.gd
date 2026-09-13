class_name MarkMesh
extends RefCounted
## A layer of marks as ONE mesh (owner 2026-09-13, the map's decor rework):
## every mark a standing quad in NATIVE map px, its texture a rectangle of
## a MarkAtlas, its tint a vertex colour — so the whole layer is one
## draw_mesh whose transform is the view's offset and zoom, rebuilt only
## when a mark's colour changes (conquest recolours a wood) and never per
## frame or per zoom. The GPU clips what is off screen; on the beria pack
## the eleven thousand woods and hills were one draw_texture_rect each,
## ~7 ms of _draw and ten more of canvas-command CPU a frame.
##
## A mark stands ON its point the way the settlement art does: `foot` of its
## height above the point, the rest below. Marks are drawn in y order so a
## wood lower on the sheet overlaps one behind it.

## marks: [{pos: Vector2 (native), texture: String (atlas path), height:
## float (native px), color: Color}]. Marks whose texture the atlas lacks
## are skipped. Returns an empty ArrayMesh (no surfaces) for no marks.
static func build(marks: Array, atlas: MarkAtlas, foot: float = 0.85) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var kept: Array = []
	for m: Dictionary in marks:
		if atlas != null and atlas.has(String(m["texture"])):
			kept.append(m)
	if kept.is_empty():
		return mesh
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector2).y < (b["pos"] as Vector2).y)
	var n := kept.size()
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(n * 4)
	uvs.resize(n * 4)
	colors.resize(n * 4)
	indices.resize(n * 6)
	for i in n:
		var m: Dictionary = kept[i]
		var path := String(m["texture"])
		var h := float(m["height"])
		var w := h * float(atlas.aspect[path])
		var pos: Vector2 = m["pos"]
		var tl := pos - Vector2(w * 0.5, h * foot)
		var r: Rect2 = atlas.uv[path]
		var c: Color = m.get("color", Color.WHITE)
		var v := i * 4
		verts[v] = tl
		verts[v + 1] = tl + Vector2(w, 0.0)
		verts[v + 2] = tl + Vector2(w, h)
		verts[v + 3] = tl + Vector2(0.0, h)
		uvs[v] = r.position
		uvs[v + 1] = r.position + Vector2(r.size.x, 0.0)
		uvs[v + 2] = r.end
		uvs[v + 3] = r.position + Vector2(0.0, r.size.y)
		for k in 4:
			colors[v + k] = c
		var t := i * 6
		indices[t] = v
		indices[t + 1] = v + 1
		indices[t + 2] = v + 2
		indices[t + 3] = v
		indices[t + 4] = v + 2
		indices[t + 5] = v + 3
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## How many marks a built mesh carries.
static func quad_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / 4
