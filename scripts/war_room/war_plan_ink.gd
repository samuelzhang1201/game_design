class_name WarPlanInk
extends RefCounted
## The staff's strokes (WarPlans) as one sheet's plan layer (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §2.5), in that sheet's
## texture px, every width a table millimetre (`war_plan_*_mm`): CRAYON
## polygons (an axis arrow's band and head, a front's line and teeth) the
## painter fills with the wax tooth, PEN lines (phase lines, objective rings)
## in plain ink, and NAMES. A stroke shows on every sheet its box touches.

const RING_SEGMENTS := 72


static func cache_key(state: GameState, sheet_index: int) -> int:
	return hash([sheet_index, int(state.war_plans.get("rev", 0))])


## {crayon: [{poly, colour}], pen: [{line, colour, width}], names: [{at, text,
## colour, caps, size}]}, `colour` a WarPlans colour name.
static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int, table_w_m: float) -> Dictionary:
	var out := {"crayon": [], "pen": [], "names": []}
	var rect: Rect2 = sheet["rect"]
	var k := float(tex_px) / rect.size.x
	var mm := float(tex_px) / (table_w_m * 1000.0)
	for s: Dictionary in WarPlans.strokes_in(repo, state, rect):
		var kind: Dictionary = repo.war_plan_kinds.get(String(s["kind"]), {})
		if kind.is_empty():
			continue
		var ctrl := PackedVector2Array()
		for p in WarPlans.points_px(repo, s):
			ctrl.append((p - rect.position) * k)
		add(repo, out, s, kind, ctrl, WarPlans.radius_px(repo, s) * k, mm)
	return out


## One stroke's parts into `out`, its control points already in the target's
## px and `mm` px a table millimetre — the same parts the HUD draws live.
static func add(repo: DataRepository, out: Dictionary, s: Dictionary, kind: Dictionary, ctrl: PackedVector2Array,
		r: float, mm: float) -> void:
	var colour := String(s["colour"])
	var dashed := int(s.get("dashed", 0)) != 0
	var name := String(s.get("name", ""))
	var name_px := repo.bal("war_plan_name_mm") * mm
	if String(kind["gesture"]) == "ring":
		if ctrl.is_empty() or r <= 0.0:
			return
		var pen := repo.bal("war_plan_pen_mm") * mm
		for rr: float in [r, maxf(r - pen * 3.0, pen)]:
			var ring := PackedVector2Array()
			for i in RING_SEGMENTS + 1:
				ring.append(ctrl[0] + Vector2.from_angle(TAU * float(i) / RING_SEGMENTS) * rr)
			_pen(repo, out, ring, colour, pen * (1.6 if rr == r else 1.0), dashed, mm)
		if name != "":
			out["names"].append({"at": ctrl[0] + Vector2(0, -r - name_px * 0.35), "text": name, "colour": colour,
				"caps": true, "size": name_px})
		return
	if ctrl.size() < 2:
		return
	var path := WarPlanGeometry.curve(ctrl, maxf(mm, 0.5))
	if bool(kind["pen"]):
		_pen(repo, out, path, colour, repo.bal("war_plan_pen_mm") * mm, true, mm)
		if name != "":
			_end_names(out, path, name, colour, name_px)
		return
	if bool(kind["head"]):
		var a := WarPlanGeometry.arrow(path, repo.bal("war_plan_arrow_tail_mm") * mm, repo.bal("war_plan_arrow_neck_mm") * mm,
			repo.bal("war_plan_arrow_head_mm") * mm, repo.bal("war_plan_arrow_head_w_mm") * mm)
		var neck := WarPlanGeometry.length(path) - repo.bal("war_plan_arrow_head_mm") * mm
		var body := WarPlanGeometry.cut(path, 0.0, maxf(neck, 0.0))
		var w := (repo.bal("war_plan_arrow_tail_mm") + repo.bal("war_plan_arrow_neck_mm")) * 0.5 * mm
		if dashed:
			for d: PackedVector2Array in WarPlanGeometry.dashes(body, repo.bal("war_plan_dash_mm") * mm * 1.6,
					repo.bal("war_plan_gap_mm") * mm * 1.6):
				_band(out, d, w, colour)
		elif Geometry2D.triangulate_polygon(a["band"]).is_empty():
			_band(out, body, w, colour)   # a band crossing itself on a tight turn: an even one instead
		else:
			out["crayon"].append({"poly": a["band"], "colour": colour})
		out["crayon"].append({"poly": a["head"], "colour": colour})
		return
	var width := repo.bal("war_plan_front_mm") * mm
	var runs: Array = WarPlanGeometry.dashes(path, repo.bal("war_plan_dash_mm") * mm, repo.bal("war_plan_gap_mm") * mm) \
		if dashed else [path]
	for run: PackedVector2Array in runs:
		_band(out, run, width, colour)
	if bool(kind["teeth"]):
		var side := -1 if int(s.get("flip", 0)) != 0 else 1
		for t: PackedVector2Array in WarPlanGeometry.teeth(path, repo.bal("war_plan_tooth_every_mm") * mm,
				repo.bal("war_plan_tooth_base_mm") * mm, repo.bal("war_plan_tooth_h_mm") * mm + width * 0.5, side):
			out["crayon"].append({"poly": t, "colour": colour})
	if name != "":
		_end_names(out, path, name, colour, name_px)


## A crayon line of even width as simple polygons (Clipper's offset: a tight
## turn never crosses itself, which a polygon fill would refuse).
static func _band(out: Dictionary, line: PackedVector2Array, width: float, colour: String) -> void:
	if line.size() < 2:
		return
	var polys := Geometry2D.offset_polyline(line, width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	for poly: PackedVector2Array in polys:
		if polys.size() == 1 or not Geometry2D.is_polygon_clockwise(poly):   # a hole (clockwise) is left unfilled
			out["crayon"].append({"poly": poly, "colour": colour})


static func _pen(repo: DataRepository, out: Dictionary, line: PackedVector2Array, colour: String, width: float,
		dashed: bool, mm: float) -> void:
	if not dashed:
		out["pen"].append({"line": line, "colour": colour, "width": width})
		return
	for d: PackedVector2Array in WarPlanGeometry.dashes(line, repo.bal("war_plan_dash_mm") * mm, repo.bal("war_plan_gap_mm") * mm):
		out["pen"].append({"line": d, "colour": colour, "width": width})


## A line's name at both its ends, a little beyond each, upright.
static func _end_names(out: Dictionary, path: PackedVector2Array, name: String, colour: String, size: float) -> void:
	var n := path.size()
	for end: Array in [[path[0], path[0] - path[mini(1, n - 1)]], [path[n - 1], path[n - 1] - path[maxi(n - 2, 0)]]]:
		var dir: Vector2 = (end[1] as Vector2).normalized()
		out["names"].append({"at": (end[0] as Vector2) + dir * size * 0.9, "text": name, "colour": colour,
			"caps": false, "size": size, "centred": true})
