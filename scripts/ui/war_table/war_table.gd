class_name WarTable
extends RefCounted
## THE WAR TABLE (owner 2026-10-01, B3 + C1's bookmarks; spec
## docs/superpowers/specs/2026-10-01-war-table-ui-design.md): one place that
## lays a main screen on the table — the oak behind it, the map as a vellum
## sheet, the left column as the steward's pinned report. Every screen calls
## dress_screen once from _ready; with balance ui_war_table 0 it does nothing
## and the screen keeps its leather.

## Seeds for each surface's deckle (presentation only).
const SEED_SHEET := 11
const SEED_REPORT := 23
const SEED_SLIP := 37
const SEED_TAG := 41

## Lay `screen` on the table: `bg` its flat background, `map_panel` the map's
## panel, `column` the left facts column. True when the table is on.
static func dress_screen(screen: Control, bg: ColorRect, map_panel: PanelContainer,
		column: PanelContainer) -> bool:
	if not UiPalette.war_table():
		return false
	var table := WarTableBackdrop.install(screen, bg)
	# the table lies under everything the screen draws AND under the bookmarks
	# (z -1, GameRoot's), which lie under the papers: the sheet's edge and shadow
	# fall across the bookmarks' tops. z orders only the drawing; input still
	# follows the tree, so the bookmarks keep their clicks.
	bg.z_index = -2
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.z_index = -2
	map_panel.add_theme_stylebox_override("panel", sheet_style())
	column.add_theme_stylebox_override("panel", report_style())
	column.theme = paper_theme()
	column.set_meta("paper_ground", UiPalette.table_color("paper_ground", UiPalette.PANEL_BG))
	ink_column(column)
	return true

## The compass lies on the table, not on the map (owner 2026-10-01): below the
## report's drawn foot, where the news slip lay before it moved between the
## bookmark groups — sized to the band left there, never covered. `view` is the screen's map, which it turns north on a click.
static func place_compass(screen: Control, column: Control, view: Map3DView) -> TableCompass:
	if not UiPalette.war_table() or view == null:
		return null
	var c := TableCompass.new()
	c.view = view
	c.column = column
	screen.add_child(c)
	# over the column in the tree, so a press on the wheel reaches it where
	# the column's rect runs on below its drawn paper; it is never drawn over
	# the paper (TableCompass.fit keeps it below the drawn foot)
	screen.move_child(c, column.get_index() + 1)
	return c

## The map's vellum sheet: a deckled edge, two ink rules round the map.
static func sheet_style() -> PaperStyle:
	var s := PaperStyle.make("sheet", _num("ui_sheet_margin_px", 17.0), SEED_SHEET)
	s.rules = 2
	s.uv_inset = Vector2(0.075, 0.05)
	s.deckle_px = _num("ui_sheet_deckle_px", 4.0)
	s.rule_width = _num("ui_sheet_rule_px", 1.5)
	s.rule_gap = _num("ui_sheet_rule_gap_px", 4.0)
	s.rule_out = 3.0
	# a big sheet lies flat on the table: a short, close shadow (a long one
	# darkened the bookmarks hanging from under it)
	s.shadow_offset *= 0.4
	s.shadow_soft = 3.5
	return s

## The steward's report: paper turned ui_report_tilt_deg, pinned at its head.
static func report_style() -> PaperStyle:
	var s := PaperStyle.make("paper", _num("ui_report_margin_px", 22.0), SEED_REPORT)
	s.tilt_deg = _num("ui_report_tilt_deg", -1.2)
	s.pin = true
	s.content_margin_top = _num("ui_report_margin_px", 22.0) + _num("ui_pin_px", 12.0) * 0.6
	return s

## The report is paper only as tall as what is written on it while the
## realm's card holds the column (the table shows below it); a card that fills
## the column (a clicked place, the host) takes the whole sheet.
static func fit_report(column: PanelContainer, dashboard: RealmDashboard) -> void:
	var helper := _helper(column)
	if helper != null:
		helper.fit(dashboard)

## The column is paper, but its cards (MapDetailPanel, CountryPanel, the host,
## the Manor Master…) are shared with dark windows (the Missive board, the
## report popup) and write in the leather's light ink. Inside `column` only,
## every text colour that IS a leather ink is turned into its paper ink —
## TEXT_SOFT/MUTED/DIM to ink soft/muted/dim, GOLD to the rubric, a section
## header (style_section's ruled label) to the red rubric — as nodes arrive
## and whenever the column's content changes. Alpha is kept.
const INK_KEYS := ["font_color", "font_selected_color", "title_button_color", "default_color",
	"font_hover_color", "font_pressed_color"]

static func ink_column(column: Control) -> void:
	var helper := _helper(column)
	if helper != null:
		helper.ink()

## The node on a paper column that keeps its ink and its fitted height: a
## child of the column, so every signal it listens to (the tree's node_added
## among them) goes with the column when the column is freed.
static func _helper(column: Control) -> WarTablePaper:
	if column == null:
		return null
	var h := column.get_node_or_null("WarTablePaper") as WarTablePaper
	if h == null:
		h = WarTablePaper.new()
		h.name = "WarTablePaper"
		column.add_child(h, false, Node.INTERNAL_MODE_BACK)
	return h

static func _ink_node(n: Node) -> void:
	if n is Control:
		_ink_control(n as Control)
	for c in n.get_children():
		_ink_node(c)

static func _ink_control(c: Control) -> void:
	if not (c is Label or c is RichTextLabel or c is Tree or c is LinkButton):
		return
	var map := {UiPalette.TEXT_SOFT: "soft", UiPalette.TEXT_MUTED: "muted",
		UiPalette.TEXT_DIM: "dim", UiPalette.GOLD: "accent"}
	var section := false
	if c is Label:
		var rule := c.get_theme_stylebox("normal") as StyleBoxFlat
		section = rule != null and rule.border_width_bottom == 1 and rule.bg_color.a == 0.0 \
			and rule.border_color.is_equal_approx(Color(UiPalette.BORDER_GOLD, rule.border_color.a))
		if section:
			rule.border_color = Color(UiPalette.ink("muted"), 0.45)
	for key: String in INK_KEYS:
		if not c.has_theme_color_override(key):
			continue
		var col: Color = c.get_theme_color(key)
		for leather: Color in map:
			if Color(leather, col.a).is_equal_approx(col):
				var role: String = "rubric" if section else String(map[leather])
				c.add_theme_color_override(key, Color(UiPalette.ink(role), col.a))
				break

## A small paper (the news slip, the seal's tag): no pin, no tilt.
static func slip_style(margin: float, p_seed: int) -> PaperStyle:
	var s := PaperStyle.make("paper", margin, p_seed)
	# a small paper: the art's middle only (its ruled rim read as bars), and
	# a shadow that stays close to it
	s.uv_inset = Vector2(0.12, 0.08)
	s.shadow_soft = 2.0
	s.shadow_offset *= 0.45
	return s

## A Theme for everything that lies on paper: unstyled text in the paper's
## ink (a card's own overrides still win).
static func paper_theme() -> Theme:
	var t := Theme.new()
	var soft := UiPalette.ink("soft")
	t.set_color("font_color", "Label", soft)
	t.set_color("default_color", "RichTextLabel", soft)
	t.set_color("font_color", "LinkButton", UiPalette.ink("rubric"))
	# A tooltip floats OFF the paper, in the dark chip every tooltip wears —
	# but Godot looks its label up through the hovered control's theme first,
	# and TooltipLabel falls back to Label, so the paper's ink above drew it
	# dark on dark (owner 2026-10-01: 鼠标移动到icon上的tooltip字体完全看不见了).
	t.set_color("font_color", "TooltipLabel", UiPalette.TEXT_SOFT)
	return t

static func _num(key: String, fallback: float) -> float:
	if Game != null and Game.data != null and Game.data.balance.has(key):
		return Game.data.bal(key)
	return fallback
