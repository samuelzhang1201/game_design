class_name UiPalette
extends RefCounted
## Single source of UI colors, shared styles, and chrome art (architecture
## review 2026-08-29; retuned 2026-08-29 to the UI_example.png mock: near
## black ground, thin antique-gold trim, parchment text). Screens own their
## structure; every color, panel style, and the map backdrop come from here.
## Stateless statics on purpose - no autoload, no tree presence needed.

const BG_STAGE := Color("0b0c11")      # conversation backdrop ground
const BG_SCREEN := Color("0b0c11")     # menu / court / day-run ground
const PANEL_BG := Color("12141d")
const CHIP_BG := Color("1a1c26")       # buttons, trait chips, input fields
const GOLD := Color("c9a45c")          # headers, names, dates, accents
const BORDER_GOLD := Color("6e5f38")   # thin panel/button trim
const TEXT_SOFT := Color("d8d2c4")     # parchment body text
const TEXT_MUTED := Color("8a8578")    # secondary text, section labels
const TEXT_DIM := Color("6a6557")      # de-emphasized hints ("click to skip")
const POSITIVE := Color("7fd47f")      # metric gains, opinion up
const NEGATIVE := Color("d4756a")      # metric losses, opinion down
const DIM_OVERLAY := Color(0.04, 0.04, 0.07, 0.84)
## Light tone over the map on gameplay screens (user ruling 2026-08-30: the
## map stays bright and clear at all times; panels are opaque anyway).
const MAP_TINT := Color(0.02, 0.02, 0.05, 0.18)

## OFL-licensed faces (assets/fonts/, licenses alongside): EB Garamond for
## body text, Cinzel (Roman inscription capitals) for headers, names, dates.
const BODY_FONT_PATH := "res://assets/fonts/EBGaramond.ttf"
const DISPLAY_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const BODY_FONT_SIZE := 12

## Static 2D map placeholder shown behind the gameplay screens (user-provided
## screenshot; the crop trims the foreign UI chrome baked into its edges).
const MAP_BACKDROP_PATH := "res://assets/portraits/full/map_example.jpeg"
const MAP_EDGE_CROP := 34.0

## Decorative screen frame (two kings at a chess game, user-provided art;
## tools/key_frame_interior.py produced the real-alpha PNG). Drawn above the
## map backdrop, below the UI panels, on every screen.
const FRAME_PATH := "res://assets/ui/frame.png"

static func frame() -> Texture2D:
	return load_art(FRAME_PATH)

## Standard setup for the full-bleed frame layer (menu only): stretches
## edge-to-edge (art and design viewport are both 16:9), never takes input.
static func setup_frame(rect: TextureRect) -> void:
	rect.texture = frame()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Nine-patch frame for gameplay screens (user ruling 2026-08-30: the frame
## sits in the MIDDLE map area between the two UI columns and must cover no
## UI element). The pre-scaled texture (assets/ui/frame_small.png, 591x333)
## keeps the corner kings at their native aspect while the rails tile to fit
## whatever middle rect the screen gives the node. Margins bound the kings:
## young king + chessboard bottom-left, old king top-right.
const FRAME_SMALL_PATH := "res://assets/ui/frame_small.png"

static func setup_frame_nine(patch: NinePatchRect) -> void:
	patch.texture = load_art(FRAME_SMALL_PATH)
	patch.patch_margin_left = 130
	patch.patch_margin_top = 57
	patch.patch_margin_right = 92
	patch.patch_margin_bottom = 71
	# Plain stretch on both axes: the bands hold pictorial content (the
	# kings, the rails' center pendant) that tiling would duplicate or
	# shred into stripes; a smooth compression reads far better.
	patch.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	patch.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	patch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE

static var _art_cache: Dictionary = {}

static func panel_style(border: Color, border_width: int = 2,
		margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(margin)
	return style

static func chip_style(bg: Color = CHIP_BG, border: Color = BORDER_GOLD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style

## Loads a texture, preferring the import pipeline (exported builds pack only
## imported resources) with a raw-file fallback for art dropped in without an
## editor import yet and for headless runs. Cached; null when absent.
static func load_art(path: String) -> Texture2D:
	if _art_cache.has(path):
		return _art_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	_art_cache[path] = tex
	return tex

## The shared map backdrop, edge-cropped. Null when the file is missing
## (screens fall back to their flat ground color).
static func backdrop() -> Texture2D:
	var key := "backdrop:" + MAP_BACKDROP_PATH
	if _art_cache.has(key):
		return _art_cache[key]
	var tex: Texture2D = null
	var base := load_art(MAP_BACKDROP_PATH)
	if base != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = base
		atlas.region = Rect2(MAP_EDGE_CROP, MAP_EDGE_CROP,
			base.get_width() - 2.0 * MAP_EDGE_CROP,
			base.get_height() - 2.0 * MAP_EDGE_CROP)
		tex = atlas
	_art_cache[key] = tex
	return tex

static func body_font() -> Font:
	return _load_font(BODY_FONT_PATH)

static func display_font() -> Font:
	return _load_font(DISPLAY_FONT_PATH)

static func _load_font(path: String) -> Font:
	if _art_cache.has(path):
		return _art_cache[path]
	var font: Font = null
	if ResourceLoader.exists(path):
		font = load(path) as Font
	elif FileAccess.file_exists(path):
		var file_font := FontFile.new()
		if file_font.load_dynamic_font(path) == OK:
			font = file_font
	_art_cache[path] = font
	return font

## Header treatment: Cinzel in gold (or the given color) at a small size -
## used for speaker names, dates, section headers, the menu title.
static func style_header(label: Label, size: int, color: Color = GOLD) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	var font := display_font()
	if font != null:
		label.add_theme_font_override("font", font)

## Game-wide Theme, applied once at GameRoot and inherited by every screen:
## EB Garamond parchment body text at a compact size, gold-trimmed dark
## buttons and inputs.
static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", TEXT_SOFT)
	theme.set_color("font_color", "Button", TEXT_SOFT)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_stylebox("normal", "Button", chip_style())
	theme.set_stylebox("hover", "Button", chip_style(CHIP_BG.lightened(0.05), GOLD))
	theme.set_stylebox("pressed", "Button", chip_style(PANEL_BG, GOLD))
	theme.set_stylebox("disabled", "Button", chip_style(PANEL_BG, Color(BORDER_GOLD, 0.4)))
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_stylebox("normal", "LineEdit", chip_style(Color("0f1017")))
	theme.set_color("font_color", "LineEdit", TEXT_SOFT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	var body := body_font()
	if body != null:
		theme.default_font = body
	theme.default_font_size = BODY_FONT_SIZE
	return theme
