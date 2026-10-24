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
signal recruitment_requested
signal prisoners_requested
signal battle_reports_requested

var _title: Label
var _summary: Label
var _arms: BarChart
var _regiments: BarChart
## Text rows, not a bar (owner 2026-09-28: a neighbour's strength is fogged —
## Intel — and a bar chart cannot draw an estimate's WORDS instead of a
## number).
var _neighbours: VBoxContainer
var _officers: Label

## Put the panel in a screen's left column, hidden until the tab lights it.
static func attach(column: BoxContainer) -> MilitaryPanel:
	var p: MilitaryPanel = create()
	column.add_child(p)
	return p

## The host as the game makes it: scenes/panels/military_panel.tscn (owner
## 2026-10-02: the look lives in the editor), its lines theme kinds the
## column's theme inks; hidden until the host is asked for.
static func create() -> MilitaryPanel:
	return (load("res://scenes/panels/military_panel.tscn") as PackedScene).instantiate()

func _ready() -> void:
	%Prisoners.pressed.connect(func() -> void: prisoners_requested.emit())
	%BattleReports.pressed.connect(func() -> void: battle_reports_requested.emit())
	$Recruit.pressed.connect(func() -> void: recruitment_requested.emit())
	_title = $Head/Title
	($Head/Close as Button).pressed.connect(func() -> void: closed.emit())
	_summary = $Summary
	_arms = $Arms
	_regiments = $Regiments
	_neighbours = $Neighbours
	_officers = $Officers
	# The MILITARY table it replaced refreshed live while it was up; so does
	# this, so a battle or a muster shows in the column as it happens.
	SignalHub.state_changed.connect(func() -> void:
		if visible:
			refresh())

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
	var unknown := 0
	var dated := false
	var readings := {}
	var unknown_arms := {}
	for u: String in units:
		counts[u] = 0
	for row: Dictionary in _regiments_of(mine):
		var code := String(row["regiment_code"])
		var reading := BattlePresentation.known_unit(data, state, code)
		readings[code] = reading
		if reading.is_empty():
			unknown += 1
			unknown_arms[MapObjects.regiment_arm(data, row)] = true
			continue
		dated = dated or BattlePresentation.awaits_report(data, state, code)
		var count := int(reading.fit) + int(reading.wounded)
		counts[MapObjects.regiment_arm(data, row)] += count
		total += count
	for u: String in units:
		top = maxf(top, float(counts[u]))
	var arm_rows: Array = []
	for i in units.size():
		var u: String = units[i]
		arm_rows.append({"label": _label(u), "value": counts[u], "dimension": u,
			"color": UiPalette.chart_color("cat_%d" % (i + 1)), "text": "Unknown" if unknown_arms.has(u) else RealmDashboard._compact(counts[u])})
	_arms.set_rows(arm_rows, top)
	var total_text := "Unknown" if unknown > 0 else RealmDashboard._compact(total)
	_summary.text = "%s under arms in %d units%s" % [total_text, _regiments_of(mine).size(),
		"; latest received readings" if dated or unknown > 0 else ""]
	var strength: Variant = WorldLedger.value_of(data, state, "military.kingdoms.%s.strength" % mine)
	if dated or unknown > 0:
		_summary.text += "; strength awaiting a report"
	elif strength != null:
		_summary.text += "; strength " + RealmDashboard._compact(float(strength))
	# Regiments: a bar for each, its size, and the arm it is mostly made of.
	var reg_rows: Array = []
	var reg_top := 1.0
	var mine_codes: Array = _regiments_of(mine).map(
		func(r: Dictionary) -> String: return String(r["regiment_code"]))
	for code: String in ArmySystem.ordered(data, state, mine_codes):
		var r := ArmySystem.regiment(data, code, state)
		var reading: Dictionary = readings[code]
		var reg_size := 0 if reading.is_empty() else int(reading.fit) + int(reading.wounded)
		var main_arm := MapObjects.regiment_arm(data, r)
		reg_top = maxf(reg_top, reg_size)
		reg_rows.append({"label": _short(String(r["label"])), "value": reg_size, "icon": _glyph(main_arm),
			"color": UiPalette.chart_color("cat_%d" % (units.find(main_arm) + 1)),
			"text": "Unknown; awaiting a report" if reading.is_empty() else RealmDashboard._compact(reg_size) + " people" + (" · observed day %d" % int(reading.day) if BattlePresentation.awaits_report(data, state, code) else _equipment_note(data, r, main_arm))})
	_regiments.set_rows(reg_rows, reg_top)
	# Neighbours: only what may be SAID of them (Intel) — their strength in
	# common talk, and beneath it the newest spy sighting inside the kingdom
	# (a local count, never the kingdom's strength: Ruling 14); text rows,
	# since a bar chart can only draw a number and the true total must never appear.
	# Own remote losses require a received reading too.
	for c in _neighbours.get_children():
		c.free()
	for code: String in String(data.kingdoms[mine].get("neighbor_codes", "")).split("|", false):
		var theirs := 0.0
		for u: String in units:
			var v: Variant = WorldLedger.value_of(data, state, "military.kingdoms.%s.%s" % [code, u])
			theirs += float(v) if v != null else 0.0
		_neighbours.add_child(_row("%s — %s (common talk)" % [String(data.kingdoms[code]["label"]),
			Intel.magnitude(data, int(theirs))]))
		var seen := sighting(data, state, code)
		if seen != "":
			_neighbours.add_child(_row(seen))
	_neighbours.add_child(_row("%s — %s (yours)" % [String(data.kingdoms[mine]["label"]),
		total_text]))
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
	return MapObjects.regiments_of(Game.data, kingdom_code, Game.state)

## A plain text row for the neighbours block.
func _row(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"CardText"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## The newest spy sighting inside kingdom `code` (Ruling 14, final review
## I4), or "". A spy counts heads within spy_radius_km of ONE point — every
## foreign regiment near it, whoever's — so it is never the kingdom's
## strength: the kingdom's row keeps its common-talk magnitude, and this
## line beneath says what was seen, where and when. This is a KINGDOM-level
## match (any missive whose subject's province belongs to `code`), which
## Intel.estimate() cannot express; text_of() renders the fact the same way.
static func sighting(repo: DataRepository, state: GameState, code: String) -> String:
	var best: Dictionary = {}
	for m: Dictionary in state.missives:
		if not best.is_empty() and int(m["id"]) < int(best["id"]):
			continue
		if String(m["kind"]) != "spy":
			continue
		var prov := Intel.province_of(repo, state, m["subject"])
		if prov == "" or MapOwnership.owner_of(repo, state, prov) != code:
			continue
		for f: Dictionary in m["facts"]:
			if String(f["key"]) == "troops_foreign":
				best = {"id": int(m["id"]), "fact": f, "day": int(m["day"]), "subject": m["subject"]}
	if best.is_empty():
		return ""
	var subj: Dictionary = best["subject"]
	var place := Intel.place_label(repo, state, Vector2(float(subj.get("x", 0)), float(subj.get("y", 0))))
	var f: Dictionary = best["fact"]
	var count := "No" if int(f.get("hi", -1)) == 0 else Intel.text_of(f)
	return "%s foreign troops seen near %s (spy · %s)" % [count, place, CourierCard.date_of(int(best["day"]))]

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

func neighbours_chart() -> VBoxContainer:
	return _neighbours


## Ships and guns remain equipment, separately named from their crews.
func _equipment_note(repo: DataRepository, row: Dictionary, arm: String) -> String:
	if arm == "fleet":
		return " · %s ships" % UiPalette.format_int(int(row.get(arm, 0)))
	if int(repo.world_table("military", "unit_types").get(arm, {}).get("crew", 1)) > 1:
		return " · %s equipment" % UiPalette.format_int(int(row.get(arm, 0)))
	return ""
