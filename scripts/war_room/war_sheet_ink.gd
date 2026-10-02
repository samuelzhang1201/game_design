class_name WarSheetInk
extends RefCounted
## What is inked on a laid sheet (owner 2026-10-01, spec 2026-10-01-war-room-design
## §2), in TEXTURE px — tex_px across the sheet's width, its height at the same
## scale — so WarInkPainter only draws. Roads solid, trails dashed, rivers in
## blue ink, the coast, each kingdom's LIVE outline (MapOwnership), the province
## seams, towns by tier with names, peaks with heights; since v2 B (spec
## 2026-10-02-war-room-v2 §2.4) hollows, woods from the build's canopy
## (WarBake), the manors' own edges and names, walled towns and ports.
## Contours and the grid are the shader's, not here.

## A burg's `group` column to its tier (capital 3, city 2, town / fort 1, village 0).
const TOWN_TIERS := {"village": 0, "town": 1, "fort": 1, "city": 2, "capital": 3}


static func cache_key(state: GameState, sheet_index: int) -> int:
	return hash([sheet_index, state.province_owner.hash(), state.manor_province.hash()])


static func _to_tex(r: Rect2, k: float, poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = (poly[i] - r.position) * k
	return out


static func _touches(r: Rect2, poly: PackedVector2Array) -> bool:
	for p in poly:
		if r.has_point(p):
			return true
	return false


static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int, bake: WarBake = null) -> Dictionary:
	var r: Rect2 = sheet["rect"]
	var k := float(tex_px) / r.size.x
	var out := {"roads": [], "trails": [], "rivers": [], "coasts": [], "borders": [], "seams": [],
		"towns": [], "peaks": [], "hollows": [], "woods": [], "manor_edges": [], "manors": []}
	var route_codes: Array = repo.routes.keys()
	route_codes.sort()
	for code: String in route_codes:
		var row: Dictionary = repo.routes[code]
		var group := String(row.get("group", ""))
		if group != "roads" and group != "trails":
			continue
		var poly: PackedVector2Array = row["polyline"]
		if _touches(r, poly):
			(out[group] as Array).append(_to_tex(r, k, poly))
	var river_codes: Array = repo.rivers.keys()
	river_codes.sort()
	for code: String in river_codes:
		var poly: PackedVector2Array = repo.rivers[code]["polyline"]
		if _touches(r, poly):
			(out["rivers"] as Array).append(_to_tex(r, k, poly))
	for row: Dictionary in repo.coasts:
		var poly: PackedVector2Array = row["polyline"]
		if _touches(r, poly):
			(out["coasts"] as Array).append(_to_tex(r, k, poly))
	var kingdoms: Array = repo.kingdoms.keys()
	kingdoms.sort()
	for kd: String in kingdoms:
		var loops: Array = []
		for loop: PackedVector2Array in MapOwnership.outline_of(repo, state, kd):
			if _touches(r, loop):
				loops.append(_to_tex(r, k, loop))
		if not loops.is_empty():
			(out["borders"] as Array).append({"kingdom": kd, "color": MapPalette.color_of(repo, kd), "loops": loops})
		for seam: PackedVector2Array in MapOwnership.seams_of(repo, state, kd):
			if _touches(r, seam):
				(out["seams"] as Array).append(_to_tex(r, k, seam))
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var at := Vector2(float(b["x"]), float(b["y"]))
		if not r.has_point(at):
			continue
		var tier := 3 if String(b.get("is_capital", "0")) == "1" else int(TOWN_TIERS.get(String(b.get("group", "")), 0))
		(out["towns"] as Array).append({"at": (at - r.position) * k, "tier": tier, "label": String(b["label"]),
			"walls": String(b.get("features", "")).split("|").has("walls"), "port": String(b.get("is_port", "0")) == "1"})
	for m: Dictionary in Elevation.landmarks(repo):
		if String(m["kind"]) != "high":
			continue
		var at: Vector2 = m["pos"]
		if r.has_point(at):
			(out["peaks"] as Array).append({"at": (at - r.position) * k, "metres": int(m["metres"]), "lod": int(m["lod"])})
	for m: Dictionary in Elevation.landmarks(repo):
		if String(m["kind"]) == "low" and r.has_point(m["pos"]):
			(out["hollows"] as Array).append({"at": ((m["pos"] as Vector2) - r.position) * k,
				"metres": int(m["metres"]), "lod": int(m["lod"])})
	if bake != null:
		var step := repo.bal("war_ink_wood_step_km") * WarSheets.px_per_unit(repo)
		var min_cover := repo.bal("war_ink_wood_min_cover")
		for w: Dictionary in bake.woods(r, step):
			var at: Vector2 = w["at"]
			# a glyph where the canopy is thick enough, chosen by a fixed hash so
			# a sheet always draws the same woods
			var roll := float(absi(hash(Vector2i(roundi(at.x * 100.0), roundi(at.y * 100.0)))) % 1000) / 1000.0
			if float(w["cover"]) >= min_cover and roll < float(w["cover"]):
				var jitter := Vector2(float(absi(hash([at.x, 1])) % 100) - 50.0, float(absi(hash([at.y, 2])) % 100) - 50.0) / 100.0 * step
				(out["woods"] as Array).append({"at": (at + jitter - r.position) * k, "conifer": float(w["conifer"]) > 0.5})
	_manors(repo, state, r, k, out)
	return out


## The manors' own edges — a cell edge between two land cells of ONE province
## (a province seam or the coast is drawn already) — and each manor's name at
## its centre unless a town stands within war_ink_manor_clear_px of it.
static func _manors(repo: DataRepository, state: GameState, r: Rect2, k: float, out: Dictionary) -> void:
	var first: Dictionary = {}   # edge key -> the cell that met it first
	var ids: Array = repo.cells.keys()
	ids.sort()
	var clear := repo.bal("war_ink_manor_clear_px")
	var reach := r.grow(r.size.x * 0.05)
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell):
			continue
		var vids: PackedInt32Array = cell["vertex_ids"]
		if vids.size() < 3:
			continue
		var centre := MapTerrain.cell_center(repo, cell)
		if not reach.has_point(centre):
			continue
		var prov := MapManors.province_of(repo, id, state)
		for i in vids.size():
			var a := vids[i]
			var b := vids[(i + 1) % vids.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if first.has(key):
				if MapManors.province_of(repo, int(first[key]), state) == prov:
					(out["manor_edges"] as Array).append(PackedVector2Array([
						((repo.vertices[a] as Vector2) - r.position) * k, ((repo.vertices[b] as Vector2) - r.position) * k]))
			else:
				first[key] = id
		if r.has_point(centre):
			var at := (centre - r.position) * k
			var near_town := false
			for t: Dictionary in out["towns"]:
				if (t["at"] as Vector2).distance_to(at) < clear:
					near_town = true
					break
			if not near_town:
				(out["manors"] as Array).append({"at": at, "label": MapManors.label_of(repo, id)})


## The line cut into dashes: `on` px drawn, `off` px left, along its whole
## length. A dash or gap of no length cannot cut it: the whole line is one dash.
static func dashed(poly: PackedVector2Array, on: float, off: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if poly.size() < 2:
		return out
	if on <= 0.0 or off <= 0.0:
		out.append(poly.duplicate())
		return out
	var drawing := true
	var left := on
	var cur := PackedVector2Array([poly[0]])
	for i in range(1, poly.size()):
		var a := poly[i - 1]
		var b := poly[i]
		var seg := a.distance_to(b)
		var pos := 0.0
		while seg - pos > left:
			pos += left
			var p := a.lerp(b, pos / seg)
			if drawing:
				cur.append(p)
				out.append(cur)
				cur = PackedVector2Array()
			else:
				cur = PackedVector2Array([p])
			drawing = not drawing
			left = on if drawing else off
		left -= seg - pos
		if drawing:
			cur.append(b)
	if drawing and cur.size() >= 2:
		out.append(cur)
	return out
