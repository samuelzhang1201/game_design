@tool
class_name LoadWheel
extends TextureRect
## The ship's wheel that turns in the launch black's bottom-right corner (owner
## 2026-10-12) so the player sees the game is loading: the map's own compass
## art, turning clockwise at map_compass_turn_deg_per_s whatever the clock
## does. A scene (scenes/hud/load_wheel.tscn) holds the look; this only turns
## it. Purely a look: the angle is never game state.

func _ready() -> void:
	resized.connect(_centre_pivot)
	_centre_pivot()

func _centre_pivot() -> void:
	pivot_offset = size * 0.5

func _process(delta: float) -> void:
	if Engine.is_editor_hint():   # the editor neither loads the look data nor turns it (a save would keep the angle)
		return
	var repo := UiPalette.data()
	if repo == null or not is_visible_in_tree():
		return
	rotation = fposmod(rotation + deg_to_rad(repo.bal("map_compass_turn_deg_per_s")) * delta, TAU)
