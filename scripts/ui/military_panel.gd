class_name MilitaryPanel
extends VBoxContainer
## The MILITARY tab (user request 2026-09-09): the realm's host by arm with
## an icon per type and a bar for its size, every regiment with the arm it
## is mostly made of, and the neighbours' strength as far as it is commonly
## known. Engine truth through the ledger and the pack; refreshed on show.
##
## It lives in the LEFT column (owner ruling 2026-09-10: the left column is
## the facts column) while the MILITARY layer is on, in place of the realm
## dashboard, with the regiments themselves drawn on the map beside it.

## CLOSE (owner 2026-09-27: opened from a regiment's card now the tab is gone).
signal closed

var _title: Label
var _summary: Label
var _arms: BarChart
var _regiments: BarChart
var _neighbours: BarChart
var _officers: Label

## Put the panel in a screen's left column, hidden until the tab lights it.
static func attach(column: BoxContainer) -> MilitaryPanel:
	var p := MilitaryPanel.new()
	p.visible = false
	column.add_child(p)
	return p

func _init() -> void:
	name = "MilitaryPanel"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.name = "Title"
	_title.text = "THE HOST"
	UiPalette.style_header(_title, 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_child(_title)
	var close := Button.new()
	close.name = "Close"
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close"
	close.pressed.connect(func() -> void: closed.emit())
	head.add_child(close)
	add_child(head)
	add_child(HSeparator.new())
	_summary = Label.new()
	_summary.name = "Summary"
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	# Short headings, and every one of them wraps: the left column is a fixed
	# 120 design px (ScreenLayout.LEFT_WIDTH) and a label that cannot wrap
	# sets a minimum width, which would push the column over the map.
	_arms = _section("BY ARM", "Arms")
	_regiments = _section("REGIMENTS", "Regiments")
	_neighbours = _section("NEIGHBOURS, AS REPORTED", "Neighbours")
	_officers = Label.new()
	_officers.name = "Officers"
	_officers.add_theme_font_size_override("font_size", 14)
	_officers.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	_officers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_officers)

func _ready() -> void:
	# The MILITARY table it replaced refreshed live while it was up; so does
	# this, so a battle or a muster shows in the column as it happens.
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

func refresh() -> void:
	if Game.state == null:
		return
	var data := Game.data
	var state := Game.state
	var mine := data.resolve_realm("player_realm")
	# By arm: one bar per unit type, its glyph in front, categorical colours in
	# the unit_types order.
	var units: Array = data.world_table("military", "unit_types").keys()
	var counts: Dictionary = {}
	var total := 0.0
	var top := 1.0
	for u: String in units:
		var v: Variant = WorldLedger.value_of(data, state, "military.kingdoms.%s.%s" % [mine, u])
		counts[u] = float(v) if v != null else 0.0
		total += counts[u]
		top = maxf(top, counts[u])
	var arm_rows: Array = []
	for i in units.size():
		var u: String = units[i]
		arm_rows.append({"label": _label(u), "value": counts[u], "dimension": u,
			"color": UiPalette.chart_color("cat_%d" % (i + 1)), "text": RealmDashboard._compact(counts[u])})
	_arms.set_rows(arm_rows, top)
	var strength: Variant = WorldLedger.value_of(data, state, "military.kingdoms.%s.strength" % mine)
	_summary.text = "%s under arms in %d regiments%s" % [RealmDashboard._compact(total),
		_regiments_of(mine).size(),
		("; strength %s" % RealmDashboard._compact(float(strength))) if strength != null else ""]
	# Regiments: a bar for each, its size, and the arm it is mostly made of.
	var reg_rows: Array = []
	var reg_top := 1.0
	for r: Dictionary in _regiments_of(mine):
		# The same arithmetic the map's markers use, so the bar here and the
		# bar under the marker read the same regiment the same way.
		var reg_size := MapObjects.regiment_size(data, r)
		var main_arm := MapObjects.regiment_arm(data, r)
		reg_top = maxf(reg_top, reg_size)
		reg_rows.append({"label": _short(String(r["label"])), "value": reg_size, "icon": _glyph(main_arm),
			"color": UiPalette.chart_color("cat_%d" % (units.find(main_arm) + 1)),
			"text": RealmDashboard._compact(reg_size)})
	reg_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"])
	_regiments.set_rows(reg_rows, reg_top)
	# Neighbours: what is commonly known — their totals, in their own colours.
	var nb_rows: Array = []
	var nb_top := 1.0
	for code: String in String(data.kingdoms[mine].get("neighbor_codes", "")).split("|", false):
		var theirs := 0.0
		for u: String in units:
			var v: Variant = WorldLedger.value_of(data, state, "military.kingdoms.%s.%s" % [code, u])
			theirs += float(v) if v != null else 0.0
		nb_top = maxf(nb_top, theirs)
		nb_rows.append({"label": String(data.kingdoms[code]["label"]), "value": theirs,
			"color": MapPalette.color_of(data, code), "text": RealmDashboard._compact(theirs)})
	nb_rows.append({"label": String(data.kingdoms[mine]["label"]), "value": total,
		"color": MapPalette.color_of(data, mine), "text": RealmDashboard._compact(total)})
	nb_top = maxf(nb_top, total)
	_neighbours.set_rows(nb_rows, nb_top)
	# Officers, as the old table listed them.
	var lines: Array[String] = []
	var marshal_id := String(state.council.get("marshal", ""))
	if state.characters.has(marshal_id):
		var m: Character = state.characters[marshal_id]
		lines.append("Marshal: %s (martial %d), army quality %d" % [m.display_name,
			int(m.skills["sk_martial"]), int(state.metrics["army_quality"])])
	var hale: Character = state.characters.get("char_captain_hale")
	if hale != null:
		lines.append("Guard captain: %s" % hale.display_name)
	# What the old MILITARY table said about the threat, kept when the table
	# gave way to this column (user request 2026-09-10).
	var osric: Character = state.characters.get("char_king_osric")
	if osric != null:
		lines.append("%s: hostile (%d)" % [data.realm_label("raider_realm"), osric.opinion])
	_officers.text = "\n".join(lines)

func _regiments_of(kingdom_code: String) -> Array:
	return MapObjects.regiments_of(Game.data, kingdom_code)

func _label(unit: String) -> String:
	return String((Game.data.resource_icons.get(unit, {}) as Dictionary).get("label", unit.capitalize()))

func _glyph(unit: String) -> String:
	return String((Game.data.resource_icons.get(unit, {}) as Dictionary).get("icon", ""))

## "3rd (Stotreso) Regiment" -> "3rd Stotreso".
static func _short(label: String) -> String:
	return label.replace(" Regiment", "").replace("(", "").replace(")", "")

## Test seams.
func arms_chart() -> BarChart:
	return _arms

func regiments_chart() -> BarChart:
	return _regiments

func neighbours_chart() -> BarChart:
	return _neighbours
