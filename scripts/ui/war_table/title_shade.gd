@tool
class_name TitleShade
extends Control
## THE LIVING REALM's reading shade (owner 2026-10-11: the hero look): three
## layers of the shade over the live map so the words read — a fall from the
## left edge across the screen, a fall from the foot up, and a deep corner
## under the words at the bottom left. Each fall is a ramp of alphas at six
## evenly spaced stops. Its look is edited on the node
## (scenes/screens/main_menu.tscn's Shade).

## The shade's colour (warm umber, near black).
@export var tint := Color(0.035, 0.025, 0.018):
	set(v):
		tint = v
		queue_redraw()
## Alphas left to right at 0, 20, 40, 60, 80 and 100% of the width.
@export var across := PackedFloat32Array([0.533, 0.445, 0.33, 0.16, 0.03, 0.05]):
	set(v):
		across = v
		queue_redraw()
## Alphas top to bottom at the same six stops of the height.
@export var down := PackedFloat32Array([0.06, 0.023, 0.152, 0.3, 0.394, 0.632]):
	set(v):
		down = v
		queue_redraw()
## The bottom-left corner: an ellipse from the corner, its radii a share of
## the width and the height, the shade at the corner fading to none at its rim.
@export var corner_reach := Vector2(0.938, 0.413):
	set(v):
		corner_reach = v
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var corner := 1.0:
	set(v):
		corner = v
		queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	_ramp(across, true)
	_ramp(down, false)
	_corner()


## One fall: a quad between each pair of stops, the alphas at its two ends.
func _ramp(stops: PackedFloat32Array, horizontal: bool) -> void:
	if stops.size() < 2:
		return
	var w := size.x
	var h := size.y
	var last := stops.size() - 1
	for i in last:
		var a := Color(tint, stops[i])
		var b := Color(tint, stops[i + 1])
		var t0 := float(i) / last
		var t1 := float(i + 1) / last
		if horizontal:
			draw_polygon(PackedVector2Array([Vector2(w * t0, 0), Vector2(w * t1, 0), Vector2(w * t1, h), Vector2(w * t0, h)]),
				PackedColorArray([a, b, b, a]))
		else:
			draw_polygon(PackedVector2Array([Vector2(0, h * t0), Vector2(w, h * t0), Vector2(w, h * t1), Vector2(0, h * t1)]),
				PackedColorArray([a, a, b, b]))


## The corner's quarter ellipse as a fan from the bottom-left corner.
func _corner() -> void:
	if corner <= 0.0:
		return
	var o := Vector2(0, size.y)
	var r := Vector2(size.x * corner_reach.x, size.y * corner_reach.y)
	var dark := Color(tint, corner)
	var clear := Color(tint, 0.0)
	var steps := 32
	for i in steps:
		var a0 := -PI * 0.5 * float(i) / steps
		var a1 := -PI * 0.5 * float(i + 1) / steps
		draw_polygon(PackedVector2Array([o, o + Vector2(cos(a0), sin(a0)) * r, o + Vector2(cos(a1), sin(a1)) * r]),
			PackedColorArray([dark, clear, clear]))
