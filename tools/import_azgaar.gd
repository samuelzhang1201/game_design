extends SceneTree
## Import an Azgaar Fantasy Map Generator full export into game data.
##
## Reads the newest "*Full*.json" and newest map render PNG in assets/maps/
## and writes (all committed to git; re-run after every re-export):
##
##   data/kingdoms.csv    one row per state (state 0 "Neutrals" excluded)
##   data/provinces.csv   one row per province
##   data/burgs.csv       one row per burg
##   assets/maps/world_map.png          byte copy under a stable name
##   assets/maps/world_state_index.png  hit-test bitmap: each land cell's
##       polygon filled with R = state_id & 0xFF, G = state_id >> 8, B = 0;
##       untouched pixels stay white (255,255,255) = water / no state
##
## Polygons are filled with an even-odd scanline rasterizer. Deterministic:
## same inputs => byte-identical outputs. Hand-edits to the generated CSVs
## are overwritten; lasting changes belong in Azgaar.
##
## Usage:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##     --script res://tools/import_azgaar.gd [-- --json PATH --png PATH]

const MAPS := "res://assets/maps"
const DATA := "res://data"
const FICTION_KINGDOMS: Array[String] = ["averlain", "bentleigh", "doncaster", "empire"]
const GENERATED_PNGS: Array[String] = ["world_map.png", "world_state_index.png"]

var _slug_regex := RegEx.create_from_string("[^a-z0-9]+")


func _init() -> void:
	quit(_run())


func _slugify(name: String) -> String:
	var slug := _slug_regex.sub(name.to_lower(), "_", true).lstrip("_").rstrip("_")
	return slug if slug != "" else "unnamed"


## Hands out collision-free slugs (foo, foo_2, foo_3, ...) via `used` counts.
func _take_slug(used: Dictionary, name: String) -> String:
	var base := _slugify(name)
	var n := int(used.get(base, 0)) + 1
	used[base] = n
	return base if n == 1 else "%s_%d" % [base, n]


func _newest(candidates: Array[String], what: String) -> String:
	if candidates.is_empty():
		push_error("error: no %s found in %s" % [what, MAPS])
		return ""
	var best := candidates[0]
	for path in candidates:
		if FileAccess.get_modified_time(path) > FileAccess.get_modified_time(best):
			best = path
	return best


## Azgaar lists start with a literal 0 and may flag removed rows.
func _active(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		if e is Dictionary and not (e as Dictionary).get("removed", false):
			out.append(e)
	return out


func _png_dimensions(path: String) -> Vector2i:
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) != OK:
		push_error("error: %s is not a loadable PNG" % path)
		return Vector2i.ZERO
	return Vector2i(img.get_width(), img.get_height())


## Even-odd scanline fill sampling pixel centers (x+0.5, y+0.5), writing
## into an RGB8 byte buffer. Mirrors the committed bitmap's encoding.
## Coordinates stay in 64-bit floats (not Vector2, which is 32-bit).
func _fill_polygon(buf: PackedByteArray, width: int, height: int,
		px: PackedFloat64Array, py: PackedFloat64Array, state_id: int) -> void:
	var r := state_id & 0xFF
	var g := (state_id >> 8) & 0xFF
	var y_min := py[0]
	var y_max := py[0]
	for v in py:
		y_min = minf(y_min, v)
		y_max = maxf(y_max, v)
	var y_lo := maxi(0, int(y_min))
	var y_hi := mini(height - 1, int(y_max) + 1)
	var n := py.size()
	for y in range(y_lo, y_hi + 1):
		var yc := y + 0.5
		var xs: Array[float] = []
		for i in n:
			var k := (i + 1) % n
			if (py[i] <= yc and yc < py[k]) or (py[k] <= yc and yc < py[i]):
				xs.append(px[i] + (yc - py[i]) / (py[k] - py[i]) * (px[k] - px[i]))
		xs.sort()
		var j := 0
		while j + 1 < xs.size():
			var x_lo := maxi(0, int(xs[j] + 0.5))
			var x_hi := mini(width - 1, int(xs[j + 1] - 0.5))
			for x in range(x_lo, x_hi + 1):
				var o := (y * width + x) * 3
				buf[o] = r
				buf[o + 1] = g
				buf[o + 2] = 0
			j += 2


## Minimal-quoting CSV (matches Python csv.writer): quote only when needed.
func _csv_field(value: String) -> String:
	if value.contains(",") or value.contains("\"") or value.contains("\n"):
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value


func _csv_line(fields: Array[String]) -> String:
	var quoted: Array[String] = []
	for f in fields:
		quoted.append(_csv_field(f))
	return ",".join(quoted) + "\n"


## Coordinates: up to 2 decimals, trailing zeros stripped, whole numbers
## as plain ints ("2204.63", "720.6", "2106").
func _num2(v: float) -> String:
	if v == floorf(v):
		return str(int(v))
	return String.num(v, 2)


func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("error: cannot write %s" % path)
		return false
	f.store_string(text)
	return true


func _run() -> int:
	# --- input selection --------------------------------------------------
	var json_path := ""
	var png_path := ""
	var user_args := OS.get_cmdline_user_args()
	var i := 0
	while i < user_args.size() - 1:
		if user_args[i] == "--json":
			json_path = user_args[i + 1]
		elif user_args[i] == "--png":
			png_path = user_args[i + 1]
		i += 1
	var jsons: Array[String] = []
	var pngs: Array[String] = []
	for file in DirAccess.get_files_at(MAPS):
		var path := MAPS + "/" + file
		if file.contains("Full") and file.ends_with(".json"):
			jsons.append(path)
		elif file.ends_with(".png") and file not in GENERATED_PNGS:
			pngs.append(path)
	if json_path == "":
		json_path = _newest(jsons, "Azgaar full export (*Full*.json)")
	if png_path == "":
		png_path = _newest(pngs, "map render PNG")
	if json_path == "" or png_path == "":
		return 1
	print("json: %s\npng:  %s" % [json_path.get_file(), png_path.get_file()])

	var world: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if world == null:
		push_error("error: cannot parse %s" % json_path)
		return 1
	var info: Dictionary = world["info"]
	var width := int(info["width"])
	var height := int(info["height"])
	if _png_dimensions(png_path) != Vector2i(width, height):
		push_error("error: JSON says %dx%d but PNG is %s" % [
			width, height, _png_dimensions(png_path)])
		return 1

	var pack: Dictionary = world["pack"]
	var rate := float((world["settings"] as Dictionary).get("populationRate", 1000))
	var cells: Array = pack["cells"]
	var vertices: Array = pack["vertices"]
	var states: Array[Dictionary] = []
	for s in _active(pack["states"]):
		if int(s["i"]) != 0:
			states.append(s)
	var provinces := _active(pack["provinces"])
	var burgs := _active(pack["burgs"])

	# --- codes ------------------------------------------------------------
	var state_code: Dictionary = {}
	for s in states:
		state_code[int(s["i"])] = _slugify(String(s["name"]))
	var unique_codes: Dictionary = {}
	for code: String in state_code.values():
		unique_codes[code] = true
	if unique_codes.size() != state_code.size():
		push_error("error: two states slugify to the same kingdom_code")
		return 1
	var prov_slugs: Dictionary = {}
	var burg_slugs: Dictionary = {}
	var prov_code: Dictionary = {}
	var burg_code: Dictionary = {}
	for p in provinces:
		prov_code[int(p["i"])] = _take_slug(prov_slugs, String(p["name"]))
	for b in burgs:
		burg_code[int(b["i"])] = _take_slug(burg_slugs, String(b["name"]))

	# --- referential checks ----------------------------------------------
	for p in provinces:
		if not state_code.has(int(p["state"])):
			push_error("error: province %d references missing state %d" % [
				int(p["i"]), int(p["state"])])
			return 1
	var burg_province: Dictionary = {}
	for b in burgs:
		if not state_code.has(int(b["state"])):
			push_error("error: burg %d references missing state %d" % [
				int(b["i"]), int(b["state"])])
			return 1
		var prov_id := int((cells[int(b["cell"])] as Dictionary).get("province", 0))
		if not prov_code.has(prov_id):
			push_error("error: burg %d cell %d has no province" % [
				int(b["i"]), int(b["cell"])])
			return 1
		burg_province[int(b["i"])] = prov_id

	# --- aggregate cells per province ------------------------------------
	var prov_area: Dictionary = {}
	var prov_pop: Dictionary = {}
	for pid: int in prov_code:
		prov_area[pid] = 0.0
		prov_pop[pid] = 0.0
	for c: Dictionary in cells:
		var pid := int(c.get("province", 0))
		if prov_area.has(pid):
			prov_area[pid] += float(c.get("area", 0))
			prov_pop[pid] += float(c.get("pop", 0))
	for b in burgs:  # urban population on top of the cells' rural points
		prov_pop[burg_province[int(b["i"])]] += float(b.get("population", 0))

	# --- kingdoms.csv -----------------------------------------------------
	var out := _csv_line(["kingdom_code", "state_id", "label", "capital_burg",
		"neighbor_codes", "color", "area", "population", "center_x", "center_y"])
	for s in states:
		var center: Array = (cells[int(s["center"])] as Dictionary)["p"]
		var neighbor_codes: Array[String] = []
		for n in (s.get("neighbors", []) as Array):
			if state_code.has(int(n)):
				neighbor_codes.append(String(state_code[int(n)]))
		out += _csv_line([String(state_code[int(s["i"])]), str(int(s["i"])),
			String(s["name"]), String(burg_code.get(int(s.get("capital", 0)), "")),
			"|".join(neighbor_codes), String(s.get("color", "")),
			str(int(s.get("area", 0))),
			str(int(round((float(s.get("rural", 0)) + float(s.get("urban", 0))) * rate))),
			_num2(float(center[0])), _num2(float(center[1]))])
	if not _write_text(DATA + "/kingdoms.csv", out):
		return 1

	# --- provinces.csv ----------------------------------------------------
	out = _csv_line(["province_code", "label", "kingdom_code", "capital_burg",
		"area", "population"])
	for p in provinces:
		out += _csv_line([String(prov_code[int(p["i"])]), String(p["name"]),
			String(state_code[int(p["state"])]),
			String(burg_code.get(int(p.get("burg", 0)), "")),
			str(int(prov_area[int(p["i"])])),
			str(int(round(float(prov_pop[int(p["i"])]) * rate)))])
	if not _write_text(DATA + "/provinces.csv", out):
		return 1

	# --- burgs.csv --------------------------------------------------------
	out = _csv_line(["burg_code", "label", "province_code", "kingdom_code",
		"population", "is_capital", "is_port", "x", "y"])
	for b in burgs:
		out += _csv_line([String(burg_code[int(b["i"])]), String(b["name"]),
			String(prov_code[burg_province[int(b["i"])]]),
			String(state_code[int(b["state"])]),
			str(int(round(float(b.get("population", 0)) * rate))),
			"1" if b.get("capital") else "0", "1" if b.get("port") else "0",
			_num2(float(b["x"])), _num2(float(b["y"]))])
	if not _write_text(DATA + "/burgs.csv", out):
		return 1

	# --- bitmaps ----------------------------------------------------------
	DirAccess.copy_absolute(ProjectSettings.globalize_path(png_path),
		ProjectSettings.globalize_path(MAPS + "/world_map.png"))
	var buf := PackedByteArray()
	buf.resize(width * height * 3)
	buf.fill(255)
	for c: Dictionary in cells:
		var sid := int(c.get("state", 0))
		if state_code.has(sid):
			var px := PackedFloat64Array()
			var py := PackedFloat64Array()
			for v in (c["v"] as Array):
				var vp: Array = (vertices[int(v)] as Dictionary)["p"]
				px.append(float(vp[0]))
				py.append(float(vp[1]))
			_fill_polygon(buf, width, height, px, py, sid)
	var index_img := Image.create_from_data(width, height, false, Image.FORMAT_RGB8, buf)
	if index_img.save_png(
			ProjectSettings.globalize_path(MAPS + "/world_state_index.png")) != OK:
		push_error("error: cannot write world_state_index.png")
		return 1

	# --- report -----------------------------------------------------------
	var missing: Array[String] = []
	for wanted in FICTION_KINGDOMS:
		if not unique_codes.has(wanted):
			missing.append(wanted)
	if not missing.is_empty():
		print("WARNING: fiction kingdoms not on the map yet: %s" % ", ".join(missing))
		print("         (expected until states are renamed in Azgaar and re-exported)")
	print("wrote %d kingdoms, %d provinces, %d burgs, world_map.png, world_state_index.png"
		% [states.size(), provinces.size(), burgs.size()])
	return 0
