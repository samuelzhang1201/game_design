extends RefCounted

const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")

static func contact(repo: DataRepository, day: int) -> GameState:
	var s := SuiteData.campaign(repo, 71)
	s.tick = 1
	s.day = day
	var mine: Array = Play.land_regiments(repo, 400)
	var reg := ArmySystem.regiment(repo, String(mine[0]))
	var at := ArmySystem.pack_to_metres(repo, Vector2(float(reg["x"]), float(reg["y"])))
	Play.park_army(repo, s, at)
	s.ai_hosts.clear()
	s.foes.clear()
	Play.place(repo, s, String(mine[0]), at, ArmySystem.ORDER_STANDBY)
	var foes: Array = []
	for host: Dictionary in repo.raid_hosts:
		foes.append_array(EnemyAi.host_units(repo, null, host))
	foes.sort()
	var code := String(foes[0])
	s.foes[code] = ArmySystem.starting_state(repo, ArmySystem.regiment(repo, code))
	Play.place(repo, s, code, at + Vector2i(1000, 0), ArmySystem.ORDER_STANDBY)
	repo.battle_outcomes = [{"tier": "fixture", "eff_min": 0, "eff_max": 1000,
		"attacker_loss_permille": 100, "defender_loss_permille": 100,
		"wounded_share_permille": 500, "attacker_morale": 0, "defender_morale": 0,
		"rout": "none"}]
	for stance: Dictionary in repo.battle_stances.values():
		stance["retreat_odds_permille"] = 0
	return s

static func roundtrip(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))

static func two_battles(repo: DataRepository, day: int) -> GameState:
	var s := contact(repo, day)
	var mine: Array = Play.land_regiments(repo, 400)
	var first: Dictionary = s.regiments[String(mine[0])]
	var at := Vector2i(int(first["x_m"]), int(first["y_m"])) + Vector2i(0, 100000)
	Play.place(repo, s, String(mine[1]), at, ArmySystem.ORDER_STANDBY)
	for host: Dictionary in repo.raid_hosts:
		for code: String in EnemyAi.host_units(repo, null, host):
			if not s.foes.has(code):
				s.foes[code] = ArmySystem.starting_state(repo, ArmySystem.regiment(repo, code))
				Play.place(repo, s, code, at + Vector2i(1000, 0), ArmySystem.ORDER_STANDBY)
				return s
	return s
