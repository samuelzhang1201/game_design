class_name EconomyPanel
extends VBoxContainer
## The ECONOMY tab (owner request 2026-09-13): everything the realm produces,
## biggest first, with the category colour each good is filed under and the
## share of the realm's provinces that make it their chief trade.
##
## It lives in the LEFT column (owner ruling 2026-09-10: the left column is
## the facts column) while the ECONOMY layer is on, in place of the realm
## dashboard, beside the manor map — whose badges are ringed in the same
## category colours these bars use, so the column is the map's legend.
##
## Reads live: production follows the land, so a conquest moves output from
## one realm's column to another's with nothing to recompute by hand.

## The left column is a fixed height as well as a fixed width; both lists
## are capped so the panel fits inside the vellum plate rather than
## running out under its bottom ornament.
const MAX_GOODS := 10
const MAX_TRADES := 7

var _title: Label
var _summary: Label
var _goods: BarChart
var _categories: BarChart

## Put the panel in a screen's left column, hidden until the tab lights it.
static func attach(column: BoxContainer) -> EconomyPanel:
	var p := EconomyPanel.new()
	p.visible = false
	column.add_child(p)
	return p

func _init() -> void:
	name = "EconomyPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.name = "Title"
	_title.text = "WHAT YOUR LAND MAKES"
	UiPalette.style_header(_title, 16)
	# Every heading wraps: the left column is a fixed width and a label that
	# cannot wrap sets a minimum width, which would push it over the map.
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	add_child(HSeparator.new())
	_summary = Label.new()
	_summary.name = "Summary"
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_goods = _section("BY GOOD", "Goods")
	_categories = _section("BY TRADE", "Categories")

func _ready() -> void:
	Game.state_changed.connect(func() -> void:
		if visible:
			refresh())

func _section(heading: String, chart_name: String) -> BarChart:
	var h := Label.new()
	h.text = heading
	UiPalette.style_header(h, 14, UiPalette.TEXT_MUTED)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(h)
	var chart := BarChart.new()
	chart.name = chart_name
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(chart)
	return chart

## The colour a good's category wears, the same one its provinces wear on the
## map — the column and the map are one legend, not two.
static func tag_color(data: DataRepository, tag: String) -> Color:
	var hex := String(data.goods_palette.get(tag, ""))
	return Color(hex) if hex != "" else UiPalette.TEXT_MUTED

func refresh() -> void:
	if Game.state == null:
		return
	var data := Game.data
	# The crown's economy is the provinces it controls (owner 2026-09-13), not
	# the whole kingdom's.
	var controlled := MapManors.controlled_provinces(data, Game.state)
	var output := MapEconomy.output_of_provinces(data, controlled, Game.state)
	if output.is_empty():
		_summary.text = "The crown's land trades in nothing the ledgers record."
		_goods.set_rows([], 1.0)
		_categories.set_rows([], 1.0)
		return
	var total := 0.0
	var by_tag: Dictionary = {}
	for row: Dictionary in output:
		total += float(row["units"])
		var tag := MapEconomy.good_tag(data, String(row["good"]))
		by_tag[tag] = float(by_tag.get(tag, 0.0)) + float(row["units"])
	_summary.text = "%s of goods a year, in %d kinds across %d province%s the crown controls." % [
		RealmDashboard._compact(total), output.size(), controlled.size(),
		"" if controlled.size() == 1 else "s"]

	var rows: Array = []
	var top := 1.0
	for i in mini(output.size(), MAX_GOODS):
		var row: Dictionary = output[i]
		top = maxf(top, float(row["units"]))
		rows.append({"label": String(row["label"]), "value": float(row["units"]),
			"color": tag_color(data, MapEconomy.good_tag(data, String(row["good"]))),
			"text": RealmDashboard._compact(float(row["units"]))})
	_goods.set_rows(rows, top)

	var tags: Array = by_tag.keys()
	tags.sort_custom(func(a: String, b: String) -> bool:
		return float(by_tag[a]) > float(by_tag[b]))
	var cat_rows: Array = []
	var cat_top := 1.0
	for tag: String in tags.slice(0, MAX_TRADES):
		cat_top = maxf(cat_top, float(by_tag[tag]))
		cat_rows.append({"label": tag.capitalize(), "value": float(by_tag[tag]),
			"color": tag_color(data, tag), "text": RealmDashboard._compact(float(by_tag[tag]))})
	_categories.set_rows(cat_rows, cat_top)

## Test seams.
func goods_chart() -> BarChart:
	return _goods

func categories_chart() -> BarChart:
	return _categories

func summary_text() -> String:
	return _summary.text
