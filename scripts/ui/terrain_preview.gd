class_name TerrainPreview
extends Control
## The card's map window: the terrain mesh and the shores, scaled so
## `span` native px cover the rect (cover fit, like the old atlas) and
## centred on the place. Reads Game.data only.

var mesh: ArrayMesh
var span: Vector2 = MapDetailPanel.PREVIEW_SPAN
var _center := Vector2.ZERO

func _init() -> void:
	# a scene's properties are set before its script: fill only defaults
	if not clip_contents:
		clip_contents = true
	if mouse_filter == Control.MOUSE_FILTER_STOP:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_place(center: Vector2) -> void:
	mesh = MapTerrain.shared_mesh(Game.data)
	_center = center
	visible = mesh != null
	queue_redraw()

func _draw() -> void:
	if mesh == null:
		return
	var k := maxf(size.x / span.x, size.y / span.y)
	var origin := size / 2.0 - _center * k
	draw_rect(Rect2(Vector2.ZERO, size),
		MapTerrain.palette_color(Game.data, "sea_deep", MapTerrain.FALLBACK))
	draw_mesh(mesh, null, Transform2D(0.0, Vector2(k, k), 0.0, origin))
	var coast := MapTerrain.palette_color(Game.data, "coast_line", MapTerrain.FALLBACK)
	var coast_width: float = Game.data.bal("map_coast_width")
	var frame := Rect2(Vector2.ZERO, size).grow(4.0)
	for row: Dictionary in Game.data.coasts:
		var b: Rect2 = row["bbox"]
		if not frame.intersects(Rect2(origin + b.position * k, b.size * k)):
			continue
		var loop: PackedVector2Array = row["polyline"]
		var pts := PackedVector2Array()
		pts.resize(loop.size() + 1)
		for i in loop.size():
			pts[i] = origin + loop[i] * k
		pts[loop.size()] = pts[0]
		draw_polyline(pts, coast, coast_width, true)
