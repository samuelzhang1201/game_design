class_name Map3DRivers
extends RefCounted
## The 3D map's rivers as ONE ribbon mesh (pure, tested headless). The bake
## (tools/map3d/bake_world.py) carves each river's bed and writes its water
## line, source -> mouth, to rivers.json beside the built scene: per point
## [x_m, z_m, water_y_m, width_m, mouth 0..1] in world metres. Each point
## becomes two vertices ON the centreline whose NORMAL is the side to grow
## toward — water_river.gdshader widens them to the river's width, or to a
## minimum screen width far away, as border_line.gdshader does for borders.

## A river leaving (or entering) a lake reads in the bake as the water line
## jumping tens of metres between two consecutive samples (Task 6 review):
## parse()'s default matches balance.csv map3d_river_split_rise_m.
const DEFAULT_SPLIT_RISE_M := 2.0


## rivers.json text -> [{code, pos: PackedVector3Array, width, mouth:
## PackedFloat32Array}]; [] for anything unreadable. A course is split into
## separate strips wherever water_y rises by more than split_rise_m between
## consecutive points, so no vertical wall of water is drawn at a lake
## exit — a fragment left with fewer than 2 points (two splits back to
## back) is dropped, since it cannot make a ribbon on its own.
static func parse(text: String, split_rise_m: float = DEFAULT_SPLIT_RISE_M) -> Array:
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary) or not (data as Dictionary).has("rivers"):
		return []
	var out: Array = []
	for r: Variant in (data as Dictionary)["rivers"]:
		var pts: Array = (r as Dictionary).get("points", [])
		if pts.size() < 2:
			continue
		var code := String((r as Dictionary).get("code", ""))
		var part := 1
		var pos := PackedVector3Array()
		var width := PackedFloat32Array()
		var mouth := PackedFloat32Array()
		var prev_y := NAN
		for p: Array in pts:
			var y := float(p[2])
			if not is_nan(prev_y) and y - prev_y > split_rise_m:
				part = _flush(out, code, part, pos, width, mouth)
				pos = PackedVector3Array()
				width = PackedFloat32Array()
				mouth = PackedFloat32Array()
			pos.append(Vector3(float(p[0]), y, float(p[1])))
			width.append(float(p[3]))
			mouth.append(float(p[4]))
			prev_y = y
		_flush(out, code, part, pos, width, mouth)
	return out


## Appends the strip if it has enough points to be a ribbon; returns the
## part count to use for the NEXT strip (only advanced when this one drew).
static func _flush(out: Array, code: String, part: int, pos: PackedVector3Array,
		width: PackedFloat32Array, mouth: PackedFloat32Array) -> int:
	if pos.size() < 2:
		return part
	out.append({"code": code if part == 1 else "%s#%d" % [code, part],
		"pos": pos, "width": width, "mouth": mouth})
	return part + 1


## Mesh arrays for every course, or [] when there is none.
static func ribbon_arrays(courses: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var index := PackedInt32Array()
	for c: Dictionary in courses:
		var pos: PackedVector3Array = c["pos"]
		var width: PackedFloat32Array = c["width"]
		var mouth: PackedFloat32Array = c["mouth"]
		var along := 0.0
		for i in pos.size():
			var a := pos[maxi(i - 1, 0)]
			var b := pos[mini(i + 1, pos.size() - 1)]
			var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
			var side := Vector3(dir.y, 0.0, -dir.x)  # left of the flow
			if i > 0:
				along += Vector2(pos[i].x - pos[i - 1].x, pos[i].z - pos[i - 1].z).length()
			var base := verts.size()
			for s: int in [0, 1]:
				verts.append(pos[i])
				normals.append(side * (1.0 if s == 0 else -1.0))
				uv.append(Vector2(float(s), along))
				uv2.append(Vector2(width[i], mouth[i]))
			if i > 0:
				index.append_array([base - 2, base - 1, base, base - 1, base + 1, base])
	if verts.is_empty():
		return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays
