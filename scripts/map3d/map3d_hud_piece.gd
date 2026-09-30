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


## A world XZ point on the ground, projected into design px; null behind the camera.
func on_ground(xz: Vector2) -> Variant:
	var p := Vector3(xz.x, ctx.height_at(xz), xz.y)
	if ctx.camera.is_position_behind(p):
		return null
	return ctx.camera.unproject_position(p) / ctx.viewport_px_scale()


## The ground between two world XZ points, sampled every map3d_line_step_m
## (at most MAX_DRAPE_POINTS) and projected, design px — a line that walks the
## ground's rises and falls, as a column does, where a straight chord between
## the two projected ends cut across them (owner 2026-09-30: 实际行进路线也和画的
## 不一致). It stops at the first point behind the camera.
const MAX_DRAPE_POINTS := 400

func draped(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := clampi(int(ceil(a.distance_to(b) / maxf(ctx.repo.bal("map3d_line_step_m"), 1.0))), 1, MAX_DRAPE_POINTS)
	for i in n + 1:
		var p: Variant = on_ground(a.lerp(b, float(i) / float(n)))
		if p == null:
			break
		out.append(p)
	return out
