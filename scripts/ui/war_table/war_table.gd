class_name WarTable
extends RefCounted
## THE WAR TABLE (owner 2026-10-01, B3 + C1's bookmarks; spec
## docs/superpowers/specs/2026-10-01-war-table-ui-design.md): the oak, the
## map's vellum sheet, the steward's pinned report. Since 2026-10-02 the
## screens carry them in their scenes (scenes/court.tscn, conversation.tscn);
## what is left here is the paper column's live work (ink_column, fit_report)
## and the paper styles the unconverted pieces still make in code.

## Seeds for each surface's deckle (presentation only).
const SEED_SHEET := 11
const SEED_REPORT := 23
const SEED_SLIP := 37
const SEED_TAG := 41

## The map's vellum sheet and the steward's report: the scenes' own looks
## (assets/2D/ui/war_table/styles/, edited in the editor), a fresh copy each,
## for a piece that makes one in code (the landing's print, the WAR ROOM's
## card roll).
const SHEET_PATH := "res://assets/2D/ui/war_table/styles/map_sheet.tres"
const REPORT_PATH := "res://assets/2D/ui/war_table/styles/report_paper.tres"

static func sheet_style() -> PaperStyle:
	return (load(SHEET_PATH) as PaperStyle).duplicate()

static func report_style() -> PaperStyle:
	return (load(REPORT_PATH) as PaperStyle).duplicate()

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
	var repo := UiPalette.data()
	if repo != null and repo.balance.has(key):
		return repo.bal(key)
	return fallback
