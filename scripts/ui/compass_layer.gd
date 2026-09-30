class_name CompassLayer
extends Node2D
## The map's compass as game art (owner 2026-09-14): aged oak with a ship's
## wheel and brass gears (library I-73, assets/2D/ui/compass/compass.png), drawn in the
## top-right box WorldMapView.compass_rect() gives, and TURNING clockwise
## while time runs — map_compass_turn_deg_per_s at 1x, faster at 2x and 4x —
## holding still when the clock is paused. A child of the view over its own
## drawing, so a turning compass redraws itself and never the map. When the
## art is not installed the layer draws nothing and the view keeps its
## vector rose. Purely a look: the angle is never game state.

const ART_PATH := "res://assets/2D/ui/compass/compass.png"

## Asked every frame for the box to draw in (screen px of the view).
var box: Callable = func() -> Rect2: return Rect2()
var texture: Texture2D = null
var angle := 0.0

func setup() -> void:
	texture = UiPalette.load_art(ART_PATH)

## Whether the art is in: the view hides its vector rose when it is.
func has_art() -> bool:
	return texture != null

func _process(delta: float) -> void:
	if texture == null or Game.data == null:
		return
	if Game.clock_speed > 0:
		angle = fposmod(angle + deg_to_rad(Game.data.bal("map_compass_turn_deg_per_s"))
			* float(Game.clock_speed) * delta, TAU)
		queue_redraw()

func _draw() -> void:
	if texture == null:
		return
	var r := box.call() as Rect2
	if r.size.x <= 0.0:
		return
	var alpha := Game.data.bal("map_compass_alpha") if Game.data != null else 1.0
	draw_set_transform(r.get_center(), angle, Vector2.ONE)
	draw_texture_rect(texture, Rect2(-r.size * 0.5, r.size), false, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
