class_name ManorMasterPanel
extends VBoxContainer
## The Manor Master (MANOR_SYSTEM.md §6, owner 2026-09-13): every manor on
## the map in one sortable table — name, house, value, and on hover its
## province, people, tax and buildings — in the LEFT column
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
## The house column's arms, design px (the table's 13 px text).
const ARMS_PX := 16

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
	var p: ManorMasterPanel = create()
	column.add_child(p)
	return p

## The table as the game makes it: scenes/panels/manor_master_panel.tscn (owner
## 2026-10-02: the look lives in the editor) — the table wears the theme's
## ManorTable kind, written in the column's ink — hidden until MANORS is lit.
static func create() -> ManorMasterPanel:
	return (load("res://scenes/panels/manor_master_panel.tscn") as PackedScene).instantiate()

func _ready() -> void:
	_title = $Title
	_summary = $Summary
	_scope = $Filters/Scope
	_scope.toggled.connect(func(on: bool) -> void: set_scope(on))
	_house = $Filters/House
	_house.item_selected.connect(func(index: int) -> void:
		set_house(String(_house.get_item_metadata(index))))
	_tree = $Table
	for i in COLUMNS.size():
		_tree.set_column_title(i, COLUMNS[i])
		_tree.set_column_expand(i, i != 2)
		_tree.set_column_clip_content(i, true)
	_tree.set_column_custom_minimum_width(2, 52)
	_tree.column_title_clicked.connect(func(column: int, _mouse: int) -> void: sort_by(column))
	_tree.item_selected.connect(func() -> void:
		var item := _tree.get_selected()
		if item != null:
			manor_chosen.emit(int(item.get_metadata(0))))
	_tree.item_activated.connect(func() -> void:
		var item := _tree.get_selected()
		if item != null:
			manor_activated.emit(int(item.get_metadata(0))))
	_scope_text()
	Game.report_ready.connect(func(_r: TickReport) -> void: _settled_frame = Engine.get_process_frames())
	Game.state_changed.connect(func() -> void:
		if visible:
			refresh())

func _scope_text() -> void:
	_scope.text = UiPalette.command_label("ALL REALMS" if _all else "THE REALM")

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

## Rebuild the rows from the live state — only when something the table
## shows can have moved (perf 2026-10-02: it was rebuilt every game day while
## MANORS was lit, 9-20 ms on that frame): the economy's own signature (the
## month, holdings, buildings, focus, idle works, ledger figures, borders,
## tax rates), the letters that lift the fog, DEV MODE, and the table's
## scope, filter and sort. Right after a month's settlement every line is
## cold; that read waits for the next frame, off the tick's own.
func refresh() -> void:
	if Game.state == null or Game.data == null:
		return
	var sig := [Game.state.get_instance_id(), RealmEconomy.realm_signature(Game.state),
		Game.state.next_missive_id, Intel.dev_all, _all, _house_filter, _sort_column, _sort_descending]
	if sig == _sig:
		return
	if not _read_now and is_inside_tree() and Engine.get_process_frames() == _settled_frame \
			and not RealmEconomy.is_warm(Game.data, Game.state):
		if not _waiting:
			_waiting = true
			get_tree().process_frame.connect(_refresh_later, CONNECT_ONE_SHOT)
		return
	_sig = sig
	rebuilds += 1
	_rebuild()


## What the rows were last built under (refresh()), and a test seam counting rebuilds.
var _sig: Array = []
var rebuilds := 0
var _waiting := false
var _read_now := false
## The frame a month was settled on (Game.report_ready): only then is a cold
## read left for the next frame.
var _settled_frame := -1


func _refresh_later() -> void:
	_waiting = false
	if is_inside_tree() and visible:
		_read_now = true
		refresh()
		_read_now = false


func _rebuild() -> void:
	var repo := Game.data
	var state := Game.state
	var realm := repo.resolve_realm("player_realm")
	var crown := MapManors.crown(state)
	var cells: Array = []
	if _all:
		cells = repo.manors.keys()
	else:
		for province: String in MapOwnership.provinces_of(repo, state, realm):
			cells.append_array(MapManors.manors_of_province(repo, province, Game.state))
	cells.sort()
	# Every row's month at once: one cached province read each, not a line
	# per row (the table is refreshed on every state_changed, and the map
	# scope is thousands of manors).
	var lines := RealmEconomy.lines_table(repo, state, cells)
	var houses: Dictionary = {}
	var table_rows: Array = []
	var crown_count := 0
	var rents := 0
	for cell: int in cells:
		var house := MapManors.owner_of(repo, state, cell)
		houses[house] = int(houses.get(house, 0)) + 1
		var crowns := house == crown
		if crowns:
			crown_count += 1
		var line: Dictionary = lines.get(cell, {})
		var rent := int(line.get("tax", 0))
		if crowns:
			rents += rent
		if _house_filter != "" and house != _house_filter:
			continue
		# The fog (Intel, spec 2026-09-28 §1): a row about land the crown does
		# not control shows no true people/rent/value — only what a letter has
		# said, or nothing. A subject built fresh, per row, since a manor's
		# own centre never moves.
		var subj := MissiveLog.subject("manor", MapManors.code_of(repo, cell),
			cell, MapTerrain.cell_center(repo, repo.cells[cell]))
		var full := Intel.level(repo, state, subj) == "full"
		var people_val := int(line.get("people", 0))
		var people_text := str(people_val) if full else String(Intel.fact(repo, state, subj, "people", people_val)["text"])
		var rent_shown: Variant = rent
		var value_shown: Variant = MapManors.value_of_line(repo, state, cell, line)
		if not full:
			var tax_est := Intel.estimate(repo, state, subj, "tax")
			rent_shown = String(tax_est["text"]) if not tax_est.is_empty() else "—"
			value_shown = "—"
		# No raw "people" int here (owner review, fix round 1): nothing but
		# people_text is ever read, and keeping the true figure around next to
		# the fogged text it is meant to replace invites exactly the leak this
		# task closes.
		table_rows.append({"cell": cell, "label": MapManors.label_of(repo, cell),
			"house": "The crown" if crowns else house, "family": house,
			"province": String(repo.provinces.get(MapManors.province_of(repo, cell, Game.state), {}).get("label", "")),
			"people_text": people_text, "rent": rent_shown,
			"value": value_shown, "full": full,
			"buildings": MapManors.buildings_of(state, cell).size(),
			"focus": String((repo.manor_focus.get(MapManors.focus_of(repo, state, cell), {}) as Dictionary).get("label", ""))})
	table_rows.sort_custom(_compare)
	var cap := int(repo.bal("manor_master_max_rows"))
	_left_out = maxi(table_rows.size() - cap, 0)
	_rows = table_rows.slice(0, cap)
	_fill_houses(houses, crown)
	_fill_tree()
	var scope := "the realm" if not _all else "the map"
	# Two figures side by side read as one ("holds 12, 364 gold", owner
	# 2026-09-28): each says what it counts.
	_summary.text = "%d manors in %s — the crown holds %d of them, for %s gold a month in taxes%s" % [
		cells.size(), scope, crown_count, UiPalette.format_int(rents),
		"; %d more than the table shows" % _left_out if _left_out > 0 else ""]

func _compare(a: Dictionary, b: Dictionary) -> bool:
	# A fogged row (Intel: not full) carries no true value to sort by, so it
	# always falls after every full row, whatever column or direction is
	# chosen (spec 2026-09-28 §1).
	var a_full := bool(a.get("full", true))
	var b_full := bool(b.get("full", true))
	if a_full != b_full:
		return a_full
	var less := false
	match _sort_column:
		0:
			less = String(a["label"]) < String(b["label"])
		1:
			less = String(a["house"]) < String(b["house"]) \
				or (String(a["house"]) == String(b["house"]) and _value_num(a) > _value_num(b))
		_:
			less = _value_num(a) < _value_num(b) \
				or (_value_num(a) == _value_num(b) and String(a["label"]) < String(b["label"]))
	return not less if _sort_descending else less

## The row's numeric value, or 0.0 for a fogged row whose "value" is text.
static func _value_num(r: Dictionary) -> float:
	var v: Variant = r["value"]
	return float(v) if (v is float or v is int) else 0.0

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
		# The holding house's arms before its name (owner 2026-09-15).
		var arms := HouseArms.texture_of_house(Game.data, Game.state, String(r["family"]))
		if arms != null:
			item.set_icon(1, arms)
			item.set_icon_max_width(1, ARMS_PX)
		item.set_text(2, _shown(r["value"]))
		item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_metadata(0, int(r["cell"]))
		var focus := String(r["focus"])
		var works := ("works %s" % focus.to_lower()) if focus != "" else "subsistence"
		var tip := "%s — %s\nPeople %s · tax %s gold a month · value %s gold\n%d building%s · %s" % [
			String(r["label"]), String(r["province"]), String(r["people_text"]), _shown(r["rent"]),
			_shown(r["value"]), int(r["buildings"]), "" if int(r["buildings"]) == 1 else "s",
			works]
		for i in COLUMNS.size():
			item.set_tooltip_text(i, tip)

## A fogged figure (Intel: "—", or an estimate's text) prints as itself; a
## true one rounds like the table always has.
static func _shown(v: Variant) -> String:
	return String(v) if v is String else UiPalette.format_int(roundi(float(v)))

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
