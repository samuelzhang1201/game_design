extends SceneTree
## Import an Azgaar Fantasy Map Generator full export into game data.
##
## Reads the newest "*Full*.json" and newest map render PNG in assets/maps/
## (or in any pack folder under it) and writes (all committed to git; re-run
## after every re-export):
##
## Tables are grouped by domain (spec 2026-09-09 §1.1); <pack> = data/maps/<map-id>:
##   <pack>/map_info.csv               width, height, distance unit/scale, population rate
##   (<pack>/realm_bindings.csv and house_bindings.csv are hand-maintained,
##    never written here: they bind authored realms and houses to this map)
##   <pack>/political/kingdoms.csv     one row per state (0 "Neutrals" excluded):
##       identity, capital, neighbors, area, population, form, culture, majority religion
##   <pack>/political/provinces.csv    one row per province (+ province_id, center, form, majority biome)
##   <pack>/political/burgs.csv        one row per burg (+ type, features, group, culture,
##       elevation in metres, temperature in °C)
##   <pack>/political/borders.csv      one row per closed border loop per kingdom:
##       kingdom_code,loop,points — points as "x y|x y|..." in native map
##       coordinates, so WorldMapView can outline the hovered kingdom
##   <pack>/political/province_borders.csv  the same, per province — the
##       unit ownership moves in, so a kingdom's live border is the merge of
##       the loops of the provinces it holds
##   <pack>/political/diplomacy.csv    every ordered pair of kingdoms and its stance
##   <pack>/political/campaigns.csv    the wars Azgaar generated as history
##   <pack>/economy/kingdoms.csv       treasury, sales/poll tax, urban/rural population
##   <pack>/economy/provinces.csv      urban/rural population
##   <pack>/economy/burgs.csv          treasury, product, market; production.csv what
##       each burg makes; goods.csv, markets.csv, market_goods.csv the trade tables
##   <pack>/military/kingdoms.csv      unit totals, regiment count, strength, alert
##   <pack>/military/regiments.csv     one row per regiment: its province and unit counts
##   <pack>/military/unit_types.csv    the unit definitions (rates, crew, power)
##   <pack>/society/cultures.csv, religions.csv, zones.csv (hazards -> provinces)
##   <pack>/geography/routes.csv       roads/trails/sea routes as polylines,
##       endpoints snapped to a burg within SNAP_RADIUS px
##   <pack>/geography/rivers.csv       named rivers as polylines through their cells
##   <pack>/geography/markers.csv      points of interest with their legend notes
##   <pack>/geography/biomes.csv       biome id -> label, color, habitability
##   <pack>/geography/vertices.csv     every Voronoi vertex: vertex_id,x,y
##   <pack>/geography/cells.csv        every cell: its vertex ids, height (0-100),
##       biome, water kind ("" land / ocean / lake), neighbour cell ids —
##       MapTerrain builds the terrain mesh from these; no render PNG exists
##   <pack>/geography/coasts.csv       closed shore loops: the outline of all
##       land ("land") and of each lake ("lake")
## Each domain folder carries a .gdignore so Godot does not import the tables
## as translations; FileAccess reads them regardless.
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
##       [-- --map-id ID --json PATH]

const MAPS := "res://assets/maps"
const DATA := "res://data"
## Which pack this import writes. Authored content no longer names Azgaar
## kingdoms directly — it names realm slots, and the pack's
## realm_bindings.csv binds each slot to one of that map's kingdoms — so the
## check below is against those bindings, per map, not a global list.
const DEFAULT_MAP_ID := "beria"
## A route endpoint this close (native px) to a burg is "at" that burg.
const SNAP_RADIUS := 3.0
## Title words for routes Azgaar left nameless (most trails and sea routes).
const ROUTE_WORDS := {"roads": "Road", "trails": "Trail", "searoutes": "Sea route"}
## Pack tables are grouped by domain (spec 2026-09-09 §1.1). Each folder carries
## a .gdignore so Godot does not import game tables as translations; FileAccess
## reads them regardless. An export preset must include data/** explicitly.
const DOMAINS: Array[String] = ["geography", "political", "economy", "military", "society"]
## Azgaar's convention: a cell with h below this is water.
const SEA_LEVEL := 20


func _ensure_domains(out_data: String) -> void:
	for d in DOMAINS:
		var dir := out_data + "/" + d
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		if not FileAccess.file_exists(dir + "/.gdignore"):
			_write_text(dir + "/.gdignore", "")


## The key with the largest weight; ties go to the lower key so output is stable.
func _majority_key(weights: Dictionary) -> int:
	var best := 0
	var best_w := -1.0
	var ids := weights.keys()
	ids.sort()
	for k in ids:
		if float(weights[k]) > best_w:
			best_w = float(weights[k])
			best = int(k)
	return best


## Majority religion of a state's cells by rural population; ties go to the
## lower religion id so output is stable.
func _majority_religion(cells: Array, sid: int) -> int:
	var pop: Dictionary = {}
	for c: Dictionary in cells:
		if int(c.get("state", 0)) != sid:
			continue
		var rid := int(c.get("religion", 0))
		pop[rid] = float(pop.get(rid, 0.0)) + float(c.get("pop", 0))
	var best := 0
	var best_pop := -1.0
	var ids := pop.keys()
	ids.sort()
	for rid in ids:
		if float(pop[rid]) > best_pop:
			best_pop = float(pop[rid])
			best = int(rid)
	return best

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


## Azgaar leaves most trails and sea routes nameless; the card and tooltip
## still need a title, so build one from the group and the snapped endpoints.
func _route_fallback_label(group: String, from_name: String, to_name: String) -> String:
	var kind := String(ROUTE_WORDS.get(group, "Route"))
	if from_name != "" and to_name != "":
		return "%s from %s to %s" % [kind, from_name, to_name]
	if from_name != "" or to_name != "":
		return "%s to %s" % [kind, from_name if from_name != "" else to_name]
	return kind


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


## Azgaar (1.151) sometimes writes marker legends containing astral-plane
## glyphs as *unpaired* \\uD800-\\uDFFF escapes, which Godot's JSON parser
## rejects outright ("unpaired trail surrogate") — one bad marker would
## otherwise cost the whole import. Drop the lone halves; keep well-formed
## pairs, which decode normally.
func _drop_lone_surrogates(text: String) -> String:
	var out := ""
	var i := 0
	while true:
		var at := text.find("\\u", i)
		if at < 0:
			out += text.substr(i)
			return out
		out += text.substr(i, at - i)
		var esc := text.substr(at, 6)
		if esc.length() < 6 or not _is_surrogate_escape(esc):
			out += text.substr(at, 2)
			i = at + 2
			continue
		var next := text.substr(at + 6, 6)
		if _is_high_surrogate(esc) and _is_surrogate_escape(next) \
				and not _is_high_surrogate(next):
			out += esc + next
			i = at + 12
		else:
			i = at + 6
	return out


func _is_surrogate_escape(esc: String) -> bool:
	if esc.length() != 6 or not esc.begins_with("\\u"):
		return false
	if not esc.substr(2).is_valid_hex_number():
		return false
	var cp := esc.substr(2).hex_to_int()
	return cp >= 0xD800 and cp <= 0xDFFF


func _is_high_surrogate(esc: String) -> bool:
	if not _is_surrogate_escape(esc):
		return false
	var cp := esc.substr(2).hex_to_int()
	return cp <= 0xDBFF


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


## The outline of a group of cells: every cell edge (undirected vertex pair)
## that belongs to exactly ONE cell of the group lies on its border — whether
## the far side is another group, water, or the map edge. Those edges are
## chained into closed loops (one polyline each; a pinch vertex simply joins
## two loops into one figure-eight, which draws fine). Deterministic: cells
## and edges are visited in JSON order.
##
## `field` is the cell property that names the group — "state" for a kingdom
## outline, "province" for a province one. Provinces tile their kingdom
## exactly (every cell of a state carries a province), so merging a
## kingdom's province loops reproduces its border: that is what lets the
## game redraw a border after a province changes hands.
func _cell_group_loops(cells: Array, vertices: Array, field: String,
		id: int) -> Array[PackedVector2Array]:
	return _cell_set_loops(cells, vertices, func(c: Dictionary) -> bool:
		return int(c.get(field, 0)) == id)


## The outline of every cell `member` accepts — the same edge-count walk as
## _cell_group_loops, over an arbitrary set (all land, one lake's cells).
func _cell_set_loops(cells: Array, vertices: Array,
		member: Callable) -> Array[PackedVector2Array]:
	var edge_count: Dictionary = {}
	var edge_order: Array[Vector2i] = []
	for c: Dictionary in cells:
		if not member.call(c):
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


## A loop as the "x y|x y|..." text the pack tables carry.
func _loop_points(loop: PackedVector2Array) -> String:
	var pts: Array[String] = []
	for p in loop:
		pts.append("%s %s" % [_num2(p.x), _num2(p.y)])
	return "|".join(pts)


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
	var map_id := DEFAULT_MAP_ID
	var user_args := OS.get_cmdline_user_args()
	var i := 0
	while i < user_args.size() - 1:
		if user_args[i] == "--json":
			json_path = user_args[i + 1]
		elif user_args[i] == "--map-id":
			map_id = user_args[i + 1]
		i += 1
	var out_data := DATA + "/maps/" + map_id
	var out_art := MAPS + "/" + map_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_data))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_art))
	_ensure_domains(out_data)
	# Raw exports may sit directly in assets/maps/ or inside the pack's own
	# folder next to the generated art; scan both so a re-import needs no
	# arguments either way.
	var jsons: Array[String] = []
	var dirs: Array[String] = [MAPS]
	for sub in DirAccess.get_directories_at(MAPS):
		dirs.append(MAPS + "/" + sub)
	for dir_path in dirs:
		for file in DirAccess.get_files_at(dir_path):
			var path: String = dir_path + "/" + file
			if file.contains("Full") and file.ends_with(".json"):
				jsons.append(path)
	if json_path == "":
		json_path = _newest(jsons, "Azgaar full export (*Full*.json)")
	if json_path == "":
		return 1
	var world: Variant = JSON.parse_string(
			_drop_lone_surrogates(FileAccess.get_file_as_string(json_path)))
	if world == null:
		push_error("error: cannot parse %s" % json_path)
		return 1
	var info: Dictionary = world["info"]
	var width := int(info["width"])
	var height := int(info["height"])
	print("json: %s" % json_path.get_file())

	var pack: Dictionary = world["pack"]
	var settings: Dictionary = world["settings"]
	var rate := float(settings.get("populationRate", 1000))
	var cells: Array = pack["cells"]
	var vertices: Array = pack["vertices"]
	var states: Array[Dictionary] = []
	for s in _active(pack["states"]):
		if int(s["i"]) != 0:
			states.append(s)
	var provinces := _active(pack["provinces"])
	# State 0 ("Neutrals") is not a kingdom, so neither are the burgs standing
	# on its land — they have no state and no province to belong to. Drop them
	# rather than fail the import; routes ending at one just lose their snap.
	var burgs: Array[Dictionary] = []
	for b in _active(pack["burgs"]):
		if int(b["state"]) == 0:
			print("skipping neutral burg %d (%s)" % [int(b["i"]), String(b["name"])])
			continue
		burgs.append(b)

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
	var prov_biome_area: Dictionary = {}  # pid -> {biome_id: area}
	for c: Dictionary in cells:
		var pid := int(c.get("province", 0))
		if prov_area.has(pid):
			prov_area[pid] += float(c.get("area", 0))
			prov_pop[pid] += float(c.get("pop", 0))
			if not prov_biome_area.has(pid):
				prov_biome_area[pid] = {}
			var by: Dictionary = prov_biome_area[pid]
			var bid := int(c.get("biome", 0))
			by[bid] = float(by.get(bid, 0.0)) + float(c.get("area", 0))
	for b in burgs:  # urban population on top of the cells' rural points
		prov_pop[burg_province[int(b["i"])]] += float(b.get("population", 0))

	# --- codes for cultures, religions, goods -----------------------------
	var culture_code: Dictionary = {}
	var culture_slugs: Dictionary = {}
	for cu in _active(pack.get("cultures", [])):
		culture_code[int(cu["i"])] = _take_slug(culture_slugs, String(cu["name"]))
	var religion_code: Dictionary = {}
	var religion_slugs: Dictionary = {}
	for rl in _active(pack.get("religions", [])):
		religion_code[int(rl["i"])] = _take_slug(religion_slugs, String(rl["name"]))
	var good_code: Dictionary = {}
	var good_slugs: Dictionary = {}
	for g in _active(pack.get("goods", [])):
		good_code[int(g["i"])] = _take_slug(good_slugs, String(g["name"]))
	var options: Dictionary = (world["settings"] as Dictionary).get("options", {})
	var unit_defs: Array = options.get("military", [])
	var unit_names: Array[String] = []
	var unit_power: Dictionary = {}
	for u in unit_defs:
		if u is Dictionary:
			unit_names.append(String(u["name"]))
			unit_power[String(u["name"])] = float(u.get("power", 1))

	# --- political/kingdoms.csv -------------------------------------------
	var out := _csv_line(["kingdom_code", "state_id", "label", "capital_burg",
		"neighbor_codes", "color", "area", "population", "center_x", "center_y",
		"form", "form_name", "full_name", "culture_code", "religion_code"])
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
			_num2(float(center[0])), _num2(float(center[1])),
			String(s.get("form", "")), String(s.get("formName", "")),
			String(s.get("fullName", "")),
			String(culture_code.get(int(s.get("culture", 0)), "")),
			String(religion_code.get(_majority_religion(cells, int(s["i"])), ""))])
	if not _write_text(out_data + "/political/kingdoms.csv", out):
		return 1

	# --- political/provinces.csv ------------------------------------------
	out = _csv_line(["province_code", "label", "kingdom_code", "capital_burg",
		"area", "population", "province_id", "center_x", "center_y",
		"form_name", "full_name", "color", "biome_id"])
	for p in provinces:
		var pcenter: Array = (cells[int(p["center"])] as Dictionary)["p"]
		out += _csv_line([String(prov_code[int(p["i"])]), String(p["name"]),
			String(state_code[int(p["state"])]),
			String(burg_code.get(int(p.get("burg", 0)), "")),
			str(int(prov_area[int(p["i"])])),
			str(int(round(float(prov_pop[int(p["i"])]) * rate))),
			str(int(p["i"])), _num2(float(pcenter[0])), _num2(float(pcenter[1])),
			String(p.get("formName", "")), String(p.get("fullName", "")),
			String(p.get("color", "")), str(_majority_key(prov_biome_area.get(int(p["i"]), {})))])
	if not _write_text(out_data + "/political/provinces.csv", out):
		return 1

	# --- political/burgs.csv ----------------------------------------------
	# Elevation in metres the way Azgaar prints it (height 20+ is land:
	# (h - 18) ^ heightExponent); temperature from the grid cell under the burg.
	var height_exponent := float(settings.get("heightExponent", 2))
	var grid_cells: Array = (world.get("grid", {}) as Dictionary).get("cells", [])
	out = _csv_line(["burg_code", "label", "province_code", "kingdom_code",
		"population", "is_capital", "is_port", "x", "y", "type", "features",
		"group", "culture_code", "elevation_m", "temperature_c"])
	for b in burgs:
		var feats: Array[String] = []
		for flag in ["walls", "citadel", "temple", "plaza", "shanty"]:
			if b.get(flag):
				feats.append(flag)
		var cell: Dictionary = cells[int(b["cell"])]
		var h := float(cell.get("h", 0))
		var elevation := pow(h - 18.0, height_exponent) if h >= 20.0 else 0.0
		var g := int(cell.get("g", -1))
		var temp := 0.0
		if g >= 0 and g < grid_cells.size() and grid_cells[g] is Dictionary:
			temp = float((grid_cells[g] as Dictionary).get("temp", 0))
		out += _csv_line([String(burg_code[int(b["i"])]), String(b["name"]),
			String(prov_code[burg_province[int(b["i"])]]),
			String(state_code[int(b["state"])]),
			str(int(round(float(b.get("population", 0)) * rate))),
			"1" if b.get("capital") else "0", "1" if b.get("port") else "0",
			_num2(float(b["x"])), _num2(float(b["y"])),
			String(b.get("type", "Generic")), "|".join(feats),
			String(b.get("group", "")),
			String(culture_code.get(int(b.get("culture", 0)), "")),
			str(int(round(elevation))), str(int(round(temp)))])
	if not _write_text(out_data + "/political/burgs.csv", out):
		return 1

	# --- political/borders.csv --------------------------------------------
	out = _csv_line(["kingdom_code", "loop", "points"])
	var loop_total := 0
	for s in states:
		var loops := _cell_group_loops(cells, vertices, "state", int(s["i"]))
		for li in loops.size():
			var pts: Array[String] = []
			for p in loops[li]:
				pts.append("%s %s" % [_num2(p.x), _num2(p.y)])
			out += _csv_line([String(state_code[int(s["i"])]), str(li), "|".join(pts)])
		loop_total += loops.size()
	if not _write_text(out_data + "/political/borders.csv", out):
		return 1

	# --- political/province_borders.csv -----------------------------------
	# The kingdom outlines above are the pack's *starting* borders. Ownership
	# moves at province granularity, so the game rebuilds a kingdom's outline
	# from the loops of the provinces it currently holds.
	out = _csv_line(["province_code", "loop", "points"])
	var prov_loop_total := 0
	for p in provinces:
		var loops := _cell_group_loops(cells, vertices, "province", int(p["i"]))
		for li in loops.size():
			var pts: Array[String] = []
			for pt in loops[li]:
				pts.append("%s %s" % [_num2(pt.x), _num2(pt.y)])
			out += _csv_line([String(prov_code[int(p["i"])]), str(li), "|".join(pts)])
		prov_loop_total += loops.size()
	if not _write_text(out_data + "/political/province_borders.csv", out):
		return 1

	# --- political/diplomacy.csv, political/campaigns.csv -----------------
	# Azgaar's diplomacy row is indexed by state id; index 0 (neutrals) and the
	# state's own slot hold "x", and state 0's row is a list of war notes.
	out = _csv_line(["kingdom_code", "other_code", "stance"])
	for s in states:
		var dip: Array = s.get("diplomacy", [])
		for j in dip.size():
			if j == int(s["i"]) or not state_code.has(j) or not (dip[j] is String):
				continue
			out += _csv_line([String(state_code[int(s["i"])]), String(state_code[j]),
				String(dip[j])])
	if not _write_text(out_data + "/political/diplomacy.csv", out):
		return 1
	out = _csv_line(["kingdom_code", "label", "start_year", "end_year", "attacker_code",
		"defender_code"])
	for s in states:
		for cp in (s.get("campaigns", []) as Array):
			if not cp is Dictionary:
				continue
			out += _csv_line([String(state_code[int(s["i"])]), String(cp.get("name", "")),
				str(int(cp.get("start", 0))), str(int(cp.get("end", 0))),
				String(state_code.get(int(cp.get("attacker", 0)), "")),
				String(state_code.get(int(cp.get("defender", 0)), ""))])
	if not _write_text(out_data + "/political/campaigns.csv", out):
		return 1

	# --- economy/* --------------------------------------------------------
	out = _csv_line(["kingdom_code", "treasury", "sales_tax", "poll_tax",
		"urban_population", "rural_population"])
	for s in states:
		out += _csv_line([String(state_code[int(s["i"])]), _num2(float(s.get("treasury", 0))),
			_num2(float(s.get("salesTax", 0))), _num2(float(s.get("pollTax", 0))),
			str(int(round(float(s.get("urban", 0)) * rate))),
			str(int(round(float(s.get("rural", 0)) * rate)))])
	if not _write_text(out_data + "/economy/kingdoms.csv", out):
		return 1
	out = _csv_line(["province_code", "urban_population", "rural_population"])
	for p in provinces:
		out += _csv_line([String(prov_code[int(p["i"])]),
			str(int(round(float(p.get("urban", 0)) * rate))),
			str(int(round(float(p.get("rural", 0)) * rate)))])
	if not _write_text(out_data + "/economy/provinces.csv", out):
		return 1
	out = _csv_line(["burg_code", "treasury", "product", "market_id"])
	var production := _csv_line(["burg_code", "good_code", "units"])
	for b in burgs:
		out += _csv_line([String(burg_code[int(b["i"])]), _num2(float(b.get("treasury", 0))),
			_num2(float(b.get("product", 0))), str(int(b.get("market", 0)))])
		for pe in (b.get("production", []) as Array):
			if pe is Dictionary and pe.has("goodId") and good_code.has(int(pe["goodId"])):
				production += _csv_line([String(burg_code[int(b["i"])]),
					String(good_code[int(pe["goodId"])]), _num2(float(pe.get("units", 0)))])
	if not _write_text(out_data + "/economy/burgs.csv", out):
		return 1
	if not _write_text(out_data + "/economy/production.csv", production):
		return 1
	out = _csv_line(["good_code", "good_id", "label", "value", "tags", "unit"])
	for g in _active(pack.get("goods", [])):
		var tags: Array[String] = []
		for t in (g.get("tags", []) as Array):
			tags.append(String(t))
		out += _csv_line([String(good_code[int(g["i"])]), str(int(g["i"])), String(g["name"]),
			_num2(float(g.get("value", 0))), "|".join(tags), String(g.get("unit", ""))])
	if not _write_text(out_data + "/economy/goods.csv", out):
		return 1
	out = _csv_line(["market_id", "center_burg"])
	var market_goods := _csv_line(["market_id", "good_code", "stock", "price"])
	for mk in _active(pack.get("markets", [])):
		out += _csv_line([str(int(mk["i"])),
			String(burg_code.get(int(mk.get("centerBurgId", 0)), ""))])
		var goods: Dictionary = mk.get("goods", {})
		var gids: Array = []
		for k in goods:
			gids.append(int(k))
		gids.sort()
		for gid in gids:
			if not good_code.has(gid):
				continue
			var entry: Dictionary = goods[str(gid)]
			market_goods += _csv_line([str(int(mk["i"])), String(good_code[gid]),
				_num2(float(entry.get("stock", 0))), _num2(float(entry.get("price", 0)))])
	if not _write_text(out_data + "/economy/markets.csv", out):
		return 1
	if not _write_text(out_data + "/economy/market_goods.csv", market_goods):
		return 1

	# --- military/* -------------------------------------------------------
	out = _csv_line(["unit_code", "label", "type", "rural_rate", "urban_rate", "crew",
		"power", "separate"])
	for u in unit_defs:
		if not u is Dictionary:
			continue
		out += _csv_line([String(u["name"]), String(u["name"]).capitalize(),
			String(u.get("type", "")), _num2(float(u.get("rural", 0))),
			_num2(float(u.get("urban", 0))), str(int(u.get("crew", 1))),
			_num2(float(u.get("power", 1))), "1" if u.get("separate") else "0"])
	if not _write_text(out_data + "/military/unit_types.csv", out):
		return 1
	var reg_header: Array[String] = ["regiment_code", "kingdom_code", "province_code", "label", "x", "y"]
	reg_header.append_array(unit_names)
	reg_header.append("is_naval")
	out = _csv_line(reg_header)
	var king_header: Array[String] = ["kingdom_code"]
	king_header.append_array(unit_names)
	king_header.append_array(["regiments", "strength", "alert", "expansionism"])
	var military := _csv_line(king_header)
	var regiment_slugs: Dictionary = {}
	for s in states:
		var totals: Dictionary = {}
		var regs: Array = s.get("military", [])
		var strength := 0.0
		var reg_count := 0
		for rg in regs:
			if not rg is Dictionary:
				continue
			reg_count += 1
			var units: Dictionary = rg.get("u", {})
			var reg_cell: Dictionary = cells[int(rg.get("cell", 0))]
			var fields: Array[String] = [
				_take_slug(regiment_slugs, "%s %s" % [String(s["name"]), String(rg.get("name", ""))]),
				String(state_code[int(s["i"])]),
				String(prov_code.get(int(reg_cell.get("province", 0)), "")),
				String(rg.get("name", "")),
				_num2(float(rg.get("x", 0))), _num2(float(rg.get("y", 0)))]
			for u in unit_names:
				var n := int(units.get(u, 0))
				fields.append(str(n))
				totals[u] = int(totals.get(u, 0)) + n
				strength += n * float(unit_power.get(u, 1.0))
			fields.append("1" if int(rg.get("n", 0)) == 1 else "0")
			out += _csv_line(fields)
		var kfields: Array[String] = [String(state_code[int(s["i"])])]
		for u in unit_names:
			kfields.append(str(int(totals.get(u, 0))))
		kfields.append_array([str(reg_count), _num2(strength), _num2(float(s.get("alert", 0))),
			_num2(float(s.get("expansionism", 0)))])
		military += _csv_line(kfields)
	if not _write_text(out_data + "/military/regiments.csv", out):
		return 1
	if not _write_text(out_data + "/military/kingdoms.csv", military):
		return 1

	# --- society/* --------------------------------------------------------
	out = _csv_line(["culture_code", "culture_id", "label", "type", "expansionism", "color"])
	for cu in _active(pack.get("cultures", [])):
		out += _csv_line([String(culture_code[int(cu["i"])]), str(int(cu["i"])),
			String(cu["name"]), String(cu.get("type", "")),
			_num2(float(cu.get("expansionism", 0))), String(cu.get("color", ""))])
	if not _write_text(out_data + "/society/cultures.csv", out):
		return 1
	out = _csv_line(["religion_code", "religion_id", "label", "type", "form", "culture_code",
		"deity", "urban_population", "rural_population", "area"])
	for rl in _active(pack.get("religions", [])):
		out += _csv_line([String(religion_code[int(rl["i"])]), str(int(rl["i"])),
			String(rl["name"]), String(rl.get("type", "")), String(rl.get("form", "")),
			String(culture_code.get(int(rl.get("culture", -1)), "")),
			String(rl.get("deity", "")),
			str(int(round(float(rl.get("urban", 0)) * rate))),
			str(int(round(float(rl.get("rural", 0)) * rate))), str(int(rl.get("area", 0)))])
	if not _write_text(out_data + "/society/religions.csv", out):
		return 1
	out = _csv_line(["zone_code", "label", "type", "cells", "center_x", "center_y",
		"province_codes", "kingdom_codes"])
	var zone_slugs: Dictionary = {}
	for z in _active(pack.get("zones", [])):
		var zcells: Array = z.get("cells", [])
		var sx := 0.0
		var sy := 0.0
		var provs: Array[String] = []
		var kings: Array[String] = []
		for ci in zcells:
			var c: Dictionary = cells[int(ci)]
			sx += float((c["p"] as Array)[0])
			sy += float((c["p"] as Array)[1])
			var pc := String(prov_code.get(int(c.get("province", 0)), ""))
			if pc != "" and not provs.has(pc):
				provs.append(pc)
			var kc := String(state_code.get(int(c.get("state", 0)), ""))
			if kc != "" and not kings.has(kc):
				kings.append(kc)
		var n := maxi(zcells.size(), 1)
		out += _csv_line([_take_slug(zone_slugs, String(z.get("name", ""))),
			String(z.get("name", "")), String(z.get("type", "")), str(zcells.size()),
			_num2(sx / n), _num2(sy / n), "|".join(provs), "|".join(kings)])
	if not _write_text(out_data + "/society/zones.csv", out):
		return 1

	# --- geography/routes.csv ---------------------------------------------
	out = _csv_line(["route_code", "label", "group", "from_burg", "to_burg", "length", "points"])
	var route_slugs: Dictionary = {}
	var burg_name: Dictionary = {}
	for b in burgs:
		burg_name[int(b["i"])] = String(b["name"])
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
		if label == "":
			label = _route_fallback_label(String(r.get("group", "")),
				String(burg_name.get(from_id, "")), String(burg_name.get(to_id, "")))
		out += _csv_line([_take_slug(route_slugs, label), label, String(r.get("group", "")),
			String(burg_code.get(from_id, "")), String(burg_code.get(to_id, "")),
			String.num(length, 1), "|".join(pts)])
	if not _write_text(out_data + "/geography/routes.csv", out):
		return 1

	# --- geography/rivers.csv ---------------------------------------------
	out = _csv_line(["river_code", "label", "type", "length", "discharge", "kingdom_codes", "points"])
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
			String.num(length, 1), str(int(rv.get("discharge", 0))), "|".join(through), "|".join(pts)])
		river_count += 1
	if not _write_text(out_data + "/geography/rivers.csv", out):
		return 1

	# --- geography/markers.csv --------------------------------------------
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
	if not _write_text(out_data + "/geography/markers.csv", out):
		return 1
	if unnoted > 0:
		print("WARNING: %d markers have no note; their type stands in as the label" % unnoted)

	# --- geography/biomes.csv ---------------------------------------------
	out = _csv_line(["biome_id", "label", "color", "habitability"])
	for bm in _active(pack.get("biomes", [])):
		out += _csv_line([str(int(bm["i"])), String(bm["name"]), String(bm.get("color", "")),
			str(int(bm.get("habitability", 0)))])
	if not _write_text(out_data + "/geography/biomes.csv", out):
		return 1

	# --- geography/vertices.csv -------------------------------------------
	out = _csv_line(["vertex_id", "x", "y"])
	for v in vertices:
		if not (v is Dictionary):
			continue
		var vp: Array = (v as Dictionary)["p"]
		out += _csv_line([str(int((v as Dictionary)["i"])), _num2(float(vp[0])), _num2(float(vp[1]))])
	if not _write_text(out_data + "/geography/vertices.csv", out):
		return 1

	# --- geography/cells.csv ----------------------------------------------
	# The terrain itself (spec 2026-09-11): MapTerrain fans every cell into a
	# mesh, shades land by its neighbours' heights, and grades the sea by depth.
	var feat_type: Dictionary = {}
	for f in (pack.get("features", []) as Array):
		if f is Dictionary:
			feat_type[int((f as Dictionary).get("i", -1))] = String((f as Dictionary).get("type", ""))
	out = _csv_line(["cell_id", "vertex_ids", "height", "biome_id", "water", "neighbor_ids"])
	for c: Dictionary in cells:
		var h := int(round(float(c.get("h", 0))))
		var water := ""
		if h < SEA_LEVEL:
			water = "lake" if String(feat_type.get(int(c.get("f", 0)), "")) == "lake" else "ocean"
		var vids: Array[String] = []
		for v in (c.get("v", []) as Array):
			vids.append(str(int(v)))
		var nids: Array[String] = []
		for n in (c.get("c", []) as Array):
			nids.append(str(int(n)))
		out += _csv_line([str(int(c["i"])), "|".join(vids), str(h),
			str(int(c.get("biome", 0))), water, "|".join(nids)])
	if not _write_text(out_data + "/geography/cells.csv", out):
		return 1

	# --- geography/coasts.csv ---------------------------------------------
	# Shores as closed loops: the outline of all land (every island, plus an
	# inner loop around any lake inside it) and each lake's own shore.
	out = _csv_line(["kind", "feature_id", "loop", "points"])
	var coast_total := 0
	var land_loops := _cell_set_loops(cells, vertices, func(c: Dictionary) -> bool:
		return float(c.get("h", 0)) >= SEA_LEVEL)
	for li in land_loops.size():
		out += _csv_line(["land", "0", str(li), _loop_points(land_loops[li])])
	coast_total += land_loops.size()
	for f in (pack.get("features", []) as Array):
		if not (f is Dictionary) or String((f as Dictionary).get("type", "")) != "lake":
			continue
		var fid := int((f as Dictionary)["i"])
		var lake_loops := _cell_set_loops(cells, vertices, func(c: Dictionary) -> bool:
			return int(c.get("f", 0)) == fid)
		for li in lake_loops.size():
			out += _csv_line(["lake", str(fid), str(li), _loop_points(lake_loops[li])])
		coast_total += lake_loops.size()
	if not _write_text(out_data + "/geography/coasts.csv", out):
		return 1

	# --- map_info.csv -----------------------------------------------------
	out = _csv_line(["key", "value"])
	out += _csv_line(["width", str(width)])
	out += _csv_line(["height", str(height)])
	out += _csv_line(["distance_unit", String(settings.get("distanceUnit", "km"))])
	out += _csv_line(["distance_scale", _num2(float(settings.get("distanceScale", 1)))])
	out += _csv_line(["population_rate", _num2(rate)])
	if not _write_text(out_data + "/map_info.csv", out):
		return 1

	# --- bitmaps ----------------------------------------------------------
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
	print("map '%s': wrote %d kingdoms, %d provinces, %d burgs, %d border loops (+%d province loops), %d routes, %d rivers, %d markers, %d coast loops into %s, art into %s"
		% [map_id, states.size(), provinces.size(), burgs.size(), loop_total,
			prov_loop_total, routes.size(), river_count, markers.size(), coast_total,
			out_data, out_art])
	return 0
