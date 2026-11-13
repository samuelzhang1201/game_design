extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Owner R-H (2026-11-13): formations are retired in ordinary play — no order is
## accepted, no saved deployment adds a combat factor, old records still load.

func test_four_shapes_preserve_figures() -> void:
	var formation: GDScript = load("res://scripts/engine/battle_formation.gd")
	if formation == null:
		return
	for shape: String in ["line", "wedge", "diamond", "double_rank"]:
		var slots: Array = formation.slots(shape, 9)
		assert_eq(slots.size(), 9, shape)
		var unique := {}
		for slot: Vector2 in slots:
			unique[slot] = true
		assert_eq(unique.size(), 9, shape + " has no overlap")

func test_distant_opposite_columns_do_not_flank_without_group_contact() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 97)
	var ours := state.regiments.keys()
	ours.sort()
	var foes := state.foes.keys()
	foes.sort()
	var code := String(ours[0])
	state.regiments[code]["x_m"] = 1000
	state.regiments[code]["y_m"] = 0
	state.foes[foes[0]]["x_m"] = 0
	state.foes[foes[0]]["y_m"] = 0
	state.foes[foes[1]]["x_m"] = 2000
	state.foes[foes[1]]["y_m"] = 0
	var battle := {"att": [code], "def": [foes[0], foes[1]], "place_x_m": 0, "place_y_m": 0}
	BattleGroups.refresh(repo, state, battle)
	assert_false(BattleFormation.context(repo, state, battle, "att")["flanked"], "opposite distant columns have no actual group contact")

func _unit_fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 981)
	var codes := state.regiments.keys()
	codes.sort()
	var battle := {"id": 981, "att": [codes[0], codes[1]], "def": [state.foes.keys()[0]],
		"place_x_m": 0, "place_y_m": 0, "town": ""}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	return {"repo": repo, "state": state, "battle": battle, "a": String(codes[0]), "b": String(codes[1])}

func test_every_formation_order_is_refused_without_mutation() -> void:
	var f := _unit_fixture()
	var at := ArmySystem.pack_to_metres(f.repo, ArmySystem.position_of(f.repo, f.state, ArmySystem.regiment(f.repo, f.a, f.state)))
	f.state.king_state["x_m"] = at.x
	f.state.king_state["y_m"] = at.y
	f.state.metrics["treasury"] = 10000.0
	var before := SaveLoad.state_hash(f.state)
	var actions := ActionSystem.new(f.repo)
	for formation: String in f.repo.battle_formations:
		var req := ActionRequest.make("BATTLE_FORMATION", {"regiment": f.a, "battle_id": 981, "formation": formation})
		assert_eq(actions.validate(req, f.state), BattleFormation.RETIRED, formation)
		assert_eq(BattleFormation.refusal(f.repo, f.state, 981, "att", formation, f.a), BattleFormation.RETIRED)
	assert_eq(SaveLoad.state_hash(f.state), before)
	assert_ne(BattleFormation.refusal(f.repo, f.state, 12345, "att", "line"), BattleFormation.RETIRED,
		"a missing battlefield keeps its own reason")


func test_an_old_formation_courier_lapses_on_arrival() -> void:
	var f := _unit_fixture()
	var before: Dictionary = f.battle.formations.duplicate(true)
	var courier := {"id": 7, "target": f.a}
	var order := {"action_code": "BATTLE_FORMATION", "battle_id": 981, "formation": "line"}
	var result := CourierSystem._deliver_one(f.repo, f.state, courier, order)
	assert_eq(result.type, "lapsed")
	assert_eq(result.said, BattleFormation.RETIRED)
	assert_eq(f.battle.formations, before)


func test_saved_deployments_add_no_combat_factor_and_round_trip() -> void:
	var f := _unit_fixture()
	f.battle.erase("formations")
	var plain := BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), false)
	BattleFormation.ensure(f.battle)
	f.battle.formations.att.current = "wedge"
	f.battle.formations.att.target = "line"
	f.battle.formations.att.disorder_until = f.state.absolute_day() + 10
	f.battle.unit_formations = {f.a: f.battle.formations.att.duplicate(true)}
	f.battle.unit_formations[f.a].current = "line"
	for attacking: bool in [false, true]:
		var strength := BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), attacking)
		assert_false(strength.factors.any(func(factor: Dictionary) -> bool:
			return String(factor.source).begins_with("formation:")), "no formation factor")
	assert_eq(BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), false), plain,
		"an old saved line and its disorder change nothing")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(restored.battles[0].unit_formations, f.battle.unit_formations, "old records load unchanged")
	BattleSystem.finish_day(f.repo, f.state)
	assert_eq(f.battle.formations.att.current, "wedge", "nothing advances a retired deployment")
