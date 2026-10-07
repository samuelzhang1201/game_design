class_name WarRoomPicks
extends RefCounted
## The room's left-button picking (spec 2026-10-01-war-room-design §2-3): what
## a click at a screen px asks for — an edge arrow, then the wall chart, then
## (WarRoomPointer) a pennant, a piece. Static answers; the pointer acts on them.


## The sheet a click at `screen_px` asks for: an edge arrow, then the wall
## chart; -1 when it is neither.
static func sheet_target(arrows: Node3D, chart: MeshInstance3D, camera: Camera3D, repo: DataRepository,
		screen_px: Vector2, window_scale: float) -> int:
	var i := WarRoomWall.pick_arrow(arrows, camera, screen_px, window_scale, repo.bal("war_pick_px"))
	if i < 0:
		i = WarRoomWall.pick_chart(chart, camera, repo, screen_px * window_scale)
	return i


## The code of the hit (`{code, rect, depth}`, WarPieces / WarPennants
## screen_hits) whose rect, grown by `radius`, holds `at` — the nearest the
## camera when several do; "" when none.
static func nearest(hits: Array, at: Vector2, radius: float) -> String:
	var best := ""
	var best_depth := INF
	for h: Dictionary in hits:
		if (h["rect"] as Rect2).grow(radius).has_point(at) and float(h["depth"]) < best_depth:
			best_depth = float(h["depth"])
			best = String(h["code"])
	return best
