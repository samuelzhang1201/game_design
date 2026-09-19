class_name Map3DHudPiece
extends Control
## One job of the 3D map's HUD (spec 2026-09-20 §1): a full-rect,
## mouse-transparent layer drawn from the context the view hands down —
## never from the Game autoload. It draws nothing until bound.

var ctx: Map3DContext
var view: Map3DView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func bind(p_ctx: Map3DContext, p_view: Map3DView) -> void:
	ctx = p_ctx
	view = p_view
	queue_redraw()


func bound() -> bool:
	return ctx != null and ctx.camera != null


## A sibling piece of the same HUD by name (the landmarks keep clear of the
## counters and the legend), or null.
func sibling(piece_name: String) -> Map3DHudPiece:
	var hud := get_parent() as Map3DHud
	return hud.piece(piece_name) if hud != null else null
