class_name BattleEncounterPanel
extends Control

signal decision_selected(token: String, choice: String)
signal formation_requested(regiment: String, battle_id: int, formation: String)

@onready var _title: Label = %Title
@onready var _summary: Label = %Summary
@onready var _continue: Button = %Continue
var _token := ""
var _view: Dictionary = {}

func _ready() -> void:
	_continue.pressed.connect(func() -> void: decision_selected.emit(_token, "continue"))
	%FormationSend.pressed.connect(_send_formation)
	%FormationChoice.item_selected.connect(_formation_selected)

func show_decision(decision: Dictionary, place: String, view: Dictionary = {}) -> void:
	_view = view.duplicate(true)
	_token = String(decision["token"])
	_title.text = "Contact at %s" % place
	_summary.text = "Our army has halted before the enemy. No fighting has yet been resolved.\n\nReview the field and your orders. Time stays paused until you choose to resume it."
	if String(view.get("agreements", "")) != "":
		_summary.text += "\n\nBattlefield agreements\n" + String(view["agreements"])
	var choice: OptionButton = %FormationChoice
	choice.clear()
	for option: Dictionary in view.get("options", []):
		choice.add_item(String(option["label"]))
		choice.set_item_metadata(choice.item_count - 1, option)
	%FormationChoice.get_parent().visible = choice.item_count > 0
	%FormationStatus.visible = choice.item_count > 0
	if choice.item_count > 0:
		choice.select(0)
		_formation_selected(0)
	show()

func _formation_selected(index: int) -> void:
	var option: Dictionary = %FormationChoice.get_item_metadata(index)
	var why := String(option.get("reason", ""))
	%FormationSend.disabled = why != ""
	%FormationStatus.text = why if why != "" else "%d gold warrant + %d gold courier. Reforming temporarily exposes the army." % [int(_view.get("gold", 0)), int(_view.get("courier_gold", 0))]
	if why == "" and String(option.get("note", "")) not in ["", String(option["label"])]:
		%FormationStatus.text += "\n" + String(option["note"])


func _send_formation() -> void:
	var option: Dictionary = %FormationChoice.get_item_metadata(%FormationChoice.selected)
	formation_requested.emit(String(_view["regiment"]), int(_view["battle_id"]), String(option["id"]))


func show_order_result(result: Dictionary) -> void:
	%FormationStatus.text = "Formation order issued." if bool(result.get("ok", false)) else String(result.get("error", "Order refused."))
