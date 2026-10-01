class_name RealmDashboard
extends VBoxContainer
## The left column's default content (user ruling 2026-09-09): the player's
## own realm at a glance — resources as icons with tooltips, the temper of
## the realm as bars, the people as a pie, the host by unit type, and the
## largest provinces — all engine truth, refreshed on every state change.
## Charts follow the dataviz rules: thin marks, text in text ink, categorical
## colours in fixed order from data/chart_palette.csv.

const RESOURCES := ["treasury", "grain", "population", "army"]
## The army's drill joined the temper when the top bar gave up everything
## but the purses (owner 2026-09-14).
const TEMPER := ["unrest", "legitimacy", "army_quality", "peasant_contentment", "church_opinion"]

var _title: Label
var _resource_values: Dictionary = {}
var _temper: BarChart
var _people: PieChart
var _host: BarChart
var _provinces: BarChart
## THE WAR TABLE's report (owner 2026-10-01): the steward's line under the
## title, and the people and the host written as sentences in place of the
## pie and the host's bars — the same figures, in the paper's own voice.
var _sub: Label
var _people_line: Label
var _host_line: Label
## The card scrolls inside the column (it had outgrown it: its foot ran under
## the news bar, 2026-10-01), so its sections live in _body under _scroll.
var _scroll: ScrollContainer
var _body: VBoxContainer
## Emitted when what is written on the card grows or shrinks (the war table
## sizes the report's paper to it).
signal content_resized

static func attach(column: BoxContainer) -> RealmDashboard:
	var d := RealmDashboard.new()
	column.add_child(d)
	column.move_child(d, 0)
	return d

func _init() -> void:
	name = "RealmDashboard"
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var table := UiPalette.war_table()
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)
	_body.minimum_size_changed.connect(func() -> void: content_resized.emit())
	_title = Label.new()
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if table:
		UiPalette.style_header(_title, 24, UiPalette.ink("rubric"))
	else:
		UiPalette.style_header(_title, 16)
	_body.add_child(_title)
	_sub = Label.new()
	_sub.name = "Sub"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var italic := UiPalette.role_font("body_italic")
	if italic != null:
		_sub.add_theme_font_override("font", italic)
	_sub.add_theme_font_size_override("font_size", 14)
	_sub.add_theme_color_override("font_color", UiPalette.ink("muted"))
	_sub.visible = table
	_body.add_child(_sub)
	if not table:
		_body.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.name = "Resources"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)
	var named_figures: bool = Game.data != null and float(Game.data.balance.get("ui_dimension_labels", 0.0)) > 0.0
	for key in RESOURCES:
		grid.add_child(ResourceIcon.create(key))
		var v := Label.new()
		v.name = "Value_" + key
		v.add_theme_font_size_override("font_size", 19 if table else 16)
		v.add_theme_color_override("font_color", UiPalette.ink("soft"))
		v.custom_minimum_size = Vector2(66, 0)
		_resource_values[key] = v
		if not named_figures:
			grid.add_child(v)
			continue
		# Each figure names itself under it (owner 2026-09-28, second
		# critique: the four figures were the card's last icon-only reading).
		var pair := VBoxContainer.new()
		pair.add_theme_constant_override("separation", -4)
		pair.add_child(v)
		var cap := Label.new()
		cap.name = "Name_" + key
		cap.text = String((Game.data.resource_icons.get(key, {}) as Dictionary).get("label", key))
		cap.add_theme_font_size_override("font_size", 11)
		cap.add_theme_color_override("font_color", UiPalette.ink("muted"))
		if table:
			var cap_italic := UiPalette.role_font("body_italic")
			if cap_italic != null:
				cap.add_theme_font_override("font", cap_italic)
			cap.text = cap.text.to_lower()
		pair.add_child(cap)
		grid.add_child(pair)
	_temper = _section("TEMPER OF THE REALM", BarChart.new(), "Temper")
	_people = _section("THE PEOPLE", PieChart.new(), "People")
	_people_line = _line("PeopleLine")
	_host = _section("THE HOST", BarChart.new(), "Host")
	_host_line = _line("HostLine")
	_provinces = _section("LARGEST PROVINCES", BarChart.new(), "Provinces")
	_temper.tally = table
	_people.visible = not table
	_host.visible = not table
	# The gauges name themselves (owner 2026-09-28) unless the balance keeps
	# the 2026-09-13 icons-only card.
	var named: bool = Game.data != null and float(Game.data.balance.get("ui_dimension_labels", 0.0)) > 0.0
	_temper.named = named
	_host.named = named
	(_people as PieChart).named = named

func _section(heading: String, chart: Control, chart_name: String) -> Control:
	var h := Label.new()
	h.text = heading
	UiPalette.style_rubric(h, 14)
	_body.add_child(h)
	chart.name = chart_name
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(chart)
	return chart

## A sentence of the report (the war table's people and host), hidden on leather.
func _line(line_name: String) -> Label:
	var l := Label.new()
	l.name = line_name
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UiPalette.ink("soft"))
	l.visible = UiPalette.war_table()
	_body.add_child(l)
	return l

func _ready() -> void:
	Game.state_changed.connect(func() -> void:
		if is_inside_tree():
			refresh())
	refresh()

func refresh() -> void:
	if Game.state == null:
		return
	var data := Game.data
	var state := Game.state
	var mine := data.resolve_realm("player_realm")
	_title.text = String(data.kingdoms.get(mine, {}).get("label", "The realm"))
	_sub.text = "The steward's account\n%s of year %d" % [
		Calendar.season_name(state.tick), Calendar.year_of(state.tick)]
	var m := state.metrics
	var pop := _people_of_crown()
	_resource_values["treasury"].text = UiPalette.format_int(int(m["treasury"]))
	_resource_values["grain"].text = UiPalette.format_int(int(m["grain"]))
	_resource_values["population"].text = _compact(pop["urban"] + pop["rural"])
	var host := _host_of()
	var troops := 0.0
	for u in host:
		troops += float(host[u])
	_resource_values["army"].text = _compact(troops)
	# Temper: four 0-100 gauges in one hue; unrest reads red as it climbs.
	var temper: Array = []
	for key in TEMPER:
		var label := String((data.resource_icons.get(key, {}) as Dictionary).get("label", key))
		var value := float(m.get(key, 0.0))
		var color := UiPalette.ink("soft") if _temper.tally else UiPalette.ink("fill")
		if key == "unrest" and value >= data.bal("concern_unrest_high"):
			color = UiPalette.ink("bad")
		# The dimension's art stands for the label on the card; the label is
		# the tooltip (owner 2026-09-13).
		temper.append({"label": label, "dimension": key, "value": value, "color": color,
			"text": str(int(value))})
	_temper.set_rows(temper, 100.0)
	_people.set_slices([
		{"label": "Towns", "dimension": "towns", "value": pop["urban"],
			"color": UiPalette.chart_color("cat_1")},
		{"label": "Country", "dimension": "country", "value": pop["rural"],
			"color": UiPalette.chart_color("cat_2")},
	])
	# One measure and one hue (owner 2026-09-28, second critique: 7 ships,
	# 75 guns and thousands of foot on one scale in four colours): each bar is
	# the arm's fighting STRENGTH — its count × the pack's unit_types `power` —
	# so a ship and a footman are weighed alike, in the gauges' one old gold;
	# the figure beside it stays the count.
	var host_rows: Array = []
	var top := 1.0
	for u in host:
		var power := float((data.world_row("military", "unit_types", u) as Dictionary).get("power", "1"))
		var strength := float(host[u]) * maxf(power, 0.0)
		top = maxf(top, strength)
		host_rows.append({"label": String((data.resource_icons.get(u, {}) as Dictionary).get("label", u)),
			"dimension": u,
			"value": strength, "color": UiPalette.chart_color("sequential"),
			"text": _compact(float(host[u]))})
	_host.set_rows(host_rows, top)
	_people_line.text = _people_sentence(pop)
	var parts: Array[String] = []
	for row: Dictionary in host_rows:
		parts.append("%s %s" % [row["label"], row["text"]])
	_host_line.text = " · ".join(parts)
	var provs: Array = []
	for code in MapManors.controlled_provinces(data, state):
		var p: Dictionary = data.provinces[code]
		var v: Variant = WorldLedger.value_of(data, state, "economy.provinces.%s.rural_population" % code)
		var w: Variant = WorldLedger.value_of(data, state, "economy.provinces.%s.urban_population" % code)
		var people := (float(v) if v != null else 0.0) + (float(w) if w != null else 0.0)
		if people <= 0.0:
			people = float(p.get("population", 0))
		provs.append({"label": String(p["label"]), "value": people, "text": _compact(people)})
	provs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"])
	var shown: Array = []
	var prov_top := 1.0
	for j in mini(provs.size(), int(data.bal("dashboard_max_provinces"))):
		var row: Dictionary = provs[j]
		row["color"] = UiPalette.ink("fill")
		prov_top = maxf(prov_top, float(row["value"]))
		shown.append(row)
	_provinces.set_rows(shown, prov_top)

## "Of every hundred souls, N live in towns and M keep the land." — the pie's
## two shares, whole, summing to a hundred.
static func _people_sentence(pop: Dictionary) -> String:
	var total := float(pop["urban"]) + float(pop["rural"])
	if total <= 0.0:
		return "No souls are counted in the crown's own land."
	var towns := roundi(100.0 * float(pop["urban"]) / total)
	return "Of every hundred souls, %d live in towns and %d keep the land." % [towns, 100 - towns]

## Urban and rural population of the provinces the crown controls (owner
## 2026-09-13: the crown's economy is its own land, not the kingdom's),
## live through the ledger.
func _people_of_crown() -> Dictionary:
	var out := {"urban": 0.0, "rural": 0.0}
	for province: String in MapManors.controlled_provinces(Game.data, Game.state):
		for key in ["urban", "rural"]:
			var v: Variant = WorldLedger.value_of(Game.data, Game.state,
				"economy.provinces.%s.%s_population" % [province, key])
			out[key] += float(v) if v != null else 0.0
	return out

## Troops by unit type for the player's realm (unit_types order), via the ledger.
func _host_of() -> Dictionary:
	var out := {}
	for unit: String in Game.data.world_table("military", "unit_types"):
		var v: Variant = WorldLedger.value_of(Game.data, Game.state,
			"military.kingdoms.player_realm." + unit)
		if v != null:
			out[unit] = float(v)
	return out

## 1234567 -> "1.2M", 45678 -> "46k", 512 -> "512".
static func _compact(v: float) -> String:
	if v >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if v >= 10000.0:
		return "%dk" % roundi(v / 1000.0)
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return str(roundi(v))

## The height of what is written on the card, in design px.
func content_height() -> float:
	return _body.get_combined_minimum_size().y

## Test seams.
func title_label() -> Label:
	return _title

func resource_text(key: String) -> String:
	return String((_resource_values.get(key, Label.new()) as Label).text)

func temper_chart() -> BarChart:
	return _temper

func people_chart() -> PieChart:
	return _people

func host_chart() -> BarChart:
	return _host

func provinces_chart() -> BarChart:
	return _provinces
