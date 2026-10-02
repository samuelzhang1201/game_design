class_name UiPalette
extends RefCounted
## Single source of UI colors, shared styles, and chrome art (architecture
## review 2026-08-29). Screens own their structure; every color, panel style,
## and the map backdrop come from here. Stateless statics on purpose - no
## autoload, no tree presence needed.
##
## Retuned 2026-09-15 to a DARK theme after Crusader Kings III (owner request,
## with the audience window): light parchment ink on dark leather cards, a
## gold accent for headers and names, and the ornament drawn in gold. It
## reverses the BRIGHT, MODERN theme of 2026-09-13, whose values are kept
## beside each line, so going back is a find-and-replace in this one file.

const BG_SCREEN := Color("0f0d0b")     # the desk behind the panels (bright: e6ebf1)
const PANEL_BG := Color("1f1a15")      # panel body — dark leather (bright: fdfcf9)
const CHIP_BG := Color("2d251d")       # buttons, trait chips (bright: eef2f7)
const CHIP_HOVER := Color("342a20")    # a button under the cursor (bright: e3ecf8)
const CHIP_PRESSED := Color("3c3024")  # a button held or lit (bright: dbe6f6)
const INPUT_BG := Color("15110d")      # text inputs, sunk into the card (bright: white)
const TROUGH := Color("14110d")        # the empty part of a bar (bright: e6ebf1)
const GOLD := Color("e0bb6a")          # ACCENT: headers, names, dates — gold again (bright: royal blue 2456a4)
const BORDER_GOLD := Color("a88a4c")   # thin panel/button trim (bright: d2b36a)
const TEXT_SOFT := Color("eee3cb")     # body ink (bright: 1e2530)
const TEXT_MUTED := Color("bfae8f")    # secondary text, labels (bright: 4f5b6b)
const TEXT_DIM := Color("8a7d68")      # de-emphasized hints (bright: 7a8594)
const POSITIVE := Color("7fcf6e")      # metric gains, opinion up (bright: 2f9e44)
const NEGATIVE := Color("ec6f5e")      # metric losses, opinion down (bright: d64545)
const DIM_OVERLAY := Color(0.02, 0.015, 0.01, 0.62)  # (bright: 0.12, 0.16, 0.22, 0.55)
## Translucent ground for the chronicle ticker (game_ui.png: a transparent
## window whose surroundings stay visible through it).
const GLASS_BG := Color(0.09, 0.075, 0.06, 0.9)       # (bright: white 0.88)
## Softer glass for the always-on bottom news strip (user request
## 2026-08-31: the ticker is transparent, the screen stays visible under it).
const GLASS_BG_SOFT := Color(0.09, 0.075, 0.06, 0.72)  # (bright: white 0.7)
## The quiet edge of a panel or chip, under the gold trim's weight.
const EDGE := Color("4b3e30")          # (bright: cfd8e3)
## The panel ornament's ink. The plate is dark lines on clear, which vanish on
## a dark card, so VellumPanelStyle draws it in this gold.
const ORNAMENT_TINT := Color("c9a45a")
## A card's drop shadow: deep, since the desk under it is already dark.
const SHADOW := Color(0.0, 0.0, 0.0, 0.45)  # (bright: 0.08, 0.12, 0.2, 0.12)

## Per-skill bar colors, matching the mock's attribute rows (diplomacy green,
## martial red, stewardship gold, intrigue purple, admin/learning blue) —
## lifted a step to read on the dark card (bright: 2f9e44 d64545 d9a21b
## 7c4ddb 2f7ed8).
const SKILL_COLORS := {
	"sk_diplomacy": Color("7fcf6e"), "sk_martial": Color("ec6f5e"),
	"sk_steward": Color("e6b43a"), "sk_intrigue": Color("a383ee"),
	"sk_admin": Color("5aa2ec"),
}
const SKILL_NAMES := {
	"sk_admin": "Admin", "sk_martial": "Martial", "sk_intrigue": "Intrigue",
	"sk_diplomacy": "Diplomacy", "sk_steward": "Steward",
}
## Three letters for the audience window's skill badges, CK3's row of five.
const SKILL_SHORT := {
	"sk_admin": "ADM", "sk_martial": "MAR", "sk_intrigue": "INT",
	"sk_diplomacy": "DIP", "sk_steward": "STW",
}
const SKILL_MAX := 20.0  # CharacterFactory clamps skills to 0..20

## A gain, a rising opinion (chart_palette.csv positive; POSITIVE the fallback).
static func good_color() -> Color:
	return _chart_or("positive", POSITIVE)

## A loss, a falling opinion, unrest past its mark (chart_palette.csv negative).
static func bad_color() -> Color:
	return _chart_or("negative", NEGATIVE)

static func _chart_or(key: String, fallback: Color) -> Color:
	if Game != null and Game.data != null:
		var hex := String(Game.data.chart_palette.get(key, ""))
		if hex != "":
			return Color(hex)
	return fallback

## THE WAR TABLE (owner 2026-10-01, B3 + C1's bookmarks; spec
## docs/superpowers/specs/2026-10-01-war-table-ui-design.md): the main screens
## laid out as objects on an oak table by daylight. balance ui_war_table 1 is
## on; 0 keeps the dark leather chrome.
static func war_table() -> bool:
	return Game != null and Game.data != null \
		and Game.data.balance.has("ui_war_table") and Game.data.bal("ui_war_table") > 0.0

## The ground a card is drawn on: the war table's paper when an ancestor is a
## paper column (meta "paper_ground"), else the leather (PANEL_BG) — for fades
## that melt a card's edge into what lies under it.
static func card_ground(n: Node) -> Color:
	var p := n
	while p != null:
		if p.has_meta("paper_ground"):
			return p.get_meta("paper_ground")
		p = p.get_parent()
	return PANEL_BG

## A WAR TABLE colour from data/ui_table_palette.csv (#rrggbb or #rrggbbaa).
static func table_color(key: String, fallback := Color.MAGENTA) -> Color:
	if Game != null and Game.data != null:
		var hex := String(Game.data.ui_table_palette.get(key, ""))
		if hex != "":
			return Color(hex)
	return fallback

## A bottom-bar tab's bookmark colour (data/ui_bookmarks.csv).
static func bookmark_color(tab: String) -> Color:
	if Game != null and Game.data != null:
		var hex := String(Game.data.ui_bookmarks.get(tab, ""))
		if hex != "":
			return Color(hex)
	return BORDER_GOLD

## The INK a left-column card writes in, by role: on the war table the column
## is paper, so dark ink (ui_table_palette.csv); otherwise the leather's light
## ink. Roles: soft (body), muted (labels), dim (hints), accent (names, the
## title), rubric (section headers), track / fill (a bar), good / bad.
static func ink(role: String) -> Color:
	if war_table():
		match role:
			"soft": return table_color("ink", TEXT_SOFT)
			"muted": return table_color("ink_muted", TEXT_MUTED)
			"dim": return table_color("ink_dim", TEXT_DIM)
			"accent", "rubric": return table_color("rubric", GOLD)
			"track": return table_color("track", TROUGH)
			"fill": return table_color("fill", GOLD)
			"good": return table_color("good", POSITIVE)
			"bad": return table_color("bad", NEGATIVE)
	match role:
		"soft": return TEXT_SOFT
		"muted": return TEXT_MUTED
		"dim": return TEXT_DIM
		"accent", "rubric": return GOLD
		"track": return chart_color("track") if Game != null and Game.data != null and Game.data.chart_palette.has("track") else TROUGH
		"fill": return chart_color("sequential") if Game != null and Game.data != null and Game.data.chart_palette.has("sequential") else GOLD
		"good": return good_color()
		"bad": return bad_color()
	return TEXT_SOFT

## A skill's colour: data/chart_palette.csv skill_<key> (owner 2026-09-28: the
## colours are data, muted to the heraldic set), SKILL_COLORS the fallback.
static func skill_color(sk: String) -> Color:
	return _chart_or("skill_" + sk, SKILL_COLORS.get(sk, TEXT_MUTED))

## Dossier SKILLS-tab tool colors (user request 2026-08-31): the accent for a
## seat's kingdom operations, teal for person-to-person tools, so the two
## kinds read apart at a glance.
const TOOL_KINGDOM := GOLD
const TOOL_PERSONAL := Color("4cc3b0")  # (bright: 13897b)

## OFL-licensed faces (assets/fonts/, licenses alongside), divided by job.
## Which file plays which role is data/ui_fonts.csv (see role_font below); the
## owner's pick of 2026-09-28 is Crimson Pro for everything read, Alegreya SC
## for headers and tabs, and the blackletter only for titles. These paths are
## the 2026-09-13 set (scheme 0), used only when no table is loaded.
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
const MAP_BACKDROP_PATH := "res://assets/2D/portraits/cast/full/map_example.jpeg"
const MAP_EDGE_CROP := 34.0

## Decorative screen frame (two kings at a chess game, user-provided art;
## tools/key_frame_interior.py produced the real-alpha PNG). Drawn above the
## map backdrop, below the UI panels, on every screen.
const FRAME_PATH := "res://assets/2D/ui/panels/frame.png"

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
	style.bg_color = TROUGH
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
const PANEL_ART_PATH := "res://assets/2D/ui/panels/panel_vellum.png"
## The border-and-ornament band, in the plate's own pixels.
const PANEL_ART_SOURCE_INSET := 75.0
## The same band as drawn on screen, in design px.
const PANEL_ART_INSET := 40.0
## Rounded corners on the flat panels and chips, in design px. Tighter than the
## bright theme's 10 / 6: CK3's frames are cut, not pillowed.
const PANEL_RADIUS := 4
const CHIP_RADIUS := 3

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
## rule, the hairline and the corner flourishes. Drawn over the card in
## ORNAMENT_TINT, since its own dark ink cannot be seen on the dark theme.
const PANEL_ORNAMENT_PATH := "res://assets/2D/ui/panels/panel_ornament.png"

static func panel_ornament_enabled() -> bool:
	if Game == null or Game.data == null or not Game.data.balance.has("ui_panel_ornament"):
		return false
	return Game.data.bal("ui_panel_ornament") > 0.0

## A card: dark leather body, a thin trim in `border`, cut corners and a deep
## drop shadow — framed by the gold ornament when ui_panel_ornament is on and
## the art loads.
## `kind` says where the panel stands, which decides whether it wears the
## ornament (balance ui_panel_ornament: 1 every panel, 2 windows and the
## columns and bars but not the map's frame, 3 floating windows only — owner
## 2026-09-28: one ornament per layer, never a frame inside a frame):
## "window" floats over the screen (the audience window, popups, menus),
## "column" is a side column or the top and bottom bars, "map" frames the map.
static func panel_style(border: Color, border_width: int = 2,
		margin: int = 12, kind := "window") -> StyleBox:
	if panel_art_enabled():
		var art := panel_art_style(margin)
		if art != null:
			return art
	var card := _card_style(border, border_width, margin)
	var framed := VellumPanelStyle.new()
	framed.base = card
	_dress(framed)
	framed.set_content_margin_all(float(margin))
	var tex := load_art(PANEL_ORNAMENT_PATH) if _wears_ornament(kind) else null
	if tex != null:
		framed.texture = tex
		framed.tint = ORNAMENT_TINT
		framed.source_inset = PANEL_ART_SOURCE_INSET
		framed.draw_inset = PANEL_ART_INSET
		# Text keeps clear of the rules, as the vellum plate's floor did.
		framed.set_content_margin_all(maxf(float(margin), PANEL_ART_INSET * 0.25))
	elif kind != "map":
		# The map's own edge frames it: a hairline there stacked with the
		# columns' into a run of parallel gold lines along the gutter.
		framed.inner_rule = Color(BORDER_GOLD, _bal_or("ui_panel_inner_rule_alpha", 0.0))
		framed.inner_inset = _bal_or("ui_panel_inner_rule_inset_px", 4.0)
	return framed

static func _wears_ornament(kind: String) -> bool:
	if not panel_ornament_enabled():
		return false
	var scope := int(_bal_or("ui_panel_ornament", 1.0))
	match scope:
		1:
			return true
		2:
			return kind != "map"
		_:
			return kind == "window"

## The card's material, every number balance ui_panel_*.
static func _dress(style: VellumPanelStyle) -> void:
	style.grain_alpha = _bal_or("ui_panel_grain_alpha", 0.0)
	if style.grain_alpha > 0.0:
		var grain := panel_grain()
		style.grain = grain[0]
		style.grain_dark = grain[1]
		style.grain_px = _bal_or("ui_panel_grain_px", 1.0)
	style.shade_top = _bal_or("ui_panel_shade_top", 0.0)
	style.shade_bottom = _bal_or("ui_panel_shade_bottom", 0.0)

static func _bal_or(key: String, fallback: float) -> float:
	if Game == null or Game.data == null or not Game.data.balance.has(key):
		return fallback
	return Game.data.bal(key)

## A seamless leather grain, made once: a low mottle and a fine tooth mixed
## (balance ui_panel_grain_freq, ui_panel_grain_tooth the tooth's frequency
## over it, ui_panel_grain_mottle the mottle's share). It is TWO textures — white where the grain rises above its mean,
## black where it falls below, each its alpha — so laying them over a card
## neither lifts it nor greys it (a grey noise laid over the dark leather
## greyed it toward slate). Procedural, so no art file; fixed seeds.
static func panel_grain() -> Array[Texture2D]:
	if _art_cache.has("panel_grain"):
		return _art_cache["panel_grain"]
	var size := 256
	var mottle := FastNoiseLite.new()
	mottle.seed = 1409
	mottle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mottle.fractal_type = FastNoiseLite.FRACTAL_FBM
	mottle.fractal_octaves = 4
	mottle.frequency = _bal_or("ui_panel_grain_freq", 0.02)
	var tooth := FastNoiseLite.new()
	tooth.seed = 2203
	# Simplex, not cellular: cellular's distance field joined into a crack
	# network and the card read as veined marble.
	tooth.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tooth.frequency = mottle.frequency * _bal_or("ui_panel_grain_tooth", 12.0)
	var share := _bal_or("ui_panel_grain_mottle", 0.4)
	var a := mottle.get_seamless_image(size, size, false, false, 0.1, true)
	var b := tooth.get_seamless_image(size, size, false, false, 0.1, true)
	var light := Image.create(size, size, false, Image.FORMAT_LA8)
	var dark := Image.create(size, size, false, Image.FORMAT_LA8)
	for y in size:
		for x in size:
			var v := a.get_pixel(x, y).r * share + b.get_pixel(x, y).r * (1.0 - share)
			var d := (v - 0.5) * 2.0
			light.set_pixel(x, y, Color(1, 1, 1, clampf(d, 0.0, 1.0)))
			dark.set_pixel(x, y, Color(0, 0, 0, clampf(-d, 0.0, 1.0)))
	var out: Array[Texture2D] = []
	for img: Image in [light, dark]:
		img.generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))
	_art_cache["panel_grain"] = out
	return out

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
	if style is VellumPanelStyle and (style as VellumPanelStyle).texture != null:
		style.content_margin_left = maxf(style.content_margin_left, ORNAMENT_CLEAR_H)
		style.content_margin_right = maxf(style.content_margin_right, ORNAMENT_CLEAR_H)
		style.content_margin_top = maxf(style.content_margin_top, ORNAMENT_CLEAR_V)
		style.content_margin_bottom = maxf(style.content_margin_bottom, ORNAMENT_CLEAR_V)
	return style

## A button's four looks, one set for the theme, the compact buttons and the
## tabs: the chip at rest, lit and gold-edged under the cursor or held, and
## sunk into the card when disabled.
static func button_looks() -> Dictionary:
	return {"normal": chip_style(), "hover": chip_style(CHIP_HOVER, GOLD),
		"pressed": chip_style(CHIP_PRESSED, GOLD),
		"disabled": chip_style(PANEL_BG, Color(EDGE, 0.6))}

## A tab without a box (owner 2026-09-28, after the UI critique: a boxed tab
## inside the bar's own rules was a frame inside a frame): the word alone, a
## gold rule under it on hover, a thicker one while it is lit.
static func flat_tab(button: Button, size: int, pad := 10.0) -> void:
	style_tab(button, size)
	var looks := {}
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.content_margin_left = pad
		box.content_margin_right = pad
		box.content_margin_top = 4.0
		box.content_margin_bottom = 4.0
		looks[state] = box
	(looks["hover"] as StyleBoxFlat).border_color = Color(GOLD, 0.45)
	(looks["hover"] as StyleBoxFlat).border_width_bottom = 1
	for lit: String in ["pressed", "hover_pressed"]:
		(looks[lit] as StyleBoxFlat).border_color = GOLD
		(looks[lit] as StyleBoxFlat).border_width_bottom = 2
	for state: String in looks:
		button.add_theme_stylebox_override(state, looks[state])
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_hover_pressed_color", GOLD)

## The screen's one PRIMARY action (owner 2026-09-28: ENTER THE COUNCIL, the
## game's core move, was the least visible thing on the screen): gold ink on
## a warm dark ground in a gold rule, brighter under the cursor.
static func primary_button(button: Button, size: int) -> void:
	style_tab(button, size)
	var rest := chip_style(Color("54401f"), GOLD)
	var hover := chip_style(Color("674e27"), Color("f3d99a"))
	var pressed := chip_style(Color("735830"), Color("f3d99a"))
	for box: StyleBoxFlat in [rest, hover, pressed]:
		box.content_margin_left = 16.0
		box.content_margin_right = 16.0
		box.content_margin_top = 6.0
		box.content_margin_bottom = 6.0
		box.shadow_color = SHADOW
		box.shadow_size = 6
	button.add_theme_stylebox_override("normal", rest)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color("f3d99a"))
	button.add_theme_color_override("font_hover_color", Color("fff0c8"))
	button.add_theme_color_override("font_pressed_color", Color("f3d99a"))

## A COMMAND (owner 2026-09-28, second critique: "Start Game", "ASK THE
## COUNCIL" and "Wave them on" were three rules): a verb the player gives —
## as against an option or reply, which is a sentence he says and stays in
## the book face — is set in the tab's tracked small capitals, in title case
## whatever case it was written in. `size` 0 keeps the button's size.
## ui_command_style 0 leaves every button as it was written.
static func command_button(button: Button, size: int = 0) -> void:
	if Game != null and Game.data != null and Game.data.bal("ui_command_style") <= 0.0:
		return
	if size > 0:
		button.add_theme_font_size_override("font_size", size)
	var font := tab_font()
	if font != null:
		button.add_theme_font_override("font", font)
	button.text = command_text(button.text)

## "ASK THE COUNCIL" / "ask the council" -> "Ask the Council"; "BUY — 3508
## gold" -> "Buy — 3,508 Gold"; a word with a figure in it ("20g", "5d") is
## left as written but for its grouping.
static func command_text(text: String) -> String:
	var small := ["of", "the", "and", "a", "an", "as", "by", "in", "on", "to", "at", "or", "for", "from", "with"]
	var words := text.split(" ")
	for i in words.size():
		var w: String = words[i]
		if w == "":
			continue
		if w.is_valid_int():
			words[i] = format_int(w.to_int())
			continue
		var has_digit := false
		for c in w:
			if c >= "0" and c <= "9":
				has_digit = true
				break
		if has_digit:
			continue
		var lw := w.to_lower()
		# A small word stays small but first and last (title case).
		var inner := i > 0 and i < words.size() - 1
		words[i] = lw if inner and small.has(lw) else lw.substr(0, 1).to_upper() + lw.substr(1)
	return " ".join(words)

## A small button that sits in a strip without stretching to the strip's
## height: tight padding, a fixed height, centred in its row.
static func compact_button(button: Button, height: float, font_px: int, pad: float = 6.0) -> void:
	button.add_theme_font_size_override("font_size", font_px)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(button.custom_minimum_size.x, height)
	var looks := button_looks()
	for state: String in looks:
		var box: StyleBoxFlat = looks[state]
		box.content_margin_left = pad
		box.content_margin_right = pad
		box.content_margin_top = 1.0
		box.content_margin_bottom = 1.0
		button.add_theme_stylebox_override(state, box)

## CK3's options (owner 2026-09-15): a full-width dark bar, text from the left,
## a gold rule down its left edge that brightens and thickens under the
## cursor. Used for the audience window's replies and event choices.
static func option_button(button: Button) -> void:
	var rest := chip_style(Color("241d17"), EDGE)
	var hover := chip_style(CHIP_HOVER, GOLD)
	var pressed := chip_style(CHIP_PRESSED, GOLD)
	for box: StyleBoxFlat in [rest, hover, pressed]:
		box.content_margin_left = 14.0
		box.content_margin_right = 12.0
		box.content_margin_top = 7.0
		box.content_margin_bottom = 7.0
	rest.border_width_left = 3
	rest.border_color = Color(BORDER_GOLD, 0.7)
	hover.border_width_left = 5
	pressed.border_width_left = 5
	button.add_theme_stylebox_override("normal", rest)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT_SOFT)
	button.add_theme_color_override("font_hover_color", GOLD)

static func _card_style(border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = border
	style.set_border_width_all(mini(border_width, 1) if border_width > 0 else 0)
	style.set_corner_radius_all(PANEL_RADIUS)
	style.shadow_color = SHADOW
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
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
		_art_lru.erase(path)
		_art_lru.append(path)
		return _art_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	_art_cache[path] = tex
	_keep_art(path, tex)
	return tex


## The art load_art keeps, least recently asked first, and its bytes: every
## portrait, painting and icon a session ever drew stayed in video memory
## (perf 2026-10-02, up to ~330 MB). Past ui_art_cache_mb the oldest go; one
## still on screen lives on through its own references, and asked again it
## is loaded again.
static var _art_lru: Array[String] = []
static var _art_bytes: Dictionary = {}
static var _art_total := 0


static func _keep_art(path: String, tex: Texture2D) -> void:
	var bytes := tex.get_width() * tex.get_height() * 4 if tex != null else 0
	_art_bytes[path] = bytes
	_art_total += bytes
	_art_lru.append(path)
	var cap := int(_bal_or("ui_art_cache_mb", 160.0) * 1048576.0)
	while _art_total > cap and _art_lru.size() > 1:
		var old: String = _art_lru.pop_front()
		_art_total -= int(_art_bytes.get(old, 0))
		_art_bytes.erase(old)
		_art_cache.erase(old)

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

## The faces are data (owner 2026-09-28, after the UI critique): balance
## ui_font_scheme picks a scheme of data/ui_fonts.csv, one row per role —
## title (the game's name, window and screen titles, the map's kingdom names),
## header (section headers, names, the date), body (the theme default and the
## transcript) with its bold and italic, tab, display (the scale bar, ruler,
## landmark metres, shield letters). The constants above are the fallback when
## no table is loaded (scheme 0 restates them).
const FONT_DIR := "res://assets/fonts/"
const _FALLBACK_FONTS := {
	"title": TITLE_FONT_PATH, "header": TITLE_FONT_PATH, "body": CONTENT_FONT_PATH,
	"body_bold": CONTENT_FONT_PATH, "body_italic": CONTENT_FONT_PATH,
	"tab": TAB_FONT_PATH, "display": MAP_FONT_PATH,
}

## The ui_fonts.csv row for a role under the current scheme, or {}.
static func font_row(role: String) -> Dictionary:
	if Game == null or Game.data == null or Game.data.ui_fonts.is_empty():
		return {}
	var scheme := 0
	if Game.data.balance.has("ui_font_scheme"):
		scheme = int(Game.data.bal("ui_font_scheme"))
	return Game.data.ui_fonts.get("%d:%s" % [scheme, role], {})

## The face for a role: the file, with its weight, embolden, slant and
## tracking applied as a FontVariation when the row asks for any.
static func role_font(role: String) -> Font:
	var row := font_row(role)
	if row.is_empty():
		if role == "body_bold":
			return _varied(_load_font(CONTENT_FONT_PATH), "fb:bold", 0, 0.7, 0.0, 0)
		if role == "body_italic":
			return _varied(_load_font(CONTENT_FONT_PATH), "fb:italic", 0, 0.0, 0.2, 0)
		return _load_font(String(_FALLBACK_FONTS.get(role, CONTENT_FONT_PATH)))
	var path := FONT_DIR + String(row["path"])
	var weight := int(float(row.get("weight", "0")))
	var embolden := float(row.get("embolden", "0"))
	var slant := float(row.get("slant", "0"))
	var spacing := int(float(row.get("spacing", "0")))
	var features := String(row.get("features", ""))
	var key := "%s|%d|%s|%s|%d|%s" % [path, weight, embolden, slant, spacing, features]
	return _varied(_load_font(path), key, weight, embolden, slant, spacing, features)

## `features` is OpenType feature tags joined by | turned on (lnum: lining
## figures, so a 0 in a column of numbers never reads as an o).
static func _varied(base: Font, key: String, weight: int, embolden: float,
		slant: float, spacing: int, features: String = "") -> Font:
	if base == null or (weight == 0 and embolden == 0.0 and slant == 0.0
			and spacing == 0 and features == ""):
		return base
	if _art_cache.has(key):
		return _art_cache[key]
	var font := FontVariation.new()
	font.base_font = base
	if weight > 0:
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	font.variation_embolden = embolden
	if slant != 0.0:
		font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(slant, 1.0), Vector2.ZERO)
	font.spacing_glyph = spacing
	var tags := {}
	for tag in features.split("|", false):
		tags[TextServerManager.get_primary_interface().name_to_tag(tag)] = 1
	font.opentype_features = tags
	_art_cache[key] = font
	return font

## A role's size multiplier (blackletter reads a size small).
static func role_scale(role: String) -> float:
	var row := font_row(role)
	if row.is_empty():
		return TITLE_SIZE_SCALE if role == "title" or role == "header" else 1.0
	return float(row.get("size_scale", "1"))

static func _role_title_case(role: String) -> bool:
	var row := font_row(role)
	if row.is_empty():
		return role == "title" or role == "header"
	return int(float(row.get("title_case", "0"))) == 1

## Window and screen titles, the game's name.
static func title_font() -> Font:
	return role_font("title")

## Section headers, names, the date.
static func header_font() -> Font:
	return role_font("header")

## Tab buttons.
static func tab_font() -> Font:
	return role_font("tab")

## The kingdom names lettered across the map.
static func map_label_font() -> Font:
	return title_font()

## Dialogue, options, long text — and the theme default.
static func content_font() -> Font:
	return role_font("body")

static func content_bold_font() -> Font:
	return role_font("body_bold")

static func content_italic_font() -> Font:
	return role_font("body_italic")

## What text drawn by hand uses: numbers on map counters and badges, chart
## labels. The content face, so they match the panels around them.
static func body_font() -> Font:
	return content_font()

## Values in a column (owner 2026-09-28, second critique): the body face in
## tabular lining figures, so a right-aligned column reads straight down.
static func figures_font() -> Font:
	return role_font("figures")

## The scale bar's distance, the ruler, landmark metres, the shield's letters.
static func display_font() -> Font:
	return role_font("display")

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

## A whole number with its thousands grouped ("13,272"; owner 2026-09-28:
## "13272" beside "179k" read as two different kinds of figure).
static func format_int(v: int) -> String:
	var digits := str(absi(v))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if v < 0 else "") + digits + out

## A change with its sign and grouping ("+1,597").
static func format_delta(v: int) -> String:
	return ("+" if v >= 0 else "-") + format_int(absi(v))

static func title_size(size: int, role: String = "header") -> int:
	return int(round(float(size) * role_scale(role)))

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

## Title treatment: the title face (blackletter) in the accent — the game's
## name, window and screen titles only (owner 2026-09-28: a blackletter on
## every header was the template look).
static func style_title(label: Label, size: int, color: Color = GOLD) -> void:
	_style_role(label, size, color, "title")

## Header treatment: the header face in the accent (or the given color) — for
## speaker names, dates, section headers, card titles.
static func style_header(label: Label, size: int, color: Color = GOLD) -> void:
	_style_role(label, size, color, "header")

## A section header inside a card ("Temper of the Realm", "The Record"): the
## header face, muted, over a faint gold rule the width of the column (owner
## 2026-09-28: sections read as one run of text; balance
## ui_section_rule_alpha, 0 draws no rule).
static func style_section(label: Label, size: int, color: Color = TEXT_MUTED) -> void:
	style_header(label, size, color)
	var alpha := _bal_or("ui_section_rule_alpha", 0.0)
	if alpha <= 0.0:
		return
	var rule := StyleBoxFlat.new()
	rule.bg_color = Color(0, 0, 0, 0)
	rule.border_color = Color(BORDER_GOLD, alpha)
	rule.border_width_bottom = 1
	rule.content_margin_bottom = _bal_or("ui_section_rule_gap_px", 3.0)
	rule.content_margin_top = _bal_or("ui_section_rule_gap_px", 3.0)
	label.add_theme_stylebox_override("normal", rule)

## A section header in a left-column card: on THE WAR TABLE the report's red
## rubric — "¶ " before the words, a faint ink rule under them; otherwise
## style_section. `label.text` must be set first.
static func style_rubric(label: Label, size: int) -> void:
	if not war_table():
		style_section(label, size)
		return
	if not label.text.begins_with("¶"):
		label.text = "¶ " + label.text
	style_section(label, size, ink("rubric"))
	var rule := label.get_theme_stylebox("normal") as StyleBoxFlat
	if rule != null:
		rule.border_color = Color(ink("muted"), 0.45)

static func _style_role(label: Label, size: int, color: Color, role: String) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", title_size(size, role))
	var font := role_font(role)
	if font != null:
		label.add_theme_font_override("font", font)
		if _role_title_case(role):
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
	var looks := button_looks()
	for state: String in looks:
		var box: StyleBoxFlat = looks[state]
		box.content_margin_left = pad
		box.content_margin_right = pad
		button.add_theme_stylebox_override(state, box)

## Game-wide Theme, applied once at GameRoot and inherited by every screen:
## the content face in light ink at a compact size, dark cut buttons and
## sunk inputs.
static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", TEXT_SOFT)
	theme.set_color("font_color", "Button", TEXT_SOFT)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", GOLD)
	var looks := button_looks()
	for state: String in looks:
		theme.set_stylebox(state, "Button", looks[state])
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_stylebox("normal", "LineEdit", chip_style(INPUT_BG))
	theme.set_stylebox("focus", "LineEdit", chip_style(INPUT_BG, GOLD))
	theme.set_color("font_color", "LineEdit", TEXT_SOFT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_constant("line_spacing", "Label", LINE_SPACING)
	# The transcript is a RichTextLabel, whose ink is NOT the Label colour:
	# left unset it was Godot's default white (owner report 2026-09-13).
	theme.set_color("default_color", "RichTextLabel", TEXT_SOFT)
	var body_px := int(round(DIALOGUE_FONT_SIZE * role_scale("body")))
	theme.set_font_size("normal_font_size", "RichTextLabel", body_px)
	theme.set_font_size("bold_font_size", "RichTextLabel", body_px)
	theme.set_font_size("italics_font_size", "RichTextLabel", body_px)
	# Floating tooltips (user request 2026-09-09: icons explain themselves on
	# hover) in the same chip chrome as everything else.
	theme.set_stylebox("panel", "TooltipPanel", chip_style(PANEL_BG, BORDER_GOLD))
	theme.set_color("font_color", "TooltipLabel", TEXT_SOFT)
	theme.set_font_size("font_size", "TooltipLabel", 16)
	# Separators and scroll bars were Godot's light grey, drawn for a light card.
	var sep := StyleBoxLine.new()
	sep.color = EDGE
	sep.thickness = 1
	theme.set_stylebox("separator", "HSeparator", sep)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(BORDER_GOLD, 0.55)
	grabber.set_corner_radius_all(3)
	var track := StyleBoxFlat.new()
	track.bg_color = TROUGH
	track.set_corner_radius_all(3)
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, track)
		theme.set_stylebox("grabber", bar, grabber)
		theme.set_stylebox("grabber_highlight", bar, grabber)
		theme.set_stylebox("grabber_pressed", bar, grabber)
	var body := content_font()
	if body != null:
		theme.default_font = body
		theme.set_font("normal_font", "RichTextLabel", body)
		theme.set_font("bold_font", "RichTextLabel", content_bold_font())
		theme.set_font("italics_font", "RichTextLabel", content_italic_font())
	theme.default_font_size = int(round(BODY_FONT_SIZE * role_scale("body")))
	return theme
