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
	var half := (repo.bal("war_slope_bar_pad_cells") + 0.5) * float(grid.cell_m)   # metres
	for run: Array in MarchPath.blocked_runs(repo, pts[0], wps, pts[pts.size() - 1]):
		var entry := Vector2(grid.centre_m(run[0]))
		var d := _dir_at(pts, entry)
		var across := Vector2(-d.y, d.x)
		var mid := entry - d * float(grid.cell_m) * 0.5   # the entry edge
		var a := mid - across * half
		var b := mid + across * half
		var n := maxi(absi((run[1] as Vector2i).x - (run[0] as Vector2i).x),
			absi((run[1] as Vector2i).y - (run[0] as Vector2i).y)) + 1
		out.append({"a": ArmySystem.metres_to_pack(repo, Vector2i(a.round())),
			"b": ArmySystem.metres_to_pack(repo, Vector2i(b.round())), "dir": d, "cells": n})
	return out


## The travel direction (unit) of the chain's chord nearest `at` (metres).
static func _dir_at(pts: Array, at: Vector2) -> Vector2:
	var best := Vector2.RIGHT
	var best_d := INF
	for i in pts.size() - 1:
		var p := Vector2(pts[i] as Vector2i)
		var q := Vector2(pts[i + 1] as Vector2i)
		if p.distance_to(q) < 1.0:
			continue
		var d := at.distance_to(Geometry2D.get_closest_point_to_segment(at, p, q))
		if d < best_d:
			best_d = d
			best = (q - p).normalized()
	return best


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
