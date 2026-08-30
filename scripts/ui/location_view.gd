class_name LocationView
extends Control
## One location's visual as a self-contained scene (user ruling 2026-08-30:
## each location is a scene), mirroring CharacterPortrait's pattern so art
## can be dropped in per location without touching any screen:
##   1. Open the location's scene in scenes/locations/ (e.g. war_room.tscn).
##   2. Add your art as a child node named exactly "CustomArt".
##   3. Done — the default kind-colored banner is skipped.
## Instantiate via LocationView.instantiate_for(code) — it picks the
## location's own scene when one exists, else the base scene.

const VIEW_SIZE := Vector2(128, 26)
const SCENE_DIR := "res://scenes/locations/"
const BASE_SCENE := SCENE_DIR + "base_location.tscn"

## Banner tint per location kind (data/locations.csv `kind`).
const KIND_COLORS := {
	"court": Color("4a3f28"), "martial": Color("4a2828"),
	"home": Color("3d3350"), "private": Color("2f3a4a"),
	"city": Color("2f4a33"), "field": Color("4a442f"),
}

@export var location_code: String = ""

static func instantiate_for(code: String) -> LocationView:
	var path := SCENE_DIR + code + ".tscn"
	if not ResourceLoader.exists(path):
		path = BASE_SCENE
	var view: LocationView = load(path).instantiate()
	view.location_code = code
	return view

func _ready() -> void:
	custom_minimum_size = VIEW_SIZE
	refresh()

func refresh() -> void:
	for child in get_children():
		if child.name.begins_with("Gen_"):
			child.queue_free()
	if has_node("CustomArt"):
		return
	var row := data_row()
	var banner := ColorRect.new()
	banner.name = "Gen_Banner"
	banner.color = KIND_COLORS.get(String(row.get("kind", "")), Color("333333"))
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(banner)
	var label := Label.new()
	label.name = "Gen_Label"
	label.text = String(row.get("label", location_code.capitalize()))
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiPalette.style_header(label, 9)
	add_child(label)
	tooltip_text = String(row.get("notes", ""))

func data_row() -> Dictionary:
	if Game.data != null:
		return LocationSystem.location(Game.data, location_code)
	return {}
