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

const PIXEL_FONT_PATH := "res://assets/fonts/pixel.ttf"  # optional; default font otherwise

## Static 2D map placeholder shown behind the gameplay screens (user-provided
## screenshot; the crop trims the foreign UI chrome baked into its edges).
const MAP_BACKDROP_PATH := "res://assets/portraits/full/map_example.jpeg"
const MAP_EDGE_CROP := 34.0

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

## Game-wide Theme, applied once at GameRoot and inherited by every screen:
## parchment labels, gold-trimmed dark buttons and inputs, plus the optional
## pixel font when present.
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
	if FileAccess.file_exists(PIXEL_FONT_PATH):
		var font: Font = load(PIXEL_FONT_PATH)
		if font != null:
			theme.default_font = font
			theme.default_font_size = 16
	return theme
