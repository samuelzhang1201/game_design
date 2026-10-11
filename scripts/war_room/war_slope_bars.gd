class_name WarSlopeBars
extends RefCounted
## Where the router goes round ground too steep for a column (owner 2026-10-12,
## item 5): the march's runs of closed dry cells on the legs the router replaces
## by a detour (MarchPath.blocked_runs) each get ONE barrier bar laid across the
## travel direction on the run's ENTRY edge, so the table says "no passing
## here, the column goes round" exactly where the crayon bends. A leg the
## router walks straight (walled in, or clear) has none. Pure, pack px; sizes
## `war_slope_bar_*`, the colour is the palette's `slope_bar`. A fleet has none,
## nor a pack with no march grid.


## chain: pack-px points, from the piece through its waypoints to the tip.
## [{a, b: the bar's ends, dir: the travel direction (unit), cells: cells in the run}]
static func bars(repo: DataRepository, chain: Array) -> Array:
	var out: Array = []
	var grid := MarchPath.of_pack(repo)
	if grid == null or chain.size() < 2:
		return out
	var pts: Array = []
	for p: Vector2 in chain:
		pts.append(ArmySystem.pack_to_metres(repo, p))
	var wps: Array = pts.slice(1, pts.size() - 1)
	var line: Array = [pts[0], pts[pts.size() - 1]]
	if not wps.is_empty():   # the route the column walks: the sampled curve
		line = [pts[0]]
		for leg: Array in MarchRoute.legs(MarchRoute.distinct(pts), int(repo.bal("army_route_sample_m"))):
			line.append_array(leg)
	var half := (repo.bal("war_slope_bar_pad_cells") + 0.5) * float(grid.cell_m)   # metres
	for run: Array in MarchPath.blocked_runs(repo, pts[0], wps, pts[pts.size() - 1]):
		var hit := _entry(line, run[0], float(grid.cell_m))
		var d: Vector2 = hit["dir"]
		var across := Vector2(-d.y, d.x)
		var mid: Vector2 = hit["at"]   # where the route first touches the run's entry cell
		var a := mid - across * half
		var b := mid + across * half
		var n := maxi(absi((run[1] as Vector2i).x - (run[0] as Vector2i).x),
			absi((run[1] as Vector2i).y - (run[0] as Vector2i).y)) + 1
		out.append({"a": ArmySystem.metres_to_pack(repo, Vector2i(a.round())),
			"b": ArmySystem.metres_to_pack(repo, Vector2i(b.round())), "dir": d, "cells": n})
	return out


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
