class_name WarSlopeBars
extends RefCounted
## Where ground too steep for a column lies across a march (owner 2026-10-12,
## item 5): the straight chord from the piece through its waypoints to the tip
## is walked over the march grid (MarchPath.slope_runs) and each run of closed
## dry cells gets ONE barrier bar laid across the travel direction at the run's
## middle, so the table says "no passing here, the column goes round" where the
## crayon bends. Pure, pack px; sizes `war_slope_bar_*`, the colour is the
## palette's `slope_bar`. A fleet has none, nor a pack with no march grid.


## chain: pack-px points, from the piece through its waypoints to the tip.
## [{a, b: the bar's ends, dir: the travel direction (unit), cells: cells in the run}]
static func bars(repo: DataRepository, chain: Array) -> Array:
	var out: Array = []
	var grid := MarchPath.of_pack(repo)
	if grid == null or chain.size() < 2:
		return out
	var half := (repo.bal("war_slope_bar_pad_cells") + 0.5) * float(grid.cell_m)   # metres
	for i in chain.size() - 1:
		var p := ArmySystem.pack_to_metres(repo, chain[i])
		var q := ArmySystem.pack_to_metres(repo, chain[i + 1])
		var d := Vector2(q - p)
		if d.length() < 1.0:
			continue
		d = d.normalized()
		var across := Vector2(-d.y, d.x)
		for run: Array in grid.slope_runs(p, q):
			var c0 := Vector2(grid.centre_m(run[0]))
			var c1 := Vector2(grid.centre_m(run[1]))
			var mid := (c0 + c1) * 0.5
			var n := maxi(absi((run[1] as Vector2i).x - (run[0] as Vector2i).x),
				absi((run[1] as Vector2i).y - (run[0] as Vector2i).y)) + 1
			var a := mid - across * half
			var b := mid + across * half
			out.append({"a": ArmySystem.metres_to_pack(repo, Vector2i(a.round())),
				"b": ArmySystem.metres_to_pack(repo, Vector2i(b.round())), "dir": d, "cells": n})
	return out


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
