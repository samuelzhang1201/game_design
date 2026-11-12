class_name BattleEncounterPanel
extends Control

signal decision_selected(token: String, choice: String)
signal deployment_requested

@onready var _title: Label = %Title
@onready var _summary: Label = %Summary
@onready var _continue: Button = %Continue
var _token := ""
var _view: Dictionary = {}
var _map_rect := Rect2()

func _ready() -> void:
	_continue.pressed.connect(func() -> void: decision_selected.emit(_token, "continue"))
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
	show()
