class_name WarPlanHud
extends Control
## The staff's strokes LIVE on the screen (spec 2026-10-07-war-room-
## annotations-and-planning-pieces §2.5): the one being drawn, one being
## dragged, and a chosen stroke's chalk handles — in screen px, drawn as the
## plan layer draws (WarPlanDraw) until the release paints them into plan_tex.
## Takes no mouse.

var _ink: Dictionary = {}
var _look: Dictionary = {}
var _handles := PackedVector2Array()
var _chalk := Color.WHITE
var _handle_r := 7.0


func show_live(ink: Dictionary, look: Dictionary, handles: PackedVector2Array, chalk: Color, handle_r: float) -> void:
	_ink = ink
	_look = look
	_handles = handles
	_chalk = chalk
	_handle_r = handle_r
	queue_redraw()


func clear_live() -> void:
	if _ink.is_empty() and _handles.is_empty():
		return
	_ink = {}
	_handles = PackedVector2Array()
	queue_redraw()


## True while anything is drawn (tests read it).
func drawing() -> bool:
	return not _ink.is_empty() or not _handles.is_empty()


func _draw() -> void:
	if not _ink.is_empty():
		WarPlanDraw.paint(self, _ink, _look)
	for h in _handles:
		draw_circle(h, _handle_r, Color(_chalk, 0.35))
		draw_arc(h, _handle_r, 0.0, TAU, 20, _chalk, 1.5, true)
