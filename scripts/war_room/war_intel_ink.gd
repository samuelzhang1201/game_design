class_name WarIntelInk
extends RefCounted
## What we KNOW, inked over the laid sheet (owner 2026-10-02, spec
## 2026-10-02-war-room-v2 §2.4): the crown's regiments' supply roads (fainter
## for what they lose), the crown's couriers on the road and the road ahead,
## this spell's weather by province, and every spy report that has COME IN (a
## missive) as a ring of its estimate. Never a foreign regiment's line, never a
## spy still riding as a report. In ink-texture px like WarSheetInk; drawn into
## its own texture once a day (cache_key).


static func cache_key(state: GameState, sheet_index: int) -> int:
	var couriers: Array = state.couriers.map(func(c: Dictionary) -> Array: return [c["id"], c["x_m"], c["y_m"]])
	return hash([sheet_index, state.absolute_day(), couriers, state.next_missive_id, state.regiments.hash(),
		state.manor_owner.hash(), state.manor_province.hash(), state.hazards_rev, state.hazards.size()])


static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int) -> Dictionary:
	var r: Rect2 = sheet["rect"]
	var k := float(tex_px) / r.size.x
	var out := {"supply": [], "couriers": [], "weather": [], "spies": [], "hazards": []}
	var ours: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).map(
		func(x: Dictionary) -> String: return String(x["regiment_code"]))
	ours.sort()
	for code: String in ours:
		var route := SupplySystem.route_px(repo, state, code)
		if route.size() >= 2 and WarSheetInk._touches(r, route):
			var line := SupplySystem.line_of(repo, state, code)
			(out["supply"] as Array).append({"code": code, "poly": WarSheetInk._to_tex(r, k, route),
				"loss_permille": int(line["loss_permille"])})
	for c: Dictionary in state.couriers:
		var pts := PackedVector2Array([ArmySystem.metres_to_pack(repo, Vector2i(int(c["x_m"]), int(c["y_m"])))])
		for p: Array in c.get("path", []):
			pts.append(ArmySystem.metres_to_pack(repo, Vector2i(int(p[0]), int(p[1]))))
		if WarSheetInk._touches(r, pts):
			(out["couriers"] as Array).append({"poly": WarSheetInk._to_tex(r, k, pts), "at": (pts[0] - r.position) * k,
				"spy": String(c.get("kind", "")) == CourierSystem.SPY})
	var day := state.absolute_day()
	var codes: Array = repo.provinces.keys()
	codes.sort()
	for code: String in codes:
		var row: Dictionary = repo.provinces[code]
		var at := Vector2(float(row.get("center_x", 0)), float(row.get("center_y", 0)))
		if not r.has_point(at):
			continue
		var kind := Weather.of(repo, state, code, day)
		var look: Dictionary = repo.weather_kinds.get(kind, {})
		var rain := float(look.get("rainfall", "0"))
		var snow := float(look.get("snowfall", "0"))
		var overcast := float(look.get("overcast", "0"))
		if rain <= 0.0 and snow <= 0.0 and overcast < 0.5:
			continue   # fair weather is not news
		(out["weather"] as Array).append({"at": (at - r.position) * k, "rain": rain, "snow": snow,
			"overcast": overcast, "label": Weather.label_of(repo, kind)})
	# the known hazards in play (spec 2026-10-07-war-room-p2 §2.4): hatched by kind, outlined, named
	var gap := repo.bal("war_hazard_hatch_km") / WarMarks.km_per_px(repo) * k
	for id: String in Hazards.active_ids(state):
		if not Hazards.known(repo, state, id):
			continue
		var h: Dictionary = state.hazards[id]
		var ink := String(Hazards.kind_of(repo, String(h["kind"])).get("ink", "none"))
		if ink == "none":
			continue
		var polys: Array = []
		var centres: Array[Vector2] = []
		var centre := Vector2.ZERO
		for c in h["cells"]:
			var cell: Dictionary = repo.cells[int(c)]
			var poly := PackedVector2Array()
			for v in (cell["vertex_ids"] as PackedInt32Array):
				poly.append(((repo.vertices[v] as Vector2) - r.position) * k)
			polys.append(poly)
			centres.append((MapTerrain.cell_center(repo, cell) - r.position) * k)
			centre += centres[-1]
		centre /= float(maxi(polys.size(), 1))
		var tex_rect := Rect2(Vector2.ZERO, r.size * k)
		if not polys.any(func(p: PackedVector2Array) -> bool: return Geometry2D.intersect_polygons(p,
				PackedVector2Array([tex_rect.position, Vector2(tex_rect.end.x, 0), tex_rect.end, Vector2(0, tex_rect.end.y)])).size() > 0):
			continue
		var left := Hazards.months_left(state, id)
		(out["hazards"] as Array).append({"ink": ink, "lines": hatch_lines(polys, ink, gap),
			"dots": hatch_dots(polys, ink, gap * repo.bal("war_hazard_dot_ratio")), "edges": outline(polys),
			"at": name_at(centres, centre, tex_rect, repo.bal("war_intel_hazard_label_px")),
			"text": String(h["label"]) + ("" if left < 0 else " · %d mo" % left)})
	var seen: Dictionary = {}
	var spies: Array = state.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "spy")
	spies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) > int(b["id"]))
	for m: Dictionary in spies:
		var subj: Dictionary = m["subject"]
		var at := Vector2(float(subj.get("x", 0)), float(subj.get("y", 0)))
		var key := Vector2i(at.round())
		if seen.has(key) or not r.has_point(at):
			continue
		seen[key] = true   # the newest report about a place stands for it
		var spread := 0.0
		var text := String(m["title"])
		for f: Dictionary in m["facts"]:
			if f.has("lo"):
				spread = float(int(f["hi"]) - int(f["lo"])) / maxf(float(f["hi"]), 1.0)
				text = "%s ≈ %s–%s" % [String(f["label"]), WarRoom.group(int(f["lo"])), WarRoom.group(int(f["hi"]))]
				break
		text += " · " + String(m["column"]).capitalize() + " · " + CourierCard.date_of(int(m["day"]))
		(out["spies"] as Array).append({"at": (at - r.position) * k,
			"radius": repo.bal("war_intel_spy_ring_px") * (1.0 + spread * repo.bal("war_intel_spy_spread_k")), "text": text})
	return out


## Hatch lines through each polygon at the kind's angles: unrest crossed (±45°),
## water level (0°), rock one diagonal (painted dashed), plague none (dots).
static func hatch_lines(polys: Array, ink: String, gap: float) -> Array:
	var angles: Array = {"unrest": [PI * 0.25, -PI * 0.25], "water": [0.0], "rock": [PI * 0.25]}.get(ink, [])
	var out: Array = []
	for poly: PackedVector2Array in polys:
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		var c := box.get_center()
		var reach := box.size.length() * 0.5 + gap
		for a: float in angles:
			var along := Vector2.from_angle(a)
			var across := along.orthogonal()
			var t := -reach
			while t <= reach:
				var line := PackedVector2Array([c + across * t - along * reach, c + across * t + along * reach])
				out.append_array(Geometry2D.intersect_polyline_with_polygon(line, poly))
				t += gap
	return out


## Where a hazard's name goes: on the centre of its cell nearest the middle
## (a hazard in two pieces has its middle in neither), kept on the sheet.
static func name_at(centres: Array[Vector2], middle: Vector2, sheet: Rect2, label_px: float) -> Vector2:
	var at := middle
	var best := INF
	for c: Vector2 in centres:
		if c.distance_squared_to(middle) < best:
			best = c.distance_squared_to(middle)
			at = c
	var room := sheet.grow_individual(-label_px * 4.0, -label_px * 1.5, -label_px * 4.0, -label_px * 1.5)
	return at.clamp(room.position, room.end) if room.has_area() else at


## A plague's dots: a grid inside each polygon, each row half a step over.
static func hatch_dots(polys: Array, ink: String, gap: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ink != "plague":
		return out
	for poly: PackedVector2Array in polys:
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		var y := ceilf(box.position.y / gap) * gap
		while y < box.end.y:
			var shift := gap * 0.5 if posmod(roundi(y / gap), 2) == 1 else 0.0
			var x := ceilf((box.position.x - shift) / gap) * gap + shift
			while x < box.end.x:
				if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
					out.append(Vector2(x, y))
				x += gap
			y += gap
	return out


## The edges no two of the polygons share: the hazard's outline.
static func outline(polys: Array) -> Array:
	var count: Dictionary = {}
	var seg: Dictionary = {}
	for poly: PackedVector2Array in polys:
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var key := [Vector2i((a * 4.0).round()), Vector2i((b * 4.0).round())]
			key.sort()
			count[key] = int(count.get(key, 0)) + 1
			seg[key] = PackedVector2Array([a, b])
	var out: Array = []
	for key in count:
		if int(count[key]) == 1:
			out.append(seg[key])
	return out
