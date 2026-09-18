class_name InfoScreen
extends Control
## Centered table overlay for the bottom bar's REALM / LAWS / RELIGION /
## FAMILIES tabs: a titled two-column table of engine truth (metrics and
## office holders), refreshed live on state_changed while visible.
##
## MILITARY is no longer one of them (user request 2026-09-10): it is a map
## layer plus the host in the screen's left column, so it never dims the map.

var _title: Label
var _grid: GridContainer
var _current_tab := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = UiPalette.DIM_OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 2, 24))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(400, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.style_header(_title, 18)
	col.add_child(_title)
	col.add_child(HSeparator.new())
	_grid = GridContainer.new()
	_grid.name = "Table"
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 32)
	_grid.add_theme_constant_override("v_separation", 4)
	col.add_child(_grid)
	col.add_child(HSeparator.new())
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: hide())
	col.add_child(close)
	Game.state_changed.connect(func() -> void:
		if visible and _current_tab != "":
			_render())
	hide()

func show_tab(tab: String) -> void:
	_current_tab = tab
	_render()
	show()

func _render() -> void:
	if Game.state == null:
		return
	_title.text = _current_tab
	_grid.visible = true
	for child in _grid.get_children():
		child.queue_free()
	# Most tabs are a name/value pair; a tab that needs more (FAMILIES) says
	# so with a header row, and the grid widens to match.
	var headers := _headers_for(_current_tab)
	_grid.columns = headers.size() if not headers.is_empty() else 2
	if not headers.is_empty():
		for h: String in headers:
			var label := Label.new()
			label.text = h
			label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
			_grid.add_child(label)
	for row in _rows_for(_current_tab):
		_add_row_cells(row)

func _add_row_cells(row: Array) -> void:
	for i in row.size():
		var l := Label.new()
		l.text = String(row[i])
		if i == 0:
			l.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
		_grid.add_child(l)

## Column headings for tabs that are wider than name/value; [] for the rest.
func _headers_for(tab: String) -> Array:
	if tab == "FAMILIES":
		return ["House", "Members", "Seats", "Standing"]
	return []

func _seat_holder(seat: String) -> Character:
	var id := String(Game.state.council.get(seat, ""))
	return Game.state.characters.get(id)

## Table content per tab — all engine truth, nothing invented.
func _rows_for(tab: String) -> Array:
	var m: Dictionary = Game.state.metrics
	match tab:
		"REALM":
			var realm_rows := [
				["Treasury", "%d gold" % int(m["treasury"])],
				["Tax income", "%d / tick" % int(m["tax_income"])],
				["Grain", str(int(m["grain"]))],
				["Unrest", str(int(m["unrest"]))],
				["Legitimacy", str(int(m["legitimacy"]))],
				["Peasant contentment", str(int(m["peasant_contentment"]))],
				["Admin capacity", str(int(m["admin_capacity"]))],
			]
			# The pack's population, live through the ledger (spec 2026-09-09).
			for spec in [["Urban population", "urban_population"],
					["Rural population", "rural_population"]]:
				var v: Variant = WorldLedger.value_of(Game.data, Game.state,
					"economy.kingdoms.player_realm." + String(spec[1]))
				if v != null:
					realm_rows.append([String(spec[0]), str(int(v))])
			return realm_rows
		"FAMILIES":
			return _family_rows()
		"LAWS":
			return [
				["Tax rate", "%d / 10" % int(m["tax_rate"])],
				["Tariff rate", "%d / 10" % int(m["tariff_rate"])],
				["Grain rationing", "in force" if m["grain_ration"] > 0.0 else "none"],
			]
		"RELIGION":
			var rows2 := [["Church opinion", str(int(m["church_opinion"]))]]
			var chaplain := _seat_holder("chaplain")
			if chaplain != null:
				rows2.append(["Chaplain", "%s (piety %d)" %
					[chaplain.display_name, int(chaplain.attributes["piety"])]])
			var cassian: Character = Game.state.characters.get("char_prophet_cassian")
			if cassian != null:
				rows2.append(["Street preacher", "%s (%d)" %
					[cassian.display_name, cassian.opinion]])
			return rows2
		"WAR ROOM":
			# Owner 2026-09-17: a placeholder until the war room is designed.
			return [["War Room", "The war room is being prepared."]]
	return []

## The noble houses of the player's own realm, richest first, then by name so
## the order is stable. A house is a family_name shared by characters who live
## in the realm the pack binds player_realm to — no separate table to keep in
## step with the roster.
##
## Standing is the mean opinion of the members who have one; the player has no
## opinion of himself, so his own house shows "—" unless a relative is at
## court. Seats come from the live council, not from the roster's ambitions.
func _family_rows() -> Array:
	var realm := Game.data.resolve_realm("player_realm")
	var houses: Dictionary = {}
	for id: String in Game.state.characters:
		var c: Character = Game.state.characters[id]
		if c.kingdom != realm or c.family_name == "":
			continue
		if not houses.has(c.family_name):
			houses[c.family_name] = {"members": 0, "seats": [], "opinion": 0, "rated": 0}
		var h: Dictionary = houses[c.family_name]
		h["members"] = int(h["members"]) + 1
		if id != "you":
			h["opinion"] = int(h["opinion"]) + c.opinion
			h["rated"] = int(h["rated"]) + 1
		for seat: String in Game.state.council:
			if String(Game.state.council[seat]) == id:
				(h["seats"] as Array).append(seat.capitalize())
		if id == "you":
			(h["seats"] as Array).append("Crown")
	var names := houses.keys()
	names.sort()
	names.sort_custom(func(a, b): return int(houses[a]["members"]) > int(houses[b]["members"]))
	var rows: Array = []
	for house_name: String in names:
		var h: Dictionary = houses[house_name]
		var seats: Array = h["seats"]
		var rated := int(h["rated"])
		rows.append([house_name, str(int(h["members"])),
			", ".join(seats) if not seats.is_empty() else "—",
			"—" if rated == 0 else "%+d" % roundi(float(h["opinion"]) / float(rated))])
	return rows

## Test seams.
func current_tab() -> String:
	return _current_tab

func table() -> GridContainer:
	return _grid
