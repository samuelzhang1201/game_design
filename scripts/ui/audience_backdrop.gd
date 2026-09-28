class_name AudienceBackdrop
extends Control
## The scene behind the person in the audience window (owner 2026-09-15, after
## Crusader Kings III, where a courtier stands before the room they are met
## in). There is no room painting yet, so the scene is drawn: the location
## kind's tint (LocationView.KIND_COLORS) washing down into the dark, a warm
## glow on the floor where the figure stands, and a vignette closing the
## corners. A location that names a painting in data/locations.csv `backdrop`
## gets the painting instead, cover-cropped, with the same vignette over it.

## Where the audience is held (data/locations.csv); "" draws the fallback tint.
var location_code := "":
	set(value):
		location_code = value
		queue_redraw()

## The glow and the vignette are smooth radial gradients (owner 2026-09-28,
## second critique: the stacked rings and circles that drew them showed as
## steps). Built once, stretched over the rect.
static var _vignette: GradientTexture2D
static var _glow: GradientTexture2D

static func _radial(stops: PackedFloat32Array, colors: PackedColorArray, reach: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = stops
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5 + reach, 0.5)
	t.width = 256
	t.height = 256
	return t

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _row() -> Dictionary:
	if Game == null or Game.data == null or location_code == "":
		return {}
	return LocationSystem.location(Game.data, location_code)

## The location's painting, or null while it has none (the usual case today).
func painting() -> Texture2D:
	var path := String(_row().get("backdrop", ""))
	return UiPalette.load_art(path) if path != "" else null

func tint() -> Color:
	return LocationView.KIND_COLORS.get(String(_row().get("kind", "")), LocationView.KIND_FALLBACK)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var art := painting()
	if art != null:
		_draw_cover(art, r)
	else:
		_draw_wash(r)
	_draw_vignette(r)

## A vertical wash from the kind's tint, lifted a little, down to near-black,
## with a warm ellipse of light on the floor under the figure.
func _draw_wash(r: Rect2) -> void:
	var top := tint().lightened(0.12)
	var bottom := UiPalette.BG_SCREEN
	var colors := PackedColorArray([top, top, bottom, bottom])
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
		r.end, Vector2(r.position.x, r.end.y)]), colors)
	if _glow == null:
		_glow = _radial(PackedFloat32Array([0.0, 1.0]),
			PackedColorArray([Color(UiPalette.GOLD, 0.2), Color(UiPalette.GOLD, 0.0)]), 0.5)
	var gw := r.size.x * 1.1
	var gh := gw * 0.32
	var center := Vector2(r.get_center().x, r.end.y - r.size.y * 0.1)
	draw_texture_rect(_glow, Rect2(center - Vector2(gw, gh) * 0.5, Vector2(gw, gh)), false)

func _draw_cover(art: Texture2D, r: Rect2) -> void:
	var img := Vector2(art.get_width(), art.get_height())
	var aspect := r.size.x / r.size.y
	var region: Rect2
	if img.x / img.y > aspect:
		var w := img.y * aspect
		region = Rect2((img.x - w) / 2.0, 0.0, w, img.y)
	else:
		var h := img.x / aspect
		region = Rect2(0.0, (img.y - h) / 2.0, img.x, h)
	draw_texture_rect_region(art, r, region)

func _draw_vignette(r: Rect2) -> void:
	if _vignette == null:
		_vignette = _radial(PackedFloat32Array([0.0, 0.5, 1.0]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6)]), 0.72)
	draw_texture_rect(_vignette, r, false)
