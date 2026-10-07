class_name WarHoverDwell
extends RefCounted
## The pointer's dwell on the WAR ROOM's table (spec
## 2026-10-07-war-room-scale-hover §4.2): resting `delay_s` within `still_px`
## completes once; a move past the radius clears what was showing. Pure.

var at := Vector2(-1, -1)
var _still_s := 0.0
var _shown := false


## The pointer is at `p`; true when this clears a completed dwell.
func moved(p: Vector2, still_px: float) -> bool:
	if at.x >= 0.0 and p.distance_to(at) <= still_px:
		return false
	at = p
	_still_s = 0.0
	var was := _shown
	_shown = false
	return was


## Time passes; true on the frame the dwell completes.
func step(delta: float, delay_s: float) -> bool:
	if at.x < 0.0 or _shown:
		return false
	_still_s += delta
	if _still_s >= delay_s:
		_shown = true
		return true
	return false


## Forget the pointer (it left, or the room is busy); true when this clears a
## completed dwell.
func clear() -> bool:
	at = Vector2(-1, -1)
	_still_s = 0.0
	var was := _shown
	_shown = false
	return was
