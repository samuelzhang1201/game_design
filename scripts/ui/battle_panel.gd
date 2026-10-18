class_name BattlePanel
extends Control

signal decision_selected(token: String, choice: String)
signal order_requested(regiment: String, battle_id: int, kind: String)
signal closed
var _view: Dictionary = {}
var _battle_id := -1
var _decision: Dictionary = {}

func _ready() -> void:
	%Close.pressed.connect(func() -> void: hide(); closed.emit())
	%Send.pressed.connect(_send)
	%Order.item_selected.connect(_order_selected)
	%Battle.item_selected.connect(func(index: int) -> void: show_view(_view, int(%Battle.get_item_metadata(index))))
	for index: int in %Choices.get_child_count():
		get_node("%%Choice%d" % (index + 1)).pressed.connect(_choose.bind(index))

func show_view(view: Dictionary, battle_id := -1) -> void:
	_view = view
	_decision = view.get("decision", {})
	var event := String(_decision.get("kind", "")) == "battle_event"
	_battle_id = int(_decision.get("battle_id", battle_id)) if event else battle_id
	%Battle.clear()
	var chosen: Dictionary = {}
	for battle: Dictionary in view.get("battles", []):
		%Battle.add_item(String(battle["place"]))
		%Battle.set_item_metadata(%Battle.item_count - 1, int(battle["id"]))
		if int(battle["id"]) == _battle_id or chosen.is_empty():
			chosen = battle
			%Battle.select(%Battle.item_count - 1)
	if not chosen.is_empty(): _battle_id = int(chosen["id"])
	%Battle.visible = not event and %Battle.item_count > 1
	%Close.visible = not event
	%Orders.visible = not event and not chosen.is_empty()
	%Choices.visible = event
	%Illustration.visible = event
	%Title.text = String(_decision.get("title", "Battlefield decision")) if event else "Command at " + String(chosen.get("place", "the field"))
	%Summary.text = String(_decision.get("scene", "")) if event else _summary(chosen)
	if event:
		var path := GameArt.path(GameArt.BATTLE_EVENTS, String(_decision.get("art_key", "")))
		%Illustration.texture = load(path) if path != "" else null
		for index: int in %Choices.get_child_count():
			var button: Button = get_node("%%Choice%d" % (index + 1))
			var options: Array = _decision.get("options", [])
			button.get_parent().visible = index < options.size()
			if index >= options.size(): continue
			var row: Dictionary = options[index]
			button.text = "%s — %d gold" % [row["label"], int(row.get("gold", 0))]
			var detail: Label = get_node("%%ChoiceDetails%d" % (index + 1))
			detail.text = String(row.get("effects_text", ""))
			var why := String(row.get("reason", ""))
			button.disabled = why != "" or not bool(row.get("legal", true))
			if why != "": detail.text += "\n" + why
	else:
		%Order.clear()
		for row: Dictionary in chosen.get("orders", []):
			%Order.add_item(String(row["label"]))
			%Order.set_item_metadata(%Order.item_count - 1, row)
		if %Order.item_count > 0:
			%Order.select(0)
			_order_selected(0)
	%Status.text = ""
	show()

func _summary(battle: Dictionary) -> String:
	if battle.is_empty(): return "No active battlefield is known."
	var lines: PackedStringArray = ["Current order: %s. Formation: %s." % [battle.get("action", "hold"), String(battle.get("formation", "")).replace("_", " ")]]
	for unit: Dictionary in battle.get("units", []):
		if not bool(unit.get("known", true)):
			lines.append("%s — %s\nPersonnel, morale and supplies unknown; awaiting a report." % [unit["label"], unit["commander"]])
			continue
		lines.append("%s — %s\n%s fit, %s wounded; morale %d; supplies %s. Observed on day %d." % [unit["label"], unit["commander"], UiPalette.format_int(int(unit["fit"])), UiPalette.format_int(int(unit["wounded"])), int(unit["morale"]), UiPalette.format_int(int(unit["supplies"])), int(unit.get("observed_day", 0))])
	lines.append(String(battle.get("agreements", "")))
	for row: Dictionary in battle.get("warrants", []):
		lines.append("%s: %s; %d gold reserved. %s" % [row["kind"], row["status"], int(row["reserved_gold"]), row["reason"]])
	for report: Dictionary in _view.get("reports", []):
		if int(report.get("battle_id", -1)) == _battle_id:
			lines.append(String(report.get("text", "")))
	return "\n\n".join(lines)

func _order_selected(index: int) -> void:
	var row: Dictionary = %Order.get_item_metadata(index)
	var why := String(row.get("reason", ""))
	%Send.disabled = why != ""
	%OrderDetails.text = "%s\n%d gold courier; %d gold warrant; %d gold reserved. %s" % [row.get("effects_text", ""), int(row.get("courier_gold", 0)), int(row.get("filing_gold", 0)), int(row.get("reserved_gold", 0)), "Executed here." if bool(row.get("local", false)) else "Takes effect when the courier arrives."]
	if int(row.get("cooldown_days", 0)) > 0: %OrderDetails.text += "\nCooldown: %d days." % int(row["cooldown_days"])
	if why != "": %OrderDetails.text += "\n" + why

func _choose(index: int) -> void:
	var options: Array = _decision.get("options", [])
	if index < options.size() and bool(options[index].get("legal", true)) and String(options[index].get("reason", "")) == "":
		decision_selected.emit(String(_decision["token"]), String(options[index]["id"]))

func _send() -> void:
	if %Order.selected < 0 or %Send.disabled: return
	var row: Dictionary = %Order.get_item_metadata(%Order.selected)
	order_requested.emit(String(row["regiment"]), _battle_id, String(row["id"]))

func show_result(result: Dictionary) -> void:
	%Status.text = String(result.get("reason", result.get("error", "Order issued.")))

func battle_id() -> int:
	return _battle_id
