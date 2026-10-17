class_name KingMapBridge
extends RefCounted
## Presentation copies; predicting the day never advances the live simulation.

var revision := 0
var _key: Array = []
var _snapshot: Dictionary = {}
var _sight := Map3DSight.new()

func make(repo: DataRepository, state: GameState, dev: bool = false) -> Dictionary:
	var journal: Dictionary = state.day_resolution.get("journal", {})
	var phase := String(state.day_resolution.get("phase", ""))
	var committed := bool(journal.get("king_advanced", false)) or phase in ["encounters", "battles", "finish"]
	var key := [state.get_instance_id(), state.absolute_day(), state.king_state.hash(),
		state.regiments.hash(), state.foes.hash(), state.battles.hash(),
		state.province_owner.hash(), state.manor_owner.hash(), phase, committed, dev]
	if key == _key:
		return _snapshot
	_key = key
	revision += 1
	var king: Dictionary = state.king_state.duplicate(true)
	var path: Array = [KingSystem.position(state)]
	if not committed and int(king.get("last_advanced_day", 0)) != state.absolute_day():
		var preview := GameState.new()
		preview.tick = state.tick
		preview.day = state.day
		preview.king_state = king.duplicate(true)
		preview.army_roster = state.army_roster
		preview.regiments = state.regiments.duplicate()
		preview.foes = state.foes
		var follow := String(king.get("follow_code", ""))
		var follow_path: Array = []
		if follow != "" and state.regiments.has(follow):
			preview.regiments[follow] = (state.regiments[follow] as Dictionary).duplicate(true)
			follow_path = CourierSystem.day_path_of(repo, state, follow)
			if not follow_path.is_empty():
				preview.regiments[follow]["x_m"] = Vector2i(follow_path.back()).x
				preview.regiments[follow]["y_m"] = Vector2i(follow_path.back()).y
		KingSystem.step_day(repo, preview)
		var end := KingSystem.position(preview)
		path = []
		if String(king.get("travel_state", "")) == "following" and not follow_path.is_empty():
			path = follow_path.duplicate()
		else:
			var old := MarchRoute.from_pairs(king.get("route", []))
			var remaining := MarchRoute.from_pairs(preview.king_state.get("route", []))
			path = old.slice(0, maxi(old.size() - remaining.size(), 0))
			if path.is_empty() or Vector2i(path.back()) != end:
				path.append(end)
	var camps: Dictionary = {}
	for reg: Dictionary in _sight.regiments(repo, state, dev):
		var code := String(reg["regiment_code"])
		var book: Dictionary = state.foes if ArmySystem.is_foe(state, code) else state.regiments
		var camp: Dictionary = (book.get(code, {}) as Dictionary).get("camp_state", {}).duplicate(true)
		if camp.is_empty():
			continue
		camp["under_attack"] = not BattleSystem.battle_of(state, code).is_empty()
		camps[code] = camp
	_snapshot = {"king": king, "king_path": path, "camps": camps, "absolute_day": state.absolute_day(), "day_committed": committed}
	return _snapshot
