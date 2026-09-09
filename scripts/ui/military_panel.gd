class_name MilitaryPanel
extends VBoxContainer
## The MILITARY tab (user request 2026-09-09): the realm's host by arm with
## an icon per type and a bar for its size, every regiment with the arm it
## is mostly made of, and the neighbours' strength as far as it is commonly
## known. Engine truth through the ledger and the pack; refreshed on show.

const MAX_WIDTH := 300.0

var _summary: Label
var _arms: BarChart
var _regiments: BarChart
var _neighbours: BarChart
var _officers: Label

func _init() -> void:
	name = "MilitaryPanel"
	add_theme_constant_override("separation", 3)
	custom_minimum_size = Vector2(MAX_WIDTH, 0)
	_summary = Label.new()
	_summary.name = "Summary"
	_summary.add_theme_font_size_override("font_size", 8)
	add_child(_summary)
	_arms = _section("THE HOST BY ARM", "Arms")
	_regiments = _section("REGIMENTS", "Regiments")
	_neighbours = _section("NEIGHBOURS' STRENGTH, AS REPORTED", "Neighbours")
	_officers = Label.new()
	_officers.name = "Officers"
	_officers.add_theme_font_size_override("font_size", 7)
	_officers.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	_officers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_officers)

func _section(heading: String, chart_name: String) -> BarChart:
	var h := Label.new()
	h.text = heading
	UiPalette.style_header(h, 7, UiPalette.TEXT_MUTED)
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
		arm_rows.append({"label": _label(u), "value": counts[u], "icon": _glyph(u),
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
		var size := 0.0
		var main_arm := ""
		var main_n := -1.0
		for i in units.size():
			var u: String = units[i]
			var n := float(r.get(u, 0))
			size += n
			if n > main_n:
				main_n = n
				main_arm = u
		reg_top = maxf(reg_top, size)
		reg_rows.append({"label": _short(String(r["label"])), "value": size, "icon": _glyph(main_arm),
			"color": UiPalette.chart_color("cat_%d" % (units.find(main_arm) + 1)),
			"text": RealmDashboard._compact(size)})
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
	_officers.text = "\n".join(lines)

func _regiments_of(kingdom_code: String) -> Array:
	var out: Array = []
	for r: Dictionary in Game.data.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) == kingdom_code:
			out.append(r)
	return out

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
