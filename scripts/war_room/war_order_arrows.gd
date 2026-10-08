class_name WarOrderArrows
extends RefCounted
## A march stays the BLUE CRAYON ARROW it was drawn as (owner 2026-10-08,
## spec 2026-10-08-war-room-draw-orders rulings 10, 19): pending on its
## confirm, pencilled as a draft, sealed and riding, marching — until the
## column arrives or the order is struck or cancelled. Never a dashed line.
## Columns sharing one drawn path are ONE arrow: the lead (the most bends
## left) with its head, the others crayon feeders joining it. Pure grouping
## (`group`) and the crayon's parts (`add`); the screen px are the caller's.

const DRAFT := "draft"
const SEALED := "sealed"


## The rows [{code, kind, dest: Vector2, wps: Array}] (pack px) as arrows:
## [{lead, kind, dest, members: [codes, the lead first]}]. Two rows are one
## arrow when they are of one kind, end at one point and the one's bends are
## the tail of the other's (they joined one drawn path: WarOrderSketch.
## route_for); the lead has the most bends, a tie to the lower code.
static func group(rows: Array) -> Array:
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["kind"]) != String(b["kind"]):
			return String(a["kind"]) < String(b["kind"])
		var ka := _end_key(a["dest"])
		var kb := _end_key(b["dest"])
		if ka != kb:
			return ka.x < kb.x if ka.x != kb.x else ka.y < kb.y
		if (a["wps"] as Array).size() != (b["wps"] as Array).size():
			return (a["wps"] as Array).size() > (b["wps"] as Array).size()
		return String(a["code"]) < String(b["code"]))
	var out: Array = []
	var leads: Array = []   # the lead's row of each arrow in `out`
	for r: Dictionary in sorted:
		var joined := false
		for i in out.size():
			var lead: Dictionary = leads[i]
			if String(lead["kind"]) == String(r["kind"]) and _end_key(lead["dest"]) == _end_key(r["dest"]) \
					and _is_tail(r["wps"], lead["wps"]):
				(out[i]["members"] as Array).append(String(r["code"]))
				joined = true
				break
		if not joined:
			leads.append(r)
			out.append({"lead": String(r["code"]), "kind": String(r["kind"]), "dest": r["dest"], "members": [String(r["code"])]})
	return out


## The end as a key: one point to a hundredth of a pack px (both ends come
## from whole metres, so one end is one key).
static func _end_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 100.0), roundi(p.y * 100.0))


## True when `wps` are the last bends of `of` (none: every path ends so).
static func _is_tail(wps: Array, of: Array) -> bool:
	if wps.size() > of.size():
		return false
	var off := of.size() - wps.size()
	for i in wps.size():
		if _end_key(wps[i]) != _end_key(of[off + i]):
			return false
	return true


## One arrow's crayon into `ink` (WarPlanInk's parts): `lines` the members'
## walked curves in the target's px, the lead's first — it is the arrow with
## its head, each other a feeder war_order_feeder_mm wide; `start_cut` px cut
## off each line's start (the plinth's edge: a mark never lies on a standing
## piece); `colour` a plan look colour name; `mm` target px a table mm.
static func add(repo: DataRepository, ink: Dictionary, lines: Array, colour: String, start_cut: float, mm: float) -> void:
	var own := {"crayon": [], "pen": [], "names": []}
	for i in lines.size():
		var ctrl := WarPlanGeometry.cut(PackedVector2Array(lines[i]), start_cut,
			WarPlanGeometry.length(PackedVector2Array(lines[i])))
		if ctrl.size() < 2:
			continue
		var s := {"kind": "arrow" if i == 0 else "feeder", "colour": colour, "dashed": 0, "flip": 0, "name": "",
			"width_mm": repo.bal("war_order_feeder_mm")}
		var k: Dictionary = repo.war_plan_kinds["arrow"] if i == 0 \
			else {"gesture": "path", "pen": false, "head": false, "teeth": false}
		WarPlanInk.add(repo, own, s, k, ctrl, 0.0, mm)
	# ONE crayon outline for the arrow: a feeder's or the head's own rim never
	# shows through the band it joins, nor a paler draft darkens where they overlap
	for poly: PackedVector2Array in union(own["crayon"].map(func(c: Dictionary) -> PackedVector2Array: return c["poly"])):
		ink["crayon"].append({"poly": poly, "colour": colour})


## The union of simple polygons: each overlapping or touching pair merged
## into one outline (a hole is filled), the rest kept as they are. Each is
## grown by `seam` px first so parts that only touch (a band and its head at
## the neck) close up.
static func union(polys: Array, seam := 0.5) -> Array:
	var out: Array = []
	for q: PackedVector2Array in polys:
		var grown: Array = Geometry2D.offset_polygon(q, seam, Geometry2D.JOIN_MITER) if seam > 0.0 else [q]
		if grown.is_empty():
			continue
		var cur: PackedVector2Array = grown[0]
		var i := 0
		while i < out.size():
			var outers: Array = Geometry2D.merge_polygons(out[i], cur).filter(func(m: PackedVector2Array) -> bool:
				return not Geometry2D.is_polygon_clockwise(m))
			if outers.size() == 1:
				cur = outers[0]
				out.remove_at(i)
				i = 0
			else:
				i += 1
		out.append(cur)
	return out


## A column's walked curve (ArmySystem.curve_px from `from_px` through `wps`
## to `to_px`) in the view's screen px, leaving the piece where it is drawn
## (spread clear of its neighbours, mid-push included); empty when a point
## lies behind the camera.
static func screen_line(repo: DataRepository, view: WarRoomView, code: String, from_px: Vector2, wps: Array,
		to_px: Vector2) -> PackedVector2Array:
	var curve := ArmySystem.curve_px(repo, from_px, wps, to_px)
	var out := PackedVector2Array()
	var piece := view.piece_node(code)
	if piece != null and not view.camera().is_position_behind(piece.global_position) and curve.size() > 0:
		curve = curve.slice(1)
		out.append(view.camera().unproject_position(piece.global_position) / view.window_scale())
	for p: Vector2 in curve:
		var at: Variant = view.screen_pos_of_px(p)
		if at == null:
			return PackedVector2Array()
		out.append(at)
	return out
