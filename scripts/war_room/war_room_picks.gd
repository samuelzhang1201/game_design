class_name WarRoomPicks
extends RefCounted
## The room's left-button picking (spec 2026-10-01-war-room-design §2-3): a
## press that has not moved by war_rake_min_px when released is a CLICK (a
## longer drag is the rake's), and a click asks for an edge arrow, then the
## wall chart, then a piece. Pure bookkeeping; the view acts on the answer.

var _press_at := Vector2.ZERO
var _pressed := false


## True when `mb` is the release of a click (a press that stayed put).
func released_click(mb: InputEventMouseButton, min_drag_px: float) -> bool:
	if mb.pressed:
		_press_at = mb.position
		_pressed = true
		return false
	var was := _pressed
	_pressed = false
	return was and mb.position.distance_to(_press_at) < min_drag_px


## The sheet a click at `screen_px` asks for: an edge arrow, then the wall
## chart; -1 when it is neither.
static func sheet_target(arrows: Node3D, chart: MeshInstance3D, camera: Camera3D, repo: DataRepository,
		screen_px: Vector2, window_scale: float) -> int:
	var i := WarRoomWall.pick_arrow(arrows, camera, screen_px, window_scale, repo.bal("war_pick_px"))
	if i < 0:
		i = WarRoomWall.pick_chart(chart, camera, repo, screen_px * window_scale)
	return i
