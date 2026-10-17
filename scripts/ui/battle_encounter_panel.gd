class_name BattleEncounterPanel
extends Control
## The scene owns the look; the panel reads known facts and requests actions.

signal decision_selected(token: String, choice: String)
signal deployment_requested

var _token := ""
var _map_rect := Rect2()

func _ready() -> void:
	%Continue.pressed.connect(func() -> void: decision_selected.emit(_token, "continue"))
	%Deploy.pressed.connect(func() -> void: deployment_requested.emit())
	%Center.minimum_size_changed.connect(_fit_center)

func open(repo: DataRepository, state: GameState, decision: Dictionary) -> void:
	_token = String(decision.get("token", ""))
	var battle := BattleSystem.battle_by_id(state, int(decision.get("battle_id", 0)))
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
	visible = true

## The active map's bounds are runtime geometry, like the audience window.
func center_on(map_rect: Rect2) -> void:
	_map_rect = map_rect
	_fit_center()

func _fit_center() -> void:
	if _map_rect.size == Vector2.ZERO:
		return
	# Wrapped labels briefly report a tall minimum before their width settles.
	%Center.position = _map_rect.position - global_position
	%Center.size = _map_rect.size
