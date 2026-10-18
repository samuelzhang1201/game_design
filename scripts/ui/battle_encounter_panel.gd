class_name BattleEncounterPanel
extends Control

signal decision_selected(token: String, choice: String)
signal formation_requested(regiment: String, battle_id: int, formation: String)
signal deployment_requested

@onready var _title: Label = %Title
@onready var _summary: Label = %Summary
@onready var _continue: Button = %Continue
var _token := ""
var _view: Dictionary = {}
var _map_rect := Rect2()

func _ready() -> void:
	_continue.pressed.connect(func() -> void: decision_selected.emit(_token, "continue"))
	%FormationSend.pressed.connect(_send_formation)
	%FormationChoice.item_selected.connect(_formation_selected)
	%Deploy.pressed.connect(func() -> void: deployment_requested.emit())
	%Center.minimum_size_changed.connect(_fit_center)

func open(repo: DataRepository, state: GameState, decision: Dictionary) -> void:
	var battle := BattleSystem.battle_by_id(state, int(decision.get("battle_id", -1)))
	if battle.is_empty():
		hide()
		return
	var own: Array[String] = []
	var enemy: Array[String] = []
	for side: String in BattleSystem.SIDES:
		for code: String in battle.get(side, []):
			var brief := WarFolio.brief(repo, state, code)
			var rows: Array = brief.get("rows", [])
			var strength := String(rows[0]["text"]) if not rows.is_empty() else "Strength unknown"
			var line := "%s — %s" % [String(brief.get("title", "Troops")), strength]
			if state.regiments.has(code):
				own.append(line)
			else:
				enemy.append(line)
	%OwnForces.text = "\n".join(own)
	%EnemyForces.text = "\n".join(enemy)
	var view: Dictionary = {}
	for shown: Dictionary in BattlePresentation.snapshot(repo, state, repo.resolve_realm("player_realm"))["battles"]:
		if int(shown["id"]) == int(battle["id"]):
			view = shown["formation_view"]
			break
	show_decision(decision, BattleSystem.place_label(repo, state, battle), view)

func center_on(map_rect: Rect2) -> void:
	_map_rect = map_rect
	_fit_center()

func _fit_center() -> void:
	if _map_rect.size == Vector2.ZERO:
		return
	%Center.position = _map_rect.position - global_position
	%Center.size = _map_rect.size

func show_decision(decision: Dictionary, place: String, view: Dictionary = {}) -> void:
	_view = view.duplicate(true)
	_token = String(decision["token"])
	_title.text = "Contact at %s" % place
	_summary.text = ""
	if String(view.get("agreements", "")) != "":
		_summary.text = "Battlefield agreements\n" + String(view["agreements"])
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
