class_name UiPalette
extends RefCounted
## Single source of UI colors, shared styles, and chrome art (architecture
## review 2026-08-29). Screens own their structure; every color, panel style,
## and the map backdrop come from here. Stateless statics on purpose - no
## autoload, no tree presence needed.
##
## Retuned 2026-09-13 to a BRIGHT, MODERN theme (owner request: the parchment
## look read old and dim): dark slate ink on near-white panels with rounded
## corners, a royal-blue accent for headers and names, gold kept for trim.
## The parchment values of 2026-09-12 are kept beside each line, so going
## back is a find-and-replace in this one file.

const BG_SCREEN := Color("e6ebf1")     # the desk behind the panels (was 2b2119)
const PANEL_BG := Color("fdfcf9")      # panel body (was e6dcc4)
const CHIP_BG := Color("eef2f7")       # buttons, trait chips, inputs (was dccfb0)
const GOLD := Color("2456a4")          # ACCENT: headers, names, dates — royal blue now (was 8a6420)
const BORDER_GOLD := Color("d2b36a")   # thin panel/button trim: bright gold (was a58f5c)
const TEXT_SOFT := Color("1e2530")     # body ink (was 3a3026)
const TEXT_MUTED := Color("4f5b6b")    # secondary text, labels (was 6d6150)
const TEXT_DIM := Color("7a8594")      # de-emphasized hints (was 8d8370)
const POSITIVE := Color("2f9e44")      # metric gains, opinion up (was 3f7a3f)
const NEGATIVE := Color("d64545")      # metric losses, opinion down (was 9e3f33)
const DIM_OVERLAY := Color(0.12, 0.16, 0.22, 0.55)  # (was 0.11, 0.08, 0.05, 0.84)
## Translucent ground for the chronicle ticker (game_ui.png: a transparent
## window whose surroundings stay visible through it).
const GLASS_BG := Color(1.0, 1.0, 1.0, 0.88)
## Softer glass for the always-on bottom news strip (user request
## 2026-08-31: the ticker is transparent, the screen stays visible under it).
const GLASS_BG_SOFT := Color(1.0, 1.0, 1.0, 0.7)
## The quiet edge of a panel or chip, under the gold trim's weight.
const EDGE := Color("cfd8e3")

## Per-skill bar colors, matching the mock's attribute rows (diplomacy green,
## martial red, stewardship gold, intrigue purple, admin/learning blue).
const SKILL_COLORS := {
	"sk_diplomacy": Color("2f9e44"), "sk_martial": Color("d64545"),
	"sk_steward": Color("d9a21b"), "sk_intrigue": Color("7c4ddb"),
	"sk_admin": Color("2f7ed8"),
}
const SKILL_NAMES := {
	"sk_admin": "Admin", "sk_martial": "Martial", "sk_intrigue": "Intrigue",
	"sk_diplomacy": "Diplomacy", "sk_steward": "Steward",
}
const SKILL_MAX := 20.0  # CharacterFactory clamps skills to 0..20

## Dossier SKILLS-tab tool colors (user request 2026-08-31): the accent for a
## seat's kingdom operations, teal for person-to-person tools, so the two
## kinds read apart at a glance.
const TOOL_KINGDOM := GOLD
const TOOL_PERSONAL := Color("13897b")

## Family flag choices for character creation (simple icons for now — art
## comes later): a font glyph on a heraldic field color, picked in the main
## menu and shown beside the date in the TopBar.
const FLAGS := [
	{"id": "sun", "symbol": "☀", "color": Color("d9a21b")},
	{"id": "moon", "symbol": "☾", "color": Color("2f7ed8")},
	{"id": "blade", "symbol": "†", "color": Color("d64545")},
	{"id": "leaf", "symbol": "❦", "color": Color("2f9e44")},
	{"id": "star", "symbol": "✶", "color": Color("7c4ddb")},
	{"id": "tower", "symbol": "♜", "color": Color("5a6778")},
]

static func flag_by_id(id: String) -> Dictionary:
	for f in FLAGS:
		if String(f["id"]) == id:
			return f
	return FLAGS[0]

## OFL-licensed faces (assets/fonts/, licenses alongside), divided by job
## (owner requests 2026-09-13):
## - TITLE: UnifrakturMaguntia (blackletter) for the game title, headers and
##   the kingdom names on the map — style_header, map_label_font.
## - TAB: Cinzel Decorative on tab buttons — style_tab.
## - CONTENT: Cinzel for everything else — dialogue, menu and setting options,
##   long text — the theme's default font.
## - The scale bar and the heraldic shield are Cinzel as well (display_font).
const TITLE_FONT_PATH := "res://assets/fonts/UnifrakturMaguntia-Book.ttf"
const TAB_FONT_PATH := "res://assets/fonts/CinzelDecorative-Regular.ttf"
const CONTENT_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const MAP_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const BODY_FONT_SIZE := 18
## The conversation transcript (owner 2026-09-13: the 8 px it had was
## unreadable).
const DIALOGUE_FONT_SIZE := 18
## Blackletter reads a size smaller than a Roman face at the same px, so
## every header and tab is drawn this much larger than its caller asks.
const TITLE_SIZE_SCALE := 1.2
const LINE_SPACING := 0

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

## Flat bar styles for attribute/opinion bars (no chip margins).
static func bar_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style

static func bar_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("e6ebf1")  # the trough (was cdbf9f)
	style.border_color = EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style

static var _art_cache: Dictionary = {}

## The vellum panel plate (owner request 2026-09-12): library U-01 rendered
## through assets/flux and white-balanced onto the library's Cream Laid.
## Drawn by VellumPanelStyle, not StyleBoxTexture, so the plate stays at its
## full 475 px while the corner draws at 20 design px — see that class for why
## the built-in one cannot. Off since the bright theme (ui_panel_art 0).
const PANEL_ART_PATH := "res://assets/ui/panel_vellum.png"
## The border-and-ornament band, in the plate's own pixels.
const PANEL_ART_SOURCE_INSET := 75.0
## The same band as drawn on screen, in design px.
const PANEL_ART_INSET := 40.0
## Rounded corners on the flat panels and chips, in design px.
const PANEL_RADIUS := 10
const CHIP_RADIUS := 6

## Whether panels are drawn as the plate. Data, not a constant: the whole
## look turns on this one value in balance.csv and no screen has to change
## either way.
static func panel_art_enabled() -> bool:
	if Game == null or Game.data == null:
		return false
	return Game.data.bal("ui_panel_art") > 0.0

## The plate as a nine-slice: border and corner ornaments hold their size
## while the middle stretches. null when the art is missing, so a build
## without it falls back instead of drawing nothing.
static func panel_art_style(margin: int) -> VellumPanelStyle:
	var tex := load_art(PANEL_ART_PATH)
	if tex == null:
		return null
	var style := VellumPanelStyle.new()
	style.texture = tex
	style.source_inset = PANEL_ART_SOURCE_INSET
	style.draw_inset = PANEL_ART_INSET
	# A floor under the caller's margin so text does not sit ON the ruled
	# border — but only a quarter of the corner inset, not all of it. Forcing
	# the full 40 px put 56 px of padding into a 36 px tab strip and pushed it
	# off the bottom of the screen (owner report 2026-09-12).
	style.set_content_margin_all(maxf(float(margin), PANEL_ART_INSET * 0.25))
	return style

## The plate's ornament alone (owner 2026-09-14: "restore the decorative
## border"): panel_vellum.png with its cream made clear, leaving the double
## rule, the hairline and the corner flourishes in the art's own ink. Drawn
## over the bright card, so the modern theme keeps its body and gets its
## frame back.
const PANEL_ORNAMENT_PATH := "res://assets/ui/panel_ornament.png"

static func panel_ornament_enabled() -> bool:
	if Game == null or Game.data == null or not Game.data.balance.has("ui_panel_ornament"):
		return false
	return Game.data.bal("ui_panel_ornament") > 0.0

## A clean card: near-white body, a thin trim in `border`, rounded corners
## and a soft drop shadow — framed by the ornament when ui_panel_ornament is
## on and the art loads.
static func panel_style(border: Color, border_width: int = 2,
		margin: int = 12) -> StyleBox:
	if panel_art_enabled():
		var art := panel_art_style(margin)
		if art != null:
			return art
	var card := _card_style(border, border_width, margin)
	if panel_ornament_enabled():
		var tex := load_art(PANEL_ORNAMENT_PATH)
		if tex != null:
			var framed := VellumPanelStyle.new()
			framed.base = card
			framed.texture = tex
			framed.source_inset = PANEL_ART_SOURCE_INSET
			framed.draw_inset = PANEL_ART_INSET
			# Text keeps clear of the rules, as the vellum plate's floor did.
			framed.set_content_margin_all(maxf(float(margin), PANEL_ART_INSET * 0.25))
			return framed
	return card

## How far content must stand in from a framed panel's edges to clear the
## ornament (owner 2026-09-14: the top bar's MENU sat on the corner
## flourish). The scrolls fill most of a corner square of PANEL_ART_INSET, so
## the sides keep that much plus a gap; the rules along the top and bottom
## are thin, so a strip of text only needs to sit inside the hairline.
const ORNAMENT_CLEAR_H := PANEL_ART_INSET + 6.0
const ORNAMENT_CLEAR_V := PANEL_ART_INSET * 0.35

## Give a panel style margins that keep its content off the ornament — a
## no-op for the plain card, which has none. For a wide, short strip (the
## top bar), whose content would otherwise run into the corner scrolls.
static func clear_ornament(style: StyleBox) -> StyleBox:
	if style is VellumPanelStyle:
		style.content_margin_left = maxf(style.content_margin_left, ORNAMENT_CLEAR_H)
		style.content_margin_right = maxf(style.content_margin_right, ORNAMENT_CLEAR_H)
		style.content_margin_top = maxf(style.content_margin_top, ORNAMENT_CLEAR_V)
		style.content_margin_bottom = maxf(style.content_margin_bottom, ORNAMENT_CLEAR_V)
	return style

## A small button that sits in a strip without stretching to the strip's
## height: tight padding, a fixed height, centred in its row.
static func compact_button(button: Button, height: float, font_px: int, pad: float = 6.0) -> void:
	button.add_theme_font_size_override("font_size", font_px)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(button.custom_minimum_size.x, height)
	var looks := {"normal": chip_style(), "hover": chip_style(Color("e3ecf8"), GOLD),
		"pressed": chip_style(Color("dbe6f6"), GOLD),
		"disabled": chip_style(PANEL_BG, Color(EDGE, 0.6))}
	for state: String in looks:
		var box: StyleBoxFlat = looks[state]
		box.content_margin_left = pad
		box.content_margin_right = pad
		box.content_margin_top = 1.0
		box.content_margin_bottom = 1.0
		button.add_theme_stylebox_override(state, box)

static func _card_style(border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = border
	style.set_border_width_all(mini(border_width, 1) if border_width > 0 else 0)
	style.set_corner_radius_all(PANEL_RADIUS)
	style.shadow_color = Color(0.08, 0.12, 0.2, 0.12)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	style.set_content_margin_all(margin)
	return style

static func chip_style(bg: Color = CHIP_BG, border: Color = EDGE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(CHIP_RADIUS)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
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

## Headers, the game title.
static func title_font() -> Font:
	return _load_font(TITLE_FONT_PATH)

## Tab buttons.
static func tab_font() -> Font:
	return _load_font(TAB_FONT_PATH)

## The kingdom names lettered across the map.
static func map_label_font() -> Font:
	return title_font()

## Dialogue, options, long text — and the theme default.
static func content_font() -> Font:
	return _load_font(CONTENT_FONT_PATH)

## The shipped Cinzel file is one weight, so bold is an emboldened variation.
static func content_bold_font() -> Font:
	var key := "bold:" + CONTENT_FONT_PATH
	if _art_cache.has(key):
		return _art_cache[key]
	var base := content_font()
	var font: Font = null
	if base != null:
		var heavy := FontVariation.new()
		heavy.base_font = base
		heavy.variation_embolden = 0.7
		font = heavy
	_art_cache[key] = font
	return font

## Cinzel has no italic; the transcript's narration is set in a slanted
## variation of it.
static func content_italic_font() -> Font:
	var key := "italic:" + CONTENT_FONT_PATH
	if _art_cache.has(key):
		return _art_cache[key]
	var base := content_font()
	var font: Font = null
	if base != null:
		var slanted := FontVariation.new()
		slanted.base_font = base
		slanted.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
		font = slanted
	_art_cache[key] = font
	return font

## What text drawn by hand uses: numbers on map counters and badges, chart
## labels. The content face, so they match the panels around them.
static func body_font() -> Font:
	return content_font()

## The scale bar's distance and the heraldic shield's letters — Cinzel.
static func display_font() -> Font:
	return _load_font(MAP_FONT_PATH)

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

## A chart colour by key (data/chart_palette.csv); cat_N falls back to the
## last categorical step rather than a made-up hue.
static func chart_color(key: String) -> Color:
	var hex := String(Game.data.chart_palette.get(key, ""))
	if hex == "" and key.begins_with("cat_"):
		var n := 1
		while Game.data.chart_palette.has("cat_%d" % (n + 1)):
			n += 1
		hex = String(Game.data.chart_palette.get("cat_%d" % n, ""))
	return Color(hex) if hex != "" else TEXT_MUTED

static func title_size(size: int) -> int:
	return int(round(float(size) * TITLE_SIZE_SCALE))

## Blackletter capitals set in a row cannot be read ("TEMPER OF THE REALM"
## came out as a picket fence, 2026-09-13), so text that is ALL capitals when
## it is given the title face is set in title case instead: "Temper of the
## Realm". Mixed-case text is left exactly as written.
static func readable_title(text: String) -> String:
	if text == "" or text != text.to_upper() or text == text.to_lower():
		return text
	var small := ["of", "the", "and", "a", "an", "as", "by", "in", "on", "to", "at"]
	var words := text.to_lower().split(" ")
	for i in words.size():
		var w: String = words[i]
		if w == "" or (i > 0 and small.has(w)):
			continue
		words[i] = w.substr(0, 1).to_upper() + w.substr(1)
	return " ".join(words)

## Header treatment: the title face in the accent (or the given color) - used
## for speaker names, dates, section headers, the menu title.
static func style_header(label: Label, size: int, color: Color = GOLD) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", title_size(size))
	var font := title_font()
	if font != null:
		label.add_theme_font_override("font", font)
		label.text = readable_title(label.text)

## Tab treatment (owner 2026-09-13): tab buttons read in Cinzel Decorative.
## `pad` narrows the chip's side padding for a strip that must hold many
## tabs in one row; below 0 keeps the theme's chip.
static func style_tab(button: Button, size: int, pad: float = -1.0) -> void:
	button.add_theme_font_size_override("font_size", size)
	var font := tab_font()
	if font != null:
		button.add_theme_font_override("font", font)
	if pad < 0.0:
		return
	var looks := {"normal": chip_style(), "hover": chip_style(Color("e3ecf8"), GOLD),
		"pressed": chip_style(Color("dbe6f6"), GOLD),
		"disabled": chip_style(PANEL_BG, Color(EDGE, 0.6))}
	for state: String in looks:
		var box: StyleBoxFlat = looks[state]
		box.content_margin_left = pad
		box.content_margin_right = pad
		button.add_theme_stylebox_override(state, box)

## Game-wide Theme, applied once at GameRoot and inherited by every screen:
## the content face in dark ink at a compact size, rounded light buttons and
## inputs.
static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", TEXT_SOFT)
	theme.set_color("font_color", "Button", TEXT_SOFT)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_stylebox("normal", "Button", chip_style())
	theme.set_stylebox("hover", "Button", chip_style(Color("e3ecf8"), GOLD))
	theme.set_stylebox("pressed", "Button", chip_style(Color("dbe6f6"), GOLD))
	theme.set_stylebox("disabled", "Button", chip_style(PANEL_BG, Color(EDGE, 0.6)))
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_stylebox("normal", "LineEdit", chip_style(Color.WHITE))
	theme.set_stylebox("focus", "LineEdit", chip_style(Color.WHITE, GOLD))
	theme.set_color("font_color", "LineEdit", TEXT_SOFT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_constant("line_spacing", "Label", LINE_SPACING)
	# The transcript is a RichTextLabel, whose ink is NOT the Label colour:
	# left unset it was Godot's default white on a light panel (owner report
	# 2026-09-13: the dialogue was too white to read).
	theme.set_color("default_color", "RichTextLabel", TEXT_SOFT)
	theme.set_font_size("normal_font_size", "RichTextLabel", DIALOGUE_FONT_SIZE)
	theme.set_font_size("bold_font_size", "RichTextLabel", DIALOGUE_FONT_SIZE)
	theme.set_font_size("italics_font_size", "RichTextLabel", DIALOGUE_FONT_SIZE)
	# Floating tooltips (user request 2026-09-09: icons explain themselves on
	# hover) in the same chip chrome as everything else.
	theme.set_stylebox("panel", "TooltipPanel", chip_style(Color.WHITE, EDGE))
	theme.set_color("font_color", "TooltipLabel", TEXT_SOFT)
	theme.set_font_size("font_size", "TooltipLabel", 16)
	var body := content_font()
	if body != null:
		theme.default_font = body
		theme.set_font("normal_font", "RichTextLabel", body)
		theme.set_font("bold_font", "RichTextLabel", content_bold_font())
		theme.set_font("italics_font", "RichTextLabel", content_italic_font())
	theme.default_font_size = BODY_FONT_SIZE
	return theme
