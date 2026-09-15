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

const VIEW_SIZE := Vector2(256, 52)
const SCENE_DIR := "res://scenes/locations/"
const BASE_SCENE := SCENE_DIR + "base_location.tscn"

## Banner tint per location kind (data/locations.csv `kind`). Dark tints for
## the dark theme (owner 2026-09-15): the name is drawn in the gold accent.
## The same tint washes the audience window's backdrop (AudienceBackdrop).
## Bright-theme values: court f6e7bf, martial f7d6d2, home e5dcf5,
## private d9e6f5, city d7efd9, field efe8cf, fallback e6ebf1.
const KIND_COLORS := {
	"court": Color("4a3a22"), "martial": Color("4a2622"),
	"home": Color("372c4a"), "private": Color("22324a"),
	"city": Color("25402a"), "field": Color("423c24"),
}
const KIND_FALLBACK := Color("2d251d")

@export var location_code: String = ""

## The height this view actually got — the design height, or the slot's when
## the slot is smaller. The generated banner sizes its label to it.
var _band := VIEW_SIZE.y

static func instantiate_for(code: String) -> LocationView:
	var path := SCENE_DIR + code + ".tscn"
	if not ResourceLoader.exists(path):
		path = BASE_SCENE
	var view: LocationView = load(path).instantiate()
	view.location_code = code
	return view

func _ready() -> void:
	# The slot decides how much room there is. The conversation column gives
	# this a thin strip (128x22) and clips it, so a view that keeps the full
	# design size has its name label cut in half — the banner showed as a bare
	# brown bar. Take the slot's own minimum when it has one, and fill it.
	custom_minimum_size = VIEW_SIZE
	_band = VIEW_SIZE.y
	var slot := get_parent() as Control
	if slot != null and slot.custom_minimum_size.y > 0.0:
		custom_minimum_size = Vector2.ZERO
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_band = slot.custom_minimum_size.y
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
	banner.color = KIND_COLORS.get(String(row.get("kind", "")), KIND_FALLBACK)
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(banner)
	var label := Label.new()
	label.name = "Gen_Label"
	label.text = String(row.get("label", location_code.capitalize()))
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A thin strip cannot carry the full header size; the label follows the
	# banner's own height so the name fits whatever room the slot gave.
	UiPalette.style_header(label, 16 if _band >= 40.0 else 12)
	add_child(label)
	tooltip_text = String(row.get("notes", ""))

func data_row() -> Dictionary:
	if Game.data != null:
		return LocationSystem.location(Game.data, location_code)
	return {}
