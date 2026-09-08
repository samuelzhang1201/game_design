extends SceneTree
## Import an Azgaar Fantasy Map Generator full export into game data.
##
## Reads the newest "*Full*.json" and newest map render PNG in assets/maps/
## and writes (all committed to git; re-run after every re-export):
##
##   data/maps/<map-id>/kingdoms.csv   one row per state (0 "Neutrals" excluded)
##   data/maps/<map-id>/provinces.csv  one row per province (+ province_id, center)
##   data/maps/<map-id>/burgs.csv      one row per burg (+ type, features)
##   data/maps/<map-id>/borders.csv    one row per closed border loop per kingdom:
##       kingdom_code,loop,points — points as "x y|x y|..." in native map
##       coordinates, so WorldMapView can outline the hovered kingdom
##   data/maps/<map-id>/routes.csv     roads/trails/sea routes as polylines,
##       endpoints snapped to a burg within SNAP_RADIUS px
##   data/maps/<map-id>/rivers.csv     named rivers as polylines through their cells
##   data/maps/<map-id>/markers.csv    points of interest with their legend notes
##   data/maps/<map-id>/biomes.csv     biome id -> label, color, habitability
##   data/maps/<map-id>/map_info.csv   width, height, distance unit/scale, population rate
##   assets/maps/<map-id>/world_map.png byte copy under a stable name
##   assets/maps/<map-id>/world_state_index.png     hit-test bitmap: each cell's
##       polygon filled with R = state_id & 0xFF, G = state_id >> 8, B = 0;
##       untouched pixels stay white (255,255,255) = water / no state
##   assets/maps/<map-id>/world_province_index.png  same encoding, province id
##   assets/maps/<map-id>/world_biome_index.png     R = biome id (land cells only)
##
## Polygons are filled with an even-odd scanline rasterizer. Deterministic:
## same inputs => byte-identical outputs. Hand-edits to the generated CSVs
## are overwritten; lasting changes belong in Azgaar.
##
## Usage:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##     --script res://tools/import_azgaar.gd \\
##       [-- --map-id ID --json PATH --png PATH]

const MAPS := "res://assets/maps"
const DATA := "res://data"
## Which pack this import writes. Authored content no longer names Azgaar
## kingdoms directly — it names realm slots, and the pack's
## realm_bindings.csv binds each slot to one of that map's kingdoms — so the
## check below is against those bindings, per map, not a global list.
const DEFAULT_MAP_ID := "beria"
const GENERATED_PNGS: Array[String] = ["world_map.png", "world_state_index.png",
	"world_province_index.png", "world_biome_index.png"]
## A route endpoint this close (native px) to a burg is "at" that burg.
const SNAP_RADIUS := 3.0

var _slug_regex := RegEx.create_from_string("[^a-z0-9]+")
var _ws_regex := RegEx.create_from_string("\\s+")


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


## "hot-springs" -> "Hot springs" (first letter only; the rest stays as authored).
func _humanize(kind: String) -> String:
	var t := kind.replace("-", " ").replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else ""


func _collapse_ws(text: String) -> String:
	return _ws_regex.sub(text, " ", true).strip_edges()


## The nearest burg id within `radius` native px of (x, y), else -1. Ties go
## to the earlier burg, so output is stable.
func _burg_within(burgs: Array[Dictionary], x: float, y: float, radius: float) -> int:
	var best := -1
	var best_d := radius * radius
	for b in burgs:
		var dx := float(b["x"]) - x
		var dy := float(b["y"]) - y
		var d := dx * dx + dy * dy
		if d < best_d or (d == best_d and best < 0):
			best_d = d
			best = int(b["i"])
	return best


## Rasterize every cell whose id_of(cell) >= 0 into an RGB8 image with the
## two-byte encoding (R = id & 0xFF, G = id >> 8); untouched pixels white.
func _rasterize(cells: Array, vertices: Array, width: int, height: int,
		id_of: Callable) -> Image:
	var buf := PackedByteArray()
	buf.resize(width * height * 3)
	buf.fill(255)
	for c: Dictionary in cells:
		var id := int(id_of.call(c))
		if id < 0:
			continue
		var px := PackedFloat64Array()
		var py := PackedFloat64Array()
		for v in (c["v"] as Array):
			var vp: Array = (vertices[int(v)] as Dictionary)["p"]
			px.append(float(vp[0]))
			py.append(float(vp[1]))
		_fill_polygon(buf, width, height, px, py, id)
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, buf)


func _save_png(img: Image, path: String) -> bool:
	if img.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("error: cannot write %s" % path)
		return false
	return true


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


## A state's outline: every cell edge (undirected vertex pair) that belongs
## to exactly ONE of the state's cells lies on its border — whether the far
## side is another state, water, or the map edge. Those edges are chained
## into closed loops (one polyline each; a pinch vertex simply joins two
## loops into one figure-eight, which draws fine). Deterministic: cells and
## edges are visited in JSON order.
func _state_border_loops(cells: Array, vertices: Array, sid: int) -> Array[PackedVector2Array]:
	var edge_count: Dictionary = {}
	var edge_order: Array[Vector2i] = []
	for c: Dictionary in cells:
		if int(c.get("state", 0)) != sid:
			continue
		var vs: Array = c["v"]
		for i in vs.size():
			var a := int(vs[i])
			var b := int(vs[(i + 1) % vs.size()])
			var key := Vector2i(mini(a, b), maxi(a, b))
			if edge_count.has(key):
				edge_count[key] = int(edge_count[key]) + 1
			else:
				edge_count[key] = 1
				edge_order.append(key)
	var adjacent: Dictionary = {}
	var boundary: Array[Vector2i] = []
	for key in edge_order:
		if int(edge_count[key]) != 1:
			continue
		boundary.append(key)
		for v in [key.x, key.y]:
			if not adjacent.has(v):
				adjacent[v] = []
			(adjacent[v] as Array).append(key)
	var used: Dictionary = {}
	var loops: Array[PackedVector2Array] = []
	for start in boundary:
		if used.has(start):
			continue
		var loop := PackedVector2Array()
		var edge := start
		var v := start.x
		while true:
			used[edge] = true
			var vp: Array = (vertices[v] as Dictionary)["p"]
			loop.append(Vector2(float(vp[0]), float(vp[1])))
			v = edge.y if edge.x == v else edge.x
			var next_edge := Vector2i(-1, -1)
			for e: Vector2i in (adjacent[v] as Array):
				if not used.has(e):
					next_edge = e
					break
			if next_edge.x < 0:
				break
			edge = next_edge
		loops.append(loop)
	return loops


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


## The kingdom_codes a pack's realm_bindings.csv expects to exist. Empty when
## the pack has no bindings yet (a brand new map), which is not an error.
func _bound_kingdoms(path: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var header := f.get_csv_line()
	var col := header.find("kingdom_code")
	if col < 0:
		return out
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() > col and line[col].strip_edges() != "":
			out.append(line[col])
	return out


func _run() -> int:
	# --- input selection --------------------------------------------------
	var json_path := ""
	var png_path := ""
	var map_id := DEFAULT_MAP_ID
	var user_args := OS.get_cmdline_user_args()
	var i := 0
	while i < user_args.size() - 1:
		if user_args[i] == "--json":
			json_path = user_args[i + 1]
		elif user_args[i] == "--png":
			png_path = user_args[i + 1]
		elif user_args[i] == "--map-id":
			map_id = user_args[i + 1]
		i += 1
	var out_data := DATA + "/maps/" + map_id
	var out_art := MAPS + "/" + map_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_data))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_art))
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
	# The render may be exported at an integer scale (2x, 3x...) for
	# sharper zoom; the index bitmap and all coordinates stay at the
	# JSON's native scale, and WorldMapView converts at runtime.
	var png_dims := _png_dimensions(png_path)
	@warning_ignore("integer_division")
	var render_scale := png_dims.x / width
	if render_scale < 1 or png_dims != Vector2i(width * render_scale, height * render_scale):
		push_error("error: PNG must be the JSON's %dx%d at an integer scale, got %s" % [
			width, height, png_dims])
		return 1
	if render_scale > 1:
		print("render scale: %dx" % render_scale)

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
	if not _write_text(out_data + "/kingdoms.csv", out):
		return 1

	# --- provinces.csv ----------------------------------------------------
	out = _csv_line(["province_code", "label", "kingdom_code", "capital_burg",
		"area", "population", "province_id", "center_x", "center_y"])
	for p in provinces:
		var pcenter: Array = (cells[int(p["center"])] as Dictionary)["p"]
		out += _csv_line([String(prov_code[int(p["i"])]), String(p["name"]),
			String(state_code[int(p["state"])]),
			String(burg_code.get(int(p.get("burg", 0)), "")),
			str(int(prov_area[int(p["i"])])),
			str(int(round(float(prov_pop[int(p["i"])]) * rate))),
			str(int(p["i"])), _num2(float(pcenter[0])), _num2(float(pcenter[1]))])
	if not _write_text(out_data + "/provinces.csv", out):
		return 1

	# --- burgs.csv --------------------------------------------------------
	out = _csv_line(["burg_code", "label", "province_code", "kingdom_code",
		"population", "is_capital", "is_port", "x", "y", "type", "features"])
	for b in burgs:
		var feats: Array[String] = []
		for flag in ["walls", "citadel", "temple", "plaza", "shanty"]:
			if b.get(flag):
				feats.append(flag)
		out += _csv_line([String(burg_code[int(b["i"])]), String(b["name"]),
			String(prov_code[burg_province[int(b["i"])]]),
			String(state_code[int(b["state"])]),
			str(int(round(float(b.get("population", 0)) * rate))),
			"1" if b.get("capital") else "0", "1" if b.get("port") else "0",
			_num2(float(b["x"])), _num2(float(b["y"])),
			String(b.get("type", "Generic")), "|".join(feats)])
	if not _write_text(out_data + "/burgs.csv", out):
		return 1

	# --- borders.csv ------------------------------------------------------
	out = _csv_line(["kingdom_code", "loop", "points"])
	var loop_total := 0
	for s in states:
		var loops := _state_border_loops(cells, vertices, int(s["i"]))
		for li in loops.size():
			var pts: Array[String] = []
			for p in loops[li]:
				pts.append("%s %s" % [_num2(p.x), _num2(p.y)])
			out += _csv_line([String(state_code[int(s["i"])]), str(li), "|".join(pts)])
		loop_total += loops.size()
	if not _write_text(out_data + "/borders.csv", out):
		return 1

	# --- routes.csv -------------------------------------------------------
	out = _csv_line(["route_code", "label", "group", "from_burg", "to_burg", "length", "points"])
	var route_slugs: Dictionary = {}
	var routes := _active(pack.get("routes", []))
	for r in routes:
		var raw: Array = r.get("points", [])
		if raw.size() < 2:
			push_error("error: route %d has fewer than 2 points" % int(r.get("i", -1)))
			return 1
		var pts: Array[String] = []
		var length := 0.0
		var lx := 0.0
		var ly := 0.0
		for pi in raw.size():
			var pt: Array = raw[pi]
			var x := float(pt[0])
			var y := float(pt[1])
			if pi > 0:
				length += sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly))
			lx = x
			ly = y
			pts.append("%s %s" % [_num2(x), _num2(y)])
		var first: Array = raw[0]
		var last: Array = raw[raw.size() - 1]
		var from_id := _burg_within(burgs, float(first[0]), float(first[1]), SNAP_RADIUS)
		var to_id := _burg_within(burgs, float(last[0]), float(last[1]), SNAP_RADIUS)
		var label := String(r.get("name", ""))
		out += _csv_line([_take_slug(route_slugs, label), label, String(r.get("group", "")),
			String(burg_code.get(from_id, "")), String(burg_code.get(to_id, "")),
			String.num(length, 1), "|".join(pts)])
	if not _write_text(out_data + "/routes.csv", out):
		return 1

	# --- rivers.csv -------------------------------------------------------
	out = _csv_line(["river_code", "label", "type", "length", "kingdom_codes", "points"])
	var river_slugs: Dictionary = {}
	var river_count := 0
	for rv in _active(pack.get("rivers", [])):
		var rcells: Array = rv.get("cells", [])
		if rcells.size() < 2:
			continue  # a one-cell river has no line to draw
		var pts: Array[String] = []
		var through: Array[String] = []
		var length := 0.0
		var lx := 0.0
		var ly := 0.0
		for ci in rcells.size():
			var c: Dictionary = cells[int(rcells[ci])]
			var cp: Array = c["p"]
			var x := float(cp[0])
			var y := float(cp[1])
			if ci > 0:
				length += sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly))
			lx = x
			ly = y
			pts.append("%s %s" % [_num2(x), _num2(y)])
			var sid := int(c.get("state", 0))
			if state_code.has(sid) and not through.has(String(state_code[sid])):
				through.append(String(state_code[sid]))
		var label := String(rv.get("name", ""))
		out += _csv_line([_take_slug(river_slugs, label), label, String(rv.get("type", "River")),
			String.num(length, 1), "|".join(through), "|".join(pts)])
		river_count += 1
	if not _write_text(out_data + "/rivers.csv", out):
		return 1

	# --- markers.csv ------------------------------------------------------
	var notes: Dictionary = {}
	for n in (world.get("notes", []) as Array):
		if n is Dictionary:
			notes[String((n as Dictionary).get("id", ""))] = n
	out = _csv_line(["marker_code", "label", "type", "x", "y", "legend"])
	var marker_slugs: Dictionary = {}
	var unnoted := 0
	var markers := _active(pack.get("markers", []))
	for m in markers:
		if not m.has("x") or not m.has("y"):
			push_error("error: marker %d has no coordinates" % int(m.get("i", -1)))
			return 1
		var note: Dictionary = notes.get("marker%d" % int(m["i"]), {})
		if note.is_empty():
			unnoted += 1
		var label := String(note.get("name", _humanize(String(m.get("type", "marker")))))
		out += _csv_line([_take_slug(marker_slugs, label), label, String(m.get("type", "")),
			_num2(float(m["x"])), _num2(float(m["y"])),
			_collapse_ws(String(note.get("legend", "")))])
	if not _write_text(out_data + "/markers.csv", out):
		return 1
	if unnoted > 0:
		print("WARNING: %d markers have no note; their type stands in as the label" % unnoted)

	# --- biomes.csv -------------------------------------------------------
	out = _csv_line(["biome_id", "label", "color", "habitability"])
	for bm in _active(pack.get("biomes", [])):
		out += _csv_line([str(int(bm["i"])), String(bm["name"]), String(bm.get("color", "")),
			str(int(bm.get("habitability", 0)))])
	if not _write_text(out_data + "/biomes.csv", out):
		return 1

	# --- map_info.csv -----------------------------------------------------
	var settings: Dictionary = world["settings"]
	out = _csv_line(["key", "value"])
	out += _csv_line(["width", str(width)])
	out += _csv_line(["height", str(height)])
	out += _csv_line(["distance_unit", String(settings.get("distanceUnit", "km"))])
	out += _csv_line(["distance_scale", _num2(float(settings.get("distanceScale", 1)))])
	out += _csv_line(["population_rate", _num2(rate)])
	if not _write_text(out_data + "/map_info.csv", out):
		return 1

	# --- bitmaps ----------------------------------------------------------
	DirAccess.copy_absolute(ProjectSettings.globalize_path(png_path),
		ProjectSettings.globalize_path(out_art + "/world_map.png"))
	var state_img := _rasterize(cells, vertices, width, height, func(c: Dictionary) -> int:
		var sid := int(c.get("state", 0))
		return sid if state_code.has(sid) else -1)
	if not _save_png(state_img, out_art + "/world_state_index.png"):
		return 1
	var province_img := _rasterize(cells, vertices, width, height, func(c: Dictionary) -> int:
		var pid := int(c.get("province", 0))
		return pid if prov_code.has(pid) else -1)
	if not _save_png(province_img, out_art + "/world_province_index.png"):
		return 1
	var biome_img := _rasterize(cells, vertices, width, height, func(c: Dictionary) -> int:
		var bid := int(c.get("biome", 0))
		return bid if bid > 0 else -1)
	if not _save_png(biome_img, out_art + "/world_biome_index.png"):
		return 1

	# --- report -----------------------------------------------------------
	var missing: Array[String] = []
	for bound in _bound_kingdoms(out_data + "/realm_bindings.csv"):
		if not unique_codes.has(bound):
			missing.append(bound)
	if not missing.is_empty():
		print("WARNING: realm_bindings.csv binds slots to kingdoms this export")
		print("         does not contain: %s" % ", ".join(missing))
		print("         Fix the bindings or rename the states in Azgaar —")
		print("         until then the cast has no home on this map.")
	print("map '%s': wrote %d kingdoms, %d provinces, %d burgs, %d border loops, %d routes, %d rivers, %d markers into %s, art into %s"
		% [map_id, states.size(), provinces.size(), burgs.size(), loop_total,
			routes.size(), river_count, markers.size(), out_data, out_art])
	return 0
