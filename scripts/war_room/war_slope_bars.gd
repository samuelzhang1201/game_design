class_name WarSlopeBars
extends RefCounted
## Where the router goes round ground too steep for a column (owner 2026-10-12,
## item 5): the march's runs of closed dry cells on the legs the router replaces
## by a detour (MarchPath.blocked_runs) each get ONE barrier bar laid across the
## crayon where it turns off to go round the run's ENTRY, so the table says "no
## passing here, the column goes round" exactly where the crayon bends. A leg the
## router walks straight (walled in, or clear) has none. Pure, pack px; sizes
## `war_slope_bar_*`, the colour is the palette's `slope_bar`. A fleet has none,
## nor a pack with no march grid.


## chain: pack-px points, from the regiment's TRUE spot through its waypoints
## to the tip — which cells are blocked stays the router's truth. Each bar is
## laid across the CRAYON the player sees (R19): the route the column walks
## (ArmySystem.curve_px, as WarOrderArrows.screen_line draws it), starting from
## `shown`, the piece's DISPLAYED spot (WarPieces spreads a camp's pieces
## apart; Vector2(-1, -1), the default, = the true spot), at the place it meets
## the run — where it goes round, its nearest pass, the bend.
## [{a, b: the bar's ends, dir: the travel direction (unit), cells: cells in the run}]
static func bars(repo: DataRepository, chain: Array, shown := Vector2(-1, -1)) -> Array:
	var out: Array = []
	var grid := MarchPath.of_pack(repo)
	if grid == null or chain.size() < 2:
		return out
	var pts: Array = []
	for p: Vector2 in chain:
		pts.append(ArmySystem.pack_to_metres(repo, p))
	var wps: Array = pts.slice(1, pts.size() - 1)
	var line: Array = []
	for p: Vector2 in ArmySystem.curve_px(repo, chain[0], chain.slice(1, chain.size() - 1), chain[chain.size() - 1]):
		line.append(ArmySystem.pack_to_metres(repo, p))
	if shown.x >= 0.0:
		line[0] = ArmySystem.pack_to_metres(repo, shown)
	var meant: Array = [pts[0], pts[pts.size() - 1]]   # the line the router cuts into runs
	if not wps.is_empty():
		meant = [pts[0]]
		for leg: Array in MarchRoute.legs(MarchRoute.distinct(pts), int(repo.bal("army_route_sample_m"))):
			meant.append_array(leg)
	var half := (repo.bal("war_slope_bar_pad_cells") + 0.5) * float(grid.cell_m)   # metres
	for run: Array in MarchPath.blocked_runs(repo, pts[0], wps, pts[pts.size() - 1]):
		var hit := _meet(line, meant, run, float(grid.cell_m))
		var d: Vector2 = hit["dir"]
		var across := Vector2(-d.y, d.x)
		var mid: Vector2 = hit["at"]   # on the crayon, by the run's entry
		var a := mid - across * half
		var b := mid + across * half
		var n := maxi(absi((run[1] as Vector2i).x - (run[0] as Vector2i).x),
			absi((run[1] as Vector2i).y - (run[0] as Vector2i).y)) + 1
		out.append({"a": ArmySystem.metres_to_pack(repo, Vector2i(a.round())),
			"b": ArmySystem.metres_to_pack(repo, Vector2i(b.round())), "dir": d, "cells": n})
	return out


## Where the crayon meets a run [entry cell, exit cell] (metres): where it
## touches the entry cell, else (it goes round) its point nearest the place the
## meant line (`meant`, from the true spot) enters the run. {at, dir}.
static func _meet(crayon: Array, meant: Array, run: Array, cell_m: float) -> Dictionary:
	var c0: Vector2i = run[0]
	var lo := Vector2(c0) * cell_m
	var hit := _touch(crayon, lo, lo + Vector2(cell_m, cell_m))
	if not hit.is_empty():
		return hit
	var anchor: Vector2 = _entry(meant, c0, cell_m)["at"]
	var best := {}
	var best_d := INF
	for i in crayon.size() - 1:
		var p := Vector2(crayon[i] as Vector2i)
		var q := Vector2(crayon[i + 1] as Vector2i)
		if p.distance_to(q) < 1.0:
			continue
		var at := Geometry2D.get_closest_point_to_segment(anchor, p, q)
		if at.distance_to(anchor) < best_d - 0.001:
			best_d = at.distance_to(anchor)
			best = {"at": at, "dir": (q - p).normalized()}
	return best if not best.is_empty() else _entry(crayon, c0, cell_m)


## Where the line first touches the box lo..hi (metres): {at, dir}, {} when never.
static func _touch(line: Array, lo: Vector2, hi: Vector2) -> Dictionary:
	for i in line.size() - 1:
		var p := Vector2(line[i] as Vector2i)
		var q := Vector2(line[i + 1] as Vector2i)
		if p.distance_to(q) < 1.0:
			continue
		var t := _clip(p, q - p, lo, hi)
		if t >= 0.0:
			return {"at": p + (q - p) * t, "dir": (q - p).normalized()}
	return {}


## Where the sampled route line first touches `cell`'s box (a corner touch
## counts), clipped to the box: {at: the entry point, dir: that segment's unit
## direction} in metres. Falls back to the cell's centre and the first chord.
static func _entry(line: Array, cell: Vector2i, cell_m: float) -> Dictionary:
	var lo := Vector2(cell) * cell_m
	var hi := lo + Vector2(cell_m, cell_m)
	var first := Vector2.RIGHT
	for i in line.size() - 1:
		var p := Vector2(line[i] as Vector2i)
		var q := Vector2(line[i + 1] as Vector2i)
		if p.distance_to(q) < 1.0:
			continue
		if i == 0:
			first = (q - p).normalized()
		var t := _clip(p, q - p, lo, hi)
		if t >= 0.0:
			return {"at": p + (q - p) * t, "dir": (q - p).normalized()}
	return {"at": (lo + hi) * 0.5, "dir": first}


## Liang-Barsky: the parameter t (0..1) where p + t * d first enters the closed
## box lo..hi, or -1.0 when the segment never touches it.
static func _clip(p: Vector2, d: Vector2, lo: Vector2, hi: Vector2) -> float:
	var t0 := 0.0
	var t1 := 1.0
	var ps := [-d.x, d.x, -d.y, d.y]
	var qs := [p.x - lo.x, hi.x - p.x, p.y - lo.y, hi.y - p.y]
	for k in 4:
		if is_zero_approx(ps[k]):
			if qs[k] < 0.0:
				return -1.0
		else:
			var r: float = qs[k] / ps[k]
			if ps[k] < 0.0:
				t0 = maxf(t0, r)
			else:
				t1 = minf(t1, r)
	if t0 > t1 + 1e-9:
		return -1.0
	return t0


## A bar's ends on the screen held to at least `min_px` long, grown about its
## middle (a far, small bar must still be seen).
static func at_least(a: Vector2, b: Vector2, min_px: float) -> Array:
	var span := a.distance_to(b)
	if span >= min_px or span < 0.001:
		return [a, b]
	var mid := (a + b) * 0.5
	var along := (b - a) / span
	return [mid - along * min_px * 0.5, mid + along * min_px * 0.5]


## The hatch ticks of one bar on the screen: short strokes leaning away from the
## travel direction along the bar, `gap` px apart, `length` px long.
## a, b, dir in screen px; [[from, to], ...]. The ticks stand on the far side
## of the bar (the side the column would climb toward), like a scarp's hachures.
static func hatches(a: Vector2, b: Vector2, dir: Vector2, gap: float, length: float) -> Array:
	var out: Array = []
	var span := a.distance_to(b)
	if span < 1.0 or gap <= 0.0:
		return out
	var along := (b - a) / span
	var n := int(floor(span / gap))
	for i in n + 1:
		var at := a + along * (minf(float(i) * gap, span))
		out.append([at, at + dir.normalized() * length])
	return out


## A bar's screen ends kept off `keep_off` (screen Rect2s: standing pieces,
## towns' names): the whole bar moved along the travel direction `dir` (unit),
## ahead or back, the nearest spot first, `step` px at a time and at most
## `reach` px (about the steep run's length); when no spot clears it whole, the
## longest stretch that touches none of them, nearest spot first, kept when at
## least `min_len` px. [] when nothing is kept (the bar is then not drawn). R19.
static func clear_of(a: Vector2, b: Vector2, dir: Vector2, keep_off: Array, reach: float, step: float,
		min_len := INF) -> Array:
	var shifts: Array = [0.0]
	if step > 0.0:
		var s := step
		while s <= reach + 0.001:
			shifts.append(s)
			shifts.append(-s)
			s += step
	for need: float in [a.distance_to(b), minf(min_len, a.distance_to(b))]:
		var kept := _kept(a, b, dir, keep_off, shifts, need)
		if not kept.is_empty():
			return kept
	return []


## The first of `shifts` at which a stretch of the moved bar at least `need`
## px long touches none of `keep_off`: [its ends], [] when none.
static func _kept(a: Vector2, b: Vector2, dir: Vector2, keep_off: Array, shifts: Array, need: float) -> Array:
	for shift: float in shifts:
		var a2 := a + dir * shift
		var b2 := b + dir * shift
		var gaps: Array = [Vector2(0.0, 1.0)]   # the clear stretches, as t along a2 -> b2
		for r: Rect2 in keep_off:
			var cut := _span(a2, b2 - a2, r.position, r.end)
			if cut.x < 0.0:
				continue
			var next: Array = []
			for g: Vector2 in gaps:
				if cut.y <= g.x or cut.x >= g.y:
					next.append(g)
					continue
				if cut.x > g.x:
					next.append(Vector2(g.x, cut.x))
				if cut.y < g.y:
					next.append(Vector2(cut.y, g.y))
			gaps = next
		var best := Vector2(-1.0, -1.0)
		for g: Vector2 in gaps:
			if g.y - g.x > best.y - best.x:
				best = g
		if best.x >= 0.0 and (best.y - best.x) * a2.distance_to(b2) >= need - 0.001:
			return [a2.lerp(b2, best.x), a2.lerp(b2, best.y)]
	return []


## Liang-Barsky both ways: Vector2(t in, t out) of p + t * d (0..1) through the
## closed box lo..hi, Vector2(-1, -1) when the segment never touches it.
static func _span(p: Vector2, d: Vector2, lo: Vector2, hi: Vector2) -> Vector2:
	var t0 := 0.0
	var t1 := 1.0
	var ps := [-d.x, d.x, -d.y, d.y]
	var qs := [p.x - lo.x, hi.x - p.x, p.y - lo.y, hi.y - p.y]
	for k in 4:
		if is_zero_approx(ps[k]):
			if qs[k] < 0.0:
				return Vector2(-1.0, -1.0)
		else:
			var r: float = qs[k] / ps[k]
			if ps[k] < 0.0:
				t0 = maxf(t0, r)
			else:
				t1 = minf(t1, r)
	if t0 > t1 + 1e-9:
		return Vector2(-1.0, -1.0)
	return Vector2(t0, t1)


## The name boxes (ring, name, marks; WarSheetInk's layout) of every town on
## `sheet` whose name could reach into `around`, pack px: what a bar must keep
## off (the seat's town and any other name by the march's start). R19.
static func town_boxes(repo: DataRepository, sheet: Dictionary, around: Rect2) -> Array:
	var out: Array = []
	if sheet.is_empty():
		return out
	var r: Rect2 = sheet["rect"]
	var k := float(WarRoomInk.tex_size(repo, r).x) / r.size.x   # ink px per pack px
	# a name runs a dozen letters past its ring (WarSheetInk.strokes' window)
	var reach := around.grow(repo.bal("war_ink_label_px") * 16.0 * repo.bal("war_ink_char_w") / k)
	var name_tier := int(repo.bal("war_union_label_min_tier")) \
		if int(sheet.get("cols", 1)) * int(sheet.get("rows", 1)) > 1 else 0
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var at := Vector2(float(b["x"]), float(b["y"]))
		if not reach.has_point(at) or not r.has_point(at):
			continue
		var tier := 3 if String(b.get("is_capital", "0")) == "1" else int(WarSheetInk.TOWN_TIERS.get(String(b.get("group", "")), 0))
		var t := {"at": (at - r.position) * k, "tier": tier, "label": String(b["label"]) if tier >= name_tier else "",
			"name_dx": WarSheetInk.name_dx(repo, tier, 1.0, sheet), "walls": String(b.get("features", "")).split("|").has("walls")}
		t.merge(WarSheetInk.town_marks(repo, code))
		var box := WarSheetInk.town_label_box(repo, t)
		out.append(Rect2(box.position / k + r.position, box.size / k))
	return out
