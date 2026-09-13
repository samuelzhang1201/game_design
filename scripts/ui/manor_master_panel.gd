class_name ManorMasterPanel
extends VBoxContainer
## The Manor Master (MANOR_SYSTEM.md §6, owner 2026-09-13): every manor on
## the map in one sortable table — name, house, value, and on hover its
## province, people, rent, buildings and production — in the LEFT column
## while the MANORS layer is lit, the way ECONOMY puts its panel there.
## Scope is the crown's realm by default (a few hundred rows) or the whole
## map; a house filter narrows it; the table is capped at
## manor_master_max_rows and says how many it left out. Clicking a row
## centres the map on the manor and rings it; activating (double click or
## Enter) opens its card. All engine truth, read live.

signal manor_chosen(cell: int)
signal manor_activated(cell: int)

const COLUMNS := ["Manor", "House", "Value"]
const TABLE_HEIGHT := 330.0

var _title: Label
var _summary: Label
var _scope: Button
var _house: OptionButton
var _tree: Tree
var _all := false
var _house_filter := ""
var _sort_column := 2
var _sort_descending := true
var _rows: Array = []
var _left_out := 0

static func attach(column: BoxContainer) -> ManorMasterPanel:
	var p := ManorMasterPanel.new()
	p.visible = false
	column.add_child(p)
	return p

func _init() -> void:
	name = "ManorMasterPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.name = "Title"
	_title.text = "THE MANORS"
	UiPalette.style_header(_title, 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	add_child(HSeparator.new())
	_summary = Label.new()
	_summary.name = "Summary"
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	var filters := HBoxContainer.new()
	filters.name = "Filters"
	filters.add_theme_constant_override("separation", 6)
	add_child(filters)
	_scope = Button.new()
	_scope.name = "Scope"
	_scope.toggle_mode = true
	_scope.focus_mode = Control.FOCUS_NONE
	_scope.add_theme_font_size_override("font_size", 13)
	_scope.tooltip_text = "The crown's realm, or every realm on the map"
	_scope.toggled.connect(func(on: bool) -> void: set_scope(on))
	filters.add_child(_scope)
	_house = OptionButton.new()
	_house.name = "House"
	_house.focus_mode = Control.FOCUS_NONE
	_house.add_theme_font_size_override("font_size", 13)
	_house.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The column is a fixed width: the longest house name must not set the
	# button's minimum, or it pushes the column over the map.
	_house.fit_to_longest_item = false
	_house.clip_text = true
	_house.custom_minimum_size = Vector2(90, 0)
	_house.item_selected.connect(func(index: int) -> void:
		set_house(String(_house.get_item_metadata(index))))
	filters.add_child(_house)
	_tree = Tree.new()
	_tree.name = "Table"
	_tree.columns = COLUMNS.size()
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.custom_minimum_size = Vector2(0, TABLE_HEIGHT)
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.add_theme_font_size_override("font_size", 13)
	_tree.add_theme_font_size_override("title_button_font_size", 12)
	for i in COLUMNS.size():
		_tree.set_column_title(i, COLUMNS[i])
		_tree.set_column_expand(i, i != 2)
		_tree.set_column_clip_content(i, true)
	_tree.set_column_custom_minimum_width(2, 52)
	_style_tree()
	_tree.column_title_clicked.connect(func(column: int, _mouse: int) -> void: sort_by(column))
	_tree.item_selected.connect(func() -> void:
		var item := _tree.get_selected()
		if item != null:
			manor_chosen.emit(int(item.get_metadata(0))))
	_tree.item_activated.connect(func() -> void:
		var item := _tree.get_selected()
		if item != null:
			manor_activated.emit(int(item.get_metadata(0))))
	add_child(_tree)
	_scope_text()

## The Tree wears the UI palette, not Godot's dark default: a light track
## for its body, muted headers, ink text, the accent for the chosen row.
func _style_tree() -> void:
	_tree.add_theme_stylebox_override("panel", UiPalette.bar_bg())
	_tree.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var head := StyleBoxFlat.new()
	head.bg_color = UiPalette.CHIP_BG
	head.border_color = UiPalette.EDGE
	head.set_border_width_all(1)
	head.set_content_margin_all(3)
	for state in ["title_button_normal", "title_button_pressed", "title_button_hover"]:
		_tree.add_theme_stylebox_override(state, head)
	var chosen := StyleBoxFlat.new()
	chosen.bg_color = Color(UiPalette.GOLD, 0.18)
	chosen.set_corner_radius_all(3)
	_tree.add_theme_stylebox_override("selected", chosen)
	_tree.add_theme_stylebox_override("selected_focus", chosen)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(UiPalette.GOLD, 0.08)
	_tree.add_theme_stylebox_override("hovered", hover)
	_tree.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_tree.add_theme_color_override("font_selected_color", UiPalette.TEXT_SOFT)
	_tree.add_theme_color_override("title_button_color", UiPalette.TEXT_MUTED)
	_tree.add_theme_color_override("guide_color", UiPalette.EDGE)
	_tree.add_theme_constant_override("v_separation", 2)
	_tree.add_theme_constant_override("draw_guides", 1)

func _ready() -> void:
	Game.state_changed.connect(func() -> void:
		if visible:
			refresh())

func _scope_text() -> void:
	_scope.text = "ALL REALMS" if _all else "THE REALM"

## The realm's manors or the map's.
func set_scope(all_realms: bool) -> void:
	_all = all_realms
	_scope.set_pressed_no_signal(_all)
	_scope_text()
	refresh()

func scope_all() -> bool:
	return _all

## Only one house's manors ("" for every house).
func set_house(family: String) -> void:
	_house_filter = family
	refresh()

func house_filter() -> String:
	return _house_filter

## Sort by a column; the same column again flips the order.
func sort_by(column: int) -> void:
	if column == _sort_column:
		_sort_descending = not _sort_descending
	else:
		_sort_column = column
		_sort_descending = column == 2
	refresh()

## Rebuild the rows from the live state.
func refresh() -> void:
	if Game.state == null or Game.data == null:
		return
	var repo := Game.data
	var state := Game.state
	var realm := repo.resolve_realm("player_realm")
	var crown := MapManors.crown(state)
	var cells: Array = []
	if _all:
		cells = repo.manors.keys()
	else:
		for province: String in MapOwnership.provinces_of(repo, state, realm):
			cells.append_array(MapManors.manors_of_province(repo, province))
	cells.sort()
	var people := MapManors.population_table(repo, state, cells)
	var houses: Dictionary = {}
	var rows: Array = []
	var crown_count := 0
	var rents := 0.0
	for cell: int in cells:
		var house := MapManors.owner_of(repo, state, cell)
		houses[house] = int(houses.get(house, 0)) + 1
		var crowns := house == crown
		if crowns:
			crown_count += 1
		var pop: float = (people[cell] as Dictionary)["total"]
		var rent := MapManors.rent_of(repo, state, cell, pop)
		if crowns:
			rents += rent
		if _house_filter != "" and house != _house_filter:
			continue
		rows.append({"cell": cell, "label": MapManors.label_of(repo, cell),
			"house": "The crown" if crowns else house, "family": house,
			"province": String(repo.provinces.get(MapManors.province_of(repo, cell), {}).get("label", "")),
			"people": pop, "rent": rent, "value": MapManors.base_value_of(repo, state, cell, pop),
			"buildings": MapManors.buildings_of(state, cell).size(),
			"output": MapManors.output_of(repo, cell),
			"focus": MapManors.focus_output_of(repo, state, cell, pop)})
	rows.sort_custom(_compare)
	var cap := int(repo.bal("manor_master_max_rows"))
	_left_out = maxi(rows.size() - cap, 0)
	_rows = rows.slice(0, cap)
	_fill_houses(houses, crown)
	_fill_tree()
	var scope := "the realm" if not _all else "the map"
	_summary.text = "%d manors in %s — the crown holds %d, %.1f gold a tick in rents%s" % [
		cells.size(), scope, crown_count, rents,
		"; %d more than the table shows" % _left_out if _left_out > 0 else ""]

func _compare(a: Dictionary, b: Dictionary) -> bool:
	var less := false
	match _sort_column:
		0:
			less = String(a["label"]) < String(b["label"])
		1:
			less = String(a["house"]) < String(b["house"]) \
				or (String(a["house"]) == String(b["house"]) and float(a["value"]) > float(b["value"]))
		_:
			less = float(a["value"]) < float(b["value"]) \
				or (float(a["value"]) == float(b["value"]) and String(a["label"]) < String(b["label"]))
	return not less if _sort_descending else less

func _fill_houses(houses: Dictionary, crown: String) -> void:
	_house.clear()
	_house.add_item("Every house")
	_house.set_item_metadata(0, "")
	var names: Array = houses.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return int(houses[a]) > int(houses[b]) or (int(houses[a]) == int(houses[b]) and a < b))
	var selected := 0
	for i in names.size():
		var family: String = names[i]
		_house.add_item("%s (%d)" % ["The crown" if family == crown else "House " + family, int(houses[family])])
		_house.set_item_metadata(i + 1, family)
		if family == _house_filter:
			selected = i + 1
	_house.select(selected)
	if selected == 0 and _house_filter != "":
		_house_filter = ""

func _fill_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	for r: Dictionary in _rows:
		var item := _tree.create_item(root)
		# The column is narrow and Cinzel wide: the table drops a trailing
		# "Manor" and says "Crown"; the tooltip carries every word.
		item.set_text(0, String(r["label"]).trim_suffix(" Manor"))
		item.set_text(1, "Crown" if String(r["house"]) == "The crown" else String(r["house"]))
		item.set_text(2, str(roundi(float(r["value"]))))
		item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_metadata(0, int(r["cell"]))
		var focus: Dictionary = r["focus"]
		var works := ("works %s, %d units a year" % [String(focus["label"]).to_lower(), roundi(float(focus["units"]))]) \
			if String(focus["focus"]) != "" else "subsistence"
		var tip := "%s — %s\nPeople %d · rent %.2f a tick · value %d gold\n%d building%s · %s%s" % [
			String(r["label"]), String(r["province"]), roundi(float(r["people"])), float(r["rent"]),
			roundi(float(r["value"])), int(r["buildings"]), "" if int(r["buildings"]) == 1 else "s",
			works, (" · town trade %d units" % roundi(float(r["output"]))) if float(r["output"]) > 0.0 else ""]
		for i in COLUMNS.size():
			item.set_tooltip_text(i, tip)

## Test seams.
func rows() -> Array:
	return _rows

func left_out() -> int:
	return _left_out

func summary_text() -> String:
	return _summary.text

func table() -> Tree:
	return _tree

func house_button() -> OptionButton:
	return _house

func scope_button() -> Button:
	return _scope

## Select a row by cell, as a click would.
func choose(cell: int) -> bool:
	var item := _tree.get_root().get_first_child() if _tree.get_root() != null else null
	while item != null:
		if int(item.get_metadata(0)) == cell:
			item.select(0)
			return true
		item = item.get_next()
	return false
