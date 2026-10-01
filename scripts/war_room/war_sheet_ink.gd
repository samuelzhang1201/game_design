class_name WarSheetInk
extends RefCounted
## What is inked on a laid sheet (owner 2026-10-01, spec 2026-10-01-war-room-design
## §2), in TEXTURE px — tex_px across the sheet's width, its height at the same
## scale — so WarInkPainter only draws. Roads solid, trails dashed, rivers in
## blue ink, the coast, each kingdom's LIVE outline (MapOwnership), the province
## seams, towns by tier with names, peaks with heights. Contours and the grid
## are the shader's, not here.

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


static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int) -> Dictionary:
	var r: Rect2 = sheet["rect"]
	var k := float(tex_px) / r.size.x
	var out := {"roads": [], "trails": [], "rivers": [], "coasts": [], "borders": [], "seams": [],
		"towns": [], "peaks": []}
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
		(out["towns"] as Array).append({"at": (at - r.position) * k, "tier": tier, "label": String(b["label"])})
	for m: Dictionary in Elevation.landmarks(repo):
		if String(m["kind"]) != "high":
			continue
		var at: Vector2 = m["pos"]
		if r.has_point(at):
			(out["peaks"] as Array).append({"at": (at - r.position) * k, "metres": int(m["metres"]), "lod": int(m["lod"])})
	return out


## The line cut into dashes: `on` px drawn, `off` px left, along its whole length.
static func dashed(poly: PackedVector2Array, on: float, off: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if poly.size() < 2:
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
