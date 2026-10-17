class_name ArmyRecruitmentPanel
extends Control
## The scene owns the form; the engine owns every qualification and quote.
signal closed
signal recruited(result: Dictionary)
var above: Array[Control] = []
var _quote: Dictionary = {}
var _request_id := ""
var _serial := 0
var _filling := false

func _service() -> GDScript:
	return load("res://scripts/engine/recruitment_system.gd")

func _ready() -> void:
	%Close.pressed.connect(close)
	%Confirm.pressed.connect(confirm)
	for menu: OptionButton in [%Town, %Origin, %Target, %Arm]:
		menu.item_selected.connect(_selection_changed)
	%Commander.item_selected.connect(func(_i: int) -> void: refresh_quote())
	%People.value_changed.connect(func(_v: float) -> void: refresh_quote())
	%Nobles.value_changed.connect(func(_v: float) -> void: refresh_quote())
	Game.state_changed.connect(func() -> void:
		if visible and not _filling:
			refresh_quote())

func open() -> void:
	_filling = true
	_request_id = _next_id()
	%Town.clear()
	%Target.clear()
	%Arm.clear()
	%Origin.clear()
	_add(%Origin, "Rural people", "rural_population")
	_add(%Origin, "Urban people", "urban_population")
	var realm := Game.data.resolve_realm("player_realm")
	var towns: Array = Game.data.burgs.keys()
	towns.sort()
	for code: String in towns:
		if ArmyGround.holds(Game.data, Game.state, realm, code):
			_add(%Town, String(Game.data.burgs[code]["label"]), code)
	_add(%Target, "Raise a new unit", "")
	for row: Dictionary in MapObjects.regiments_of(Game.data, realm, Game.state):
		_add(%Target, "Reinforce · " + String(row["label"]), String(row["regiment_code"]))
	for arm: String in Game.data.recruitment:
		_add(%Arm, String(Game.data.world_table("military", "unit_types")[arm]["label"]), arm)
	%People.value = Game.data.bal("army_split_cap_men")
	%Nobles.max_value = Game.data.bal("army_noble_cap_permille")
	%Nobles.value = 0
	_filling = false
	visible = true
	Game.hold_clock(true, "recruitment")
	_selection_changed(0)

func close() -> void:
	if not visible:
		return
	visible = false
	Game.hold_clock(false, "recruitment")
	closed.emit()

func _exit_tree() -> void:
	Game.hold_clock(false, "recruitment")

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		for overlay: Control in above:
			if is_instance_valid(overlay) and overlay.visible:
				return
		close()
		get_viewport().set_input_as_handled()

func _next_id() -> String:
	var id := ""
	while id == "" or Game.state.recruitment_projects.has(id) or Game.state.army_roster.has("recruited:" + id):
		id = "ui:%d:%d:%d" % [Game.state.absolute_day(), Game.state.recruitment_projects.size(), _serial]
		_serial += 1
	return id

func _selection_changed(_index: int) -> void:
	if _filling:
		return
	_filling = true
	var code := _chosen(%Target)
	%Arm.disabled = code != ""
	if code != "":
		var arm := MapObjects.regiment_arm(Game.data, Game.state.army_roster[code])
		for i: int in %Arm.item_count:
			if String(%Arm.get_item_metadata(i)) == arm:
				%Arm.select(i)
	var previous := _chosen(%Commander)
	%Commander.clear()
	var ids: Array = _service().available_commanders(Game.data, Game.state, _chosen(%Arm), code)
	for id: String in ids:
		var person: Character = Game.state.characters[id]
		_add(%Commander, "%s · %s" % [person.display_name, person.family_name], id)
		if id == previous:
			%Commander.select(%Commander.item_count - 1)
	var serving := String(Game.state.military_rosters.get(code, {}).get("commander_id", ""))
	%Commander.disabled = serving != ""
	for i: int in %Commander.item_count:
		if String(%Commander.get_item_metadata(i)) == serving:
			%Commander.select(i)
	_filling = false
	refresh_quote()

func _add(menu: OptionButton, label: String, value: String) -> void:
	menu.add_item(label)
	menu.set_item_metadata(menu.item_count - 1, value)

func _chosen(menu: OptionButton) -> String:
	return String(menu.get_item_metadata(menu.selected)) if menu.selected >= 0 else ""

func request() -> Dictionary:
	var town := _chosen(%Town)
	return {"request_id": _request_id, "mode": "new" if _chosen(%Target) == "" else "reinforce",
		"unit_code": _chosen(%Target), "arm": _chosen(%Arm), "assembly_town": town,
		"source_province": String(Game.data.burgs.get(town, {}).get("province_code", "")),
		"source_population_field": _chosen(%Origin), "total": int(%People.value),
		"noble_permille": int(%Nobles.value), "commander_id": _chosen(%Commander)}

func refresh_quote() -> void:
	if _filling or Game.state == null:
		return
	_quote = _service().quote(Game.data, Game.state, request())
	%Share.text = "Requested noble share: %s%% · commander included in the final share" % str(%Nobles.value / 10.0)
	%Confirm.disabled = _quote.has("error")
	%Refusal.visible = _quote.has("error")
	%Refusal.text = "Cannot recruit: " + String(_quote["error"]) if _quote.has("error") else ""
	if not _quote.has("composition"):
		%Quote.text = ""
	else:
		var c: Dictionary = _quote["composition"]
		var quality: Dictionary = _quote["quality"]
		var food := int(_quote["food_per_month"])
		var food_low := floori(food / float(Calendar.DAYS_PER_TICK))
		var food_high := ceili(food / float(Calendar.DAYS_PER_TICK))
		var daily_food := str(food_low) if food_low == food_high else "%d–%d" % [food_low, food_high]
		var final: Dictionary = _quote["final_composition"]
		var final_nobles := int(final["noble_troops"]) + int(final["commander"])
		var final_total := int(final["commoners"]) + final_nobles
		%Share.text = "Requested noble share: %s%% · actual final share: %.2f%% (commander included)" % [str(%Nobles.value / 10.0), 100.0 * final_nobles / final_total]
		%Quote.text = "%s gold · paid once, in full\n%d people: %d commoners · %d noble troops · %d commander included\nFood: %d / month · %s / day\nMilitary wages: %s gold / month\nCombat quality %+.1f%% · discipline %+.1f%%\nAssembly: %d effective days · earliest %s, if uninterrupted\nNo grain is included in this purchase." % [UiPalette.format_int(int(_quote["gold"])), int(%People.value), int(c["commoners"]), int(c["noble_troops"]), int(c["commander"]), food, daily_food, UiPalette.format_int(int(quality["monthly_wages"])), (int(quality["power_permille"]) - 1000) / 10.0, (int(quality["discipline_permille"]) - 1000) / 10.0, int(_quote["build_days"]), CourierCard.date_of(int(_quote["earliest_completion_day"]))]
		if request()["mode"] == "reinforce":
			%Quote.text += "\nFinal unit: %d commoners · %d noble troops · %d commander" % [int(final["commoners"]), int(final["noble_troops"]), int(final["commander"])]
	var lines: Array[String] = []
	for project: Dictionary in Game.state.recruitment_projects.values():
		lines.append("%s · %s · %d / %d days%s" % [_project_name(project), String(project["status"]), int(project["worked_days"]), int(project["build_days"]), "\n" + String(project["pause_reason"]) if String(project.get("pause_reason", "")) != "" else ""])
		if project.has("completion_composition"):
			var people := 0
			var nobles := 0
			for composition: Dictionary in project["completion_composition"].values():
				var unit_nobles := int(composition["noble_troops"]) + int(composition["commander"])
				people += int(composition["commoners"]) + unit_nobles
				nobles += unit_nobles
			lines.append("Actual survivors: %s people · %s nobles (%.2f%%, commander included)" % [
				UiPalette.format_int(people), UiPalette.format_int(nobles), 100.0 * nobles / people if people > 0 else 0.0])
	%Projects.text = "No paid assemblies in progress." if lines.is_empty() else "\n".join(lines)

func confirm() -> void:
	if not visible:
		return
	refresh_quote()
	if _quote.has("error"):
		return
	var result := Game.try_execute(ActionRequest.make("ARMY_RECRUIT", request()))
	if bool(result.get("ok", false)):
		Game.publish_news("Recruitment paid: %s gold. Personnel and equipment are assembling." % UiPalette.format_int(int(_quote["gold"])))
		recruited.emit(result)
		close()
	else:
		%Refusal.text = String(result.get("error", "Recruitment refused."))
		%Refusal.visible = true
		%Confirm.disabled = true

func offer() -> Dictionary:
	return _quote.duplicate(true)

func quote_text() -> String:
	return %Quote.text + ("\n" + %Refusal.text if %Refusal.visible else "")


func _project_name(project: Dictionary) -> String:
	var code := String(project["unit_code"])
	if Game.state.army_roster.has(code):
		return String(Game.state.army_roster[code]["label"])
	var req: Dictionary = project.get("request", {})
	var town: Dictionary = Game.data.burgs.get(req.get("assembly_town", ""), {})
	var arm: Dictionary = Game.data.world_table("military", "unit_types").get(req.get("arm", ""), {})
	return "%s · %s" % [String(town.get("label", "Assembly")), String(arm.get("label", "new unit"))]
