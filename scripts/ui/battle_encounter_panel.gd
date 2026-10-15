class_name BattleEncounterPanel
extends Control

signal decision_selected(token: String, choice: String)

@onready var _title: Label = %Title
@onready var _summary: Label = %Summary
@onready var _continue: Button = %Continue
var _token := ""

func _ready() -> void:
	_continue.pressed.connect(func() -> void: decision_selected.emit(_token, "continue"))

func show_decision(decision: Dictionary, place: String) -> void:
	_token = String(decision["token"])
	_title.text = "Contact at %s" % place
	_summary.text = "Our army has halted before the enemy. No fighting has yet been resolved.\n\nReview the field and your orders. Time stays paused until you choose to resume it."
	show()
