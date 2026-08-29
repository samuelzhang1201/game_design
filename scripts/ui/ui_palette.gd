class_name UiPalette
extends RefCounted
## Single source of UI colors and shared styles (architecture review,
## 2026-08-29: the same hex values were re-declared in four screens).
## Screens own their structure; every color and panel style comes from here.
## Stateless statics on purpose - no autoload, no tree presence needed.

const BG_STAGE := Color("161020")      # conversation backdrop
const BG_SCREEN := Color("1a1423")     # menu / court / day-run backdrop
const PANEL_BG := Color("241c33")
const GOLD := Color("deba54")          # accents: speaker names, card border, dates
const BORDER_MUTED := Color("8c86a0")  # dialogue border, secondary text
const TEXT_DIM := Color("5c5670")      # de-emphasized hints ("click to skip")
const TEXT_SOFT := Color("b8b2c8")     # news lines
const POSITIVE := Color("7fd47f")      # metric gains, opinion up
const NEGATIVE := Color("d47f7f")      # metric losses, opinion down
const DIM_OVERLAY := Color(0.05, 0.03, 0.09, 0.82)

const PIXEL_FONT_PATH := "res://assets/fonts/pixel.ttf"  # optional; default font otherwise

static func panel_style(border: Color, border_width: int = 2,
		margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(margin)
	return style

## Game-wide Theme, applied once at GameRoot and inherited by every screen.
## Picks up the optional pixel font when present (previously court-only,
## which would have made the screens inconsistent the day the font landed).
static func build_theme() -> Theme:
	var theme := Theme.new()
	if FileAccess.file_exists(PIXEL_FONT_PATH):
		var font: Font = load(PIXEL_FONT_PATH)
		if font != null:
			theme.default_font = font
			theme.default_font_size = 16
	return theme
