class_name CharacterPortrait
extends Control
## One character's visual as a self-contained scene, so art can be replaced
## per character in the editor without touching the council screen.
##
## HOW TO SWAP IN YOUR OWN ART (e.g. a Sprite2D):
##   1. Open this character's scene in scenes/characters/ (e.g. char_marshal.tscn).
##   2. Add your art as a child node named exactly "CustomArt" (Sprite2D,
##      AnimatedSprite2D, TextureRect - anything).
##   3. Done. When a "CustomArt" node exists, this script skips building the
##      default pixel-PNG visual and only maintains the opinion badge and
##      tooltip. Remember Sprite2D positions from its center: place it at
##      (24, 24) to sit inside the 48x48 portrait box.
##
## Instantiate via CharacterPortrait.instantiate_for(id) - it picks the
## character's own scene when one exists, else the base scene.
##
## FULL-BODY ART: drop a real-alpha PNG at assets/portraits/full/<id>.png
## (tools/clean_portrait_art.py turns raw exports into one) and the VN
## conversation stage uses it instead of the 4x-scaled chip. The 48x48 chip
## above is still what council/court screens show.

const PORTRAIT_SIZE := Vector2(48, 48)
const SCENE_DIR := "res://scenes/characters/"
const BASE_SCENE := SCENE_DIR + "character_portrait.tscn"
const PNG_DIR := "res://assets/portraits/"
const FULL_PNG_DIR := "res://assets/portraits/full/"

const SEAT_COLORS := {
	"chancellor": Color("4a6fa5"), "marshal": Color("a54a4a"),
	"steward": Color("4aa571"), "spymaster": Color("6b4aa5"),
	"chaplain": Color("a58c4a"), "chief_justice": Color("4aa5a0"),
	"master_of_works": Color("8c8c8c"), "admiral": Color("2f5f8f"),
	"court_physician": Color("a54a8c"),
}
const DEFAULT_SEAT_COLOR := Color("555555")

@export var character_id: String = ""
@export var show_badge: bool = true

static func instantiate_for(id: String, with_badge: bool = true) -> CharacterPortrait:
	var path := SCENE_DIR + id + ".tscn"
	if not ResourceLoader.exists(path):
		path = BASE_SCENE
	var portrait: CharacterPortrait = load(path).instantiate()
	portrait.character_id = id
	portrait.show_badge = with_badge
	return portrait

func _ready() -> void:
	custom_minimum_size = PORTRAIT_SIZE
	refresh()

func set_character(id: String) -> void:
	character_id = id
	refresh()

func refresh() -> void:
	_clear_generated()
	if not has_node("CustomArt"):
		_build_default_visual()
	_build_badge_and_tooltip()

func _clear_generated() -> void:
	for child in get_children():
		if child.name.begins_with("Gen_"):
			child.queue_free()

func _character() -> Character:
	if Game.state != null and Game.state.characters.has(character_id):
		return Game.state.characters[character_id]
	return null

func _seat_color() -> Color:
	var c := _character()
	if c != null:
		return SEAT_COLORS.get(c.seat, DEFAULT_SEAT_COLOR)
	return DEFAULT_SEAT_COLOR

func _display_name() -> String:
	var c := _character()
	if c != null:
		return c.display_name
	return character_id.capitalize()

func _build_default_visual() -> void:
	var tex := texture_for(character_id)
	if tex != null:
		var pic := TextureRect.new()
		pic.name = "Gen_Texture"
		pic.texture = tex
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(pic)
	else:
		var bg := ColorRect.new()
		bg.name = "Gen_Fallback"
		bg.color = _seat_color()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		var initial := Label.new()
		initial.name = "Gen_Initial"
		initial.text = _display_name().left(1).to_upper()
		initial.set_anchors_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(initial)

func _build_badge_and_tooltip() -> void:
	var c := _character()
	if c == null:
		tooltip_text = _display_name()
		return
	if show_badge:
		var badge := Label.new()
		badge.name = "Gen_Badge"
		badge.text = str(c.opinion)
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color",
			UiPalette.POSITIVE if c.opinion >= 0 else UiPalette.NEGATIVE)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		add_child(badge)
	var recent := ""
	var log := c.opinion_log
	for i in range(maxi(0, log.size() - 5), log.size()):
		recent += "\n%+d %s" % [int(log[i]["delta"]), log[i]["reason"]]
	tooltip_text = c.display_name + recent

## Loads a portrait PNG, cached per path. Null when no PNG exists for the id.
static func texture_for(id: String) -> Texture2D:
	return _load_png(PNG_DIR + id + ".png")

## Full-body art for the VN conversation stage (assets/portraits/full/<id>.png,
## produced by tools/clean_portrait_art.py). Null when the character has none;
## callers fall back to the 48x48 chip.
static func full_texture_for(id: String) -> Texture2D:
	return _load_png(FULL_PNG_DIR + id + ".png")

static func _load_png(path: String) -> Texture2D:
	return UiPalette.load_art(path)
