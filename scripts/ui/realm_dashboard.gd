class_name RealmDashboard
extends VBoxContainer
## The left column's default content (user ruling 2026-09-09): the player's
## own realm at a glance — resources as icons with tooltips, the temper of
## the realm as bars, the people as a pie, the host by unit type, and the
## largest provinces — all engine truth, refreshed on every state change.
## Charts follow the dataviz rules: thin marks, text in text ink, categorical
## colours in fixed order from data/chart_palette.csv.

const RESOURCES := ["treasury", "grain", "population", "army"]
const TEMPER := ["unrest", "legitimacy", "peasant_contentment", "church_opinion"]

var _title: Label
var _resource_values: Dictionary = {}
var _temper: BarChart
var _people: PieChart
var _host: BarChart
var _provinces: BarChart

static func attach(column: BoxContainer) -> RealmDashboard:
	var d := RealmDashboard.new()
	column.add_child(d)
	column.move_child(d, 0)
	return d

func _init() -> void:
	name = "RealmDashboard"
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_title = Label.new()
	_title.name = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_header(_title, 8)
	add_child(_title)
	add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.name = "Resources"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	for key in RESOURCES:
		grid.add_child(ResourceIcon.create(key))
		var v := Label.new()
		v.name = "Value_" + key
		v.add_theme_font_size_override("font_size", 8)
		v.custom_minimum_size = Vector2(38, 0)
		grid.add_child(v)
		_resource_values[key] = v
	_temper = _section("TEMPER OF THE REALM", BarChart.new(), "Temper")
	_people = _section("THE PEOPLE", PieChart.new(), "People")
	_host = _section("THE HOST", BarChart.new(), "Host")
	_provinces = _section("LARGEST PROVINCES", BarChart.new(), "Provinces")

func _section(heading: String, chart: Control, chart_name: String) -> Control:
	var h := Label.new()
	h.text = heading
	UiPalette.style_header(h, 7, UiPalette.TEXT_MUTED)
	add_child(h)
	chart.name = chart_name
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(chart)
	return chart

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
	var m := state.metrics
	var pop := _people_of(mine)
	_resource_values["treasury"].text = str(int(m["treasury"]))
	_resource_values["grain"].text = str(int(m["grain"]))
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
		var color := UiPalette.chart_color("sequential")
		if key == "unrest" and value >= data.bal("concern_unrest_high"):
			color = UiPalette.NEGATIVE
		temper.append({"label": label, "value": value, "color": color, "text": str(int(value))})
	_temper.set_rows(temper, 100.0)
	_people.set_slices([
		{"label": "Towns", "value": pop["urban"], "color": UiPalette.chart_color("cat_1")},
		{"label": "Country", "value": pop["rural"], "color": UiPalette.chart_color("cat_2")},
	])
	var host_rows: Array = []
	var top := 1.0
	var i := 0
	for u in host:
		i += 1
		top = maxf(top, float(host[u]))
		host_rows.append({"label": String((data.resource_icons.get(u, {}) as Dictionary).get("label", u)),
			"value": float(host[u]), "color": UiPalette.chart_color("cat_%d" % i),
			"text": _compact(float(host[u]))})
	_host.set_rows(host_rows, top)
	var provs: Array = []
	for code in MapOwnership.provinces_of(data, state, mine):
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
		row["color"] = UiPalette.chart_color("sequential")
		prov_top = maxf(prov_top, float(row["value"]))
		shown.append(row)
	_provinces.set_rows(shown, prov_top)

## Urban and rural population of the realm, live through the ledger.
func _people_of(kingdom_code: String) -> Dictionary:
	var out := {"urban": 0.0, "rural": 0.0}
	for key in ["urban", "rural"]:
		var v: Variant = WorldLedger.value_of(Game.data, Game.state,
			"economy.kingdoms.%s.%s_population" % [kingdom_code, key])
		out[key] = float(v) if v != null else 0.0
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
