class_name WarBake
extends RefCounted
## The 3D build's own bake for the WAR ROOM's table (spec 2026-10-02-war-room-v2
## §2.4; plan B: the heights Terrain3D was built from, read here directly so the
## room needs no 3D map loaded and runs headless): bake/height_war.r16 — half
## floats over the pack's own `vertex_m` vertices, the file the repository
## carries (2026-10-02: the padded float32 bake/height.r32 is 128 MB, past a git
## host's limit; it is read instead when only it is there) — of which only the
## rows a sheet needs are read, and bake/woods.png — R the canopy's share,
## G the conifers', one texel per two vertices from the pack's corner. Reads
## only. Null when the bake is not built (a fresh clone).

static var _opened: Dictionary = {}   # map id -> WarBake (or null)

var _dir := ""
var _vm := 20.0
var _m_per_px := 50.0
var _sea_y := 0.0
var _fw := 0
var _fh := 0
var _px0 := 0
var _pz0 := 0
var _woods: Image
var _origin := Vector2.ZERO   # the pack's (0, 0) in world metres
var _rivers: Variant = null   # code -> PackedVector2Array pack px, read once (river_courses)
var _file := "height.r32"
var _bytes := 4   # a sample's size: 4 (float32) or 2 (float16)


static func open(dir: String) -> WarBake:
	var path := dir + "/world.json"
	var half := FileAccess.file_exists(dir + "/height_war.r16")
	if not FileAccess.file_exists(path) or not (half or FileAccess.file_exists(dir + "/height.r32")):
		return null
	var world: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not world is Dictionary:
		return null
	var b := WarBake.new()
	b._dir = dir
	b._vm = float(world["vertex_m"])
	b._m_per_px = float(world["m_per_px"])
	b._origin = Vector2(float(world["pack_origin"][0]), float(world["pack_origin"][1]))
	b._sea_y = float(world["sea_y"])
	b._fw = int(world["padded"][0])
	b._fh = int(world["padded"][1])
	b._px0 = roundi((float(world["pack_origin"][0]) - float(world["import_corner"][0])) / b._vm)
	b._pz0 = roundi((float(world["pack_origin"][1]) - float(world["import_corner"][1])) / b._vm)
	if half:   # the pack's own vertices: no padding round them
		b._file = "height_war.r16"
		b._bytes = 2
		b._fw = int(world["vertices"][0])
		b._fh = int(world["vertices"][1])
		b._px0 = 0
		b._pz0 = 0
	return b


## The bake of the repository's pack, opened once per map id.
static func of(repo: DataRepository) -> WarBake:
	if not _opened.has(repo.map_id):
		_opened[repo.map_id] = open(repo.map3d_dir() + "/bake")
	return _opened[repo.map_id]


static func forget() -> void:
	_opened.clear()


## The rivers as the 3D map draws them (owner 2026-10-07: the sheet's rivers
## were stiff, ruler-straight): rivers.json beside the build — the pack's
## polylines smoothed, meandered and joined by tools/map3d/bake_world.py, a
## sample every few tens of metres — as code -> PackedVector2Array in pack px,
## source to mouth; {} without the file.
func river_courses() -> Dictionary:
	if _rivers != null:
		return _rivers
	var out: Dictionary = {}
	_rivers = out
	var path := _dir.get_base_dir().path_join("rivers.json")
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return out
	for r: Variant in (data as Dictionary).get("rivers", []):
		var pts: Array = (r as Dictionary).get("points", [])
		var line := PackedVector2Array()
		for p: Array in pts:
			line.append((Vector2(float(p[0]), float(p[1])) - _origin) / _m_per_px)
		var code := String((r as Dictionary).get("code", ""))
		if line.size() >= 2 and line.size() > (out.get(code, PackedVector2Array()) as PackedVector2Array).size():
			out[code] = line
	return out


## The padded grid's vertex coordinates of a pack px.
func _vertex(px: Vector2) -> Vector2:
	var k := _m_per_px / _vm
	return Vector2(float(_px0) + px.x * k, float(_pz0) + px.y * k)


## RAW metres above the sea line (negative at sea) on an nx x nz grid over the
## pack rect, row-major z outer; the rect is held to the file's own grid.
func heights(rect: Rect2, nx: int, nz: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	var a := _vertex(rect.position)
	var b := _vertex(rect.end)
	var lo_x := clampi(floori(minf(a.x, b.x)), 0, _fw - 1)
	var hi_x := clampi(ceili(maxf(a.x, b.x)) + 1, 0, _fw - 1)
	var lo_z := clampi(floori(minf(a.y, b.y)), 0, _fh - 1)
	var hi_z := clampi(ceili(maxf(a.y, b.y)) + 1, 0, _fh - 1)
	var cols := hi_x - lo_x + 1
	var rows := hi_z - lo_z + 1
	var f := FileAccess.open(_dir + "/" + _file, FileAccess.READ)
	if f == null:
		return out
	var block := PackedFloat32Array()
	block.resize(cols * rows)
	for r in rows:
		f.seek(((lo_z + r) * _fw + lo_x) * _bytes)
		var raw := f.get_buffer(cols * _bytes)
		@warning_ignore("integer_division")
		var n := mini(raw.size() / _bytes, cols)
		for c in n:
			block[r * cols + c] = raw.decode_half(c * 2) if _bytes == 2 else raw.decode_float(c * 4)
	f.close()
	for j in nz:
		for i in nx:
			var px := rect.position + rect.size * Vector2(float(i) / float(maxi(nx - 1, 1)), float(j) / float(maxi(nz - 1, 1)))
			var v := _vertex(px)
			var u := clampf(v.x - float(lo_x), 0.0, float(cols - 1))
			var w := clampf(v.y - float(lo_z), 0.0, float(rows - 1))
			var i0 := mini(int(u), maxi(cols - 2, 0))
			var j0 := mini(int(w), maxi(rows - 2, 0))
			var i1 := mini(i0 + 1, cols - 1)
			var j1 := mini(j0 + 1, rows - 1)
			var fu := u - float(i0)
			var fv := w - float(j0)
			var top := lerpf(block[j0 * cols + i0], block[j0 * cols + i1], fu)
			var bot := lerpf(block[j1 * cols + i0], block[j1 * cols + i1], fu)
			out[j * nx + i] = lerpf(top, bot, fv) - _sea_y
	return out


## The woods over a pack rect, every `step_px` pack px where a canopy is:
## {at (pack px), cover, conifer}.
func woods(rect: Rect2, step_px: float) -> Array:
	var out: Array = []
	if _woods == null:
		var path := _dir + "/woods.png"
		if not FileAccess.file_exists(path):
			return out
		_woods = Image.load_from_file(path)  # res://: exported, the res:// tree is the pack
		if _woods == null:
			return out
	var k := _m_per_px / (_vm * 2.0)   # woods texels per pack px
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x
		while x < rect.end.x:
			var tx := int(x * k)
			var ty := int(y * k)
			if x >= 0.0 and y >= 0.0 and tx < _woods.get_width() and ty < _woods.get_height():
				var c := _woods.get_pixel(tx, ty)
				if c.r > 0.0:
					out.append({"at": Vector2(x, y), "cover": c.r, "conifer": c.g})
			x += step_px
		y += step_px
	return out
