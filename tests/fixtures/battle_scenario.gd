extends RefCounted
## Real-pack battle fixtures. Selection follows the pack's realm bindings and
## unit tables, so tests do not depend on a kingdom or map name.

const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")

static func contact(repo: DataRepository, day: int) -> GameState:
	var state := SuiteData.campaign(repo, 24601)
	state.tick = 1
	state.day = day
	for arm: String in repo.army_speed:
		repo.army_speed[arm] = 1
	for ground: String in repo.army_ground_speed:
		repo.army_ground_speed[ground] = 1000
	for key: String in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1}
	repo.law_effects = repo.law_effects.filter(func(row: Dictionary) -> bool:
		return String(row.get("channel", "")) != "pace")
	repo.balance["army_clearance_on"] = 0.0
	repo.balance["battle_contact_km"] = 0.0
	state.foes.clear()
	state.ai_hosts.clear()
	var mine: Array = Play.land_regiments(repo, 1)
	var host: Dictionary = repo.raid_hosts[0]
	var enemies: Array = EnemyAi.host_units(repo, null, host)
	var player_code := String(mine[0])
	var foe_code := String(enemies[0])
	var player_reg := ArmySystem.regiment(repo, player_code, state)
	var spot := ArmySystem.pack_to_metres(repo, Vector2(float(player_reg["x"]), float(player_reg["y"])))
	Play.park_army(repo, state, spot)
	var contact_point := spot + Vector2i(2000, 0)
	Play.place(repo, state, player_code, spot, ArmySystem.ORDER_MARCH)
	state.regiments[player_code]["carry_days"] = 10
	state.regiments[player_code]["morale"] = 100
	state.regiments[player_code]["training"] = 100
	state.regiments[player_code]["supplies"] = ArmySystem.supply_use(repo,
		ArmySystem.regiment(repo, player_code, state), state) * 6
	state.regiments[player_code]["dest_x_m"] = spot.x + 5000
	state.regiments[player_code]["dest_y_m"] = spot.y
	var foe := ArmySystem.starting_state(repo, ArmySystem.regiment(repo, foe_code))
	foe["x_m"] = contact_point.x
	foe["y_m"] = contact_point.y
	foe["dest_x_m"] = contact_point.x - 10000
	foe["dest_y_m"] = spot.y
	foe["order"] = ArmySystem.ORDER_MARCH
	foe["carry_days"] = 10
	foe["morale"] = 100
	foe["training"] = 100
	foe["supplies"] = ArmySystem.supply_use(repo, ArmySystem.regiment(repo, foe_code), state) * 6
	state.foes[foe_code] = foe
	return state


static func two_battles(repo: DataRepository, day: int) -> GameState:
	var state := contact(repo, day)
	var mine: Array = Play.land_regiments(repo, 1)
	if mine.size() < 2 and not mine.is_empty():
		var source_player := String(mine[0])
		var alias_player := source_player + "_fixture_2"
		var player_row: Dictionary = state.army_roster[source_player].duplicate(true)
		player_row["regiment_code"] = alias_player
		state.army_roster[alias_player] = player_row
		state.regiments[alias_player] = state.regiments[source_player].duplicate(true)
		mine.append(alias_player)
	var enemy_codes: Array = []
	for host: Dictionary in repo.raid_hosts:
		enemy_codes.append_array(EnemyAi.host_units(repo, null, host))
	enemy_codes = enemy_codes.filter(func(code: String) -> bool: return not state.foes.has(code))
	enemy_codes.sort()
	if enemy_codes.is_empty():
		var source_foe := String(state.foes.keys()[0])
		var alias_foe := source_foe + "_fixture_2"
		var foe_row: Dictionary = state.army_roster[source_foe].duplicate(true)
		foe_row["regiment_code"] = alias_foe
		state.army_roster[alias_foe] = foe_row
		enemy_codes.append(alias_foe)
	var second_player := String(mine[1])
	var second_foe := String(enemy_codes[0])
	var first_foe := String(state.foes.keys()[0])
	var origin_reg := ArmySystem.regiment(repo, second_player, state)
	var second_at := ArmySystem.pack_to_metres(repo,
		Vector2(float(origin_reg["x"]), float(origin_reg["y"])))
	var first_at := Vector2i(int(state.regiments[String(mine[0])]["x_m"]),
		int(state.regiments[String(mine[0])]["y_m"]))
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	if second_at.distance_to(first_at) <= reach * 2:
		second_at = first_at + Vector2i(maxi(reach * 3, 30000), 0)
	Play.place(repo, state, second_player, second_at, ArmySystem.ORDER_MARCH)
	state.regiments[second_player]["carry_days"] = 10
	state.regiments[second_player]["morale"] = 100
	state.regiments[second_player]["training"] = 100
	state.regiments[second_player]["supplies"] = ArmySystem.supply_use(repo,
		ArmySystem.regiment(repo, second_player, state), state) * 6
	state.regiments[second_player]["dest_x_m"] = second_at.x + 600
	var second := ArmySystem.starting_state(repo, ArmySystem.regiment(repo, second_foe))
	second["x_m"] = second_at.x + 600
	second["y_m"] = second_at.y
	second["dest_x_m"] = second_at.x
	second["dest_y_m"] = second_at.y
	second["order"] = ArmySystem.ORDER_MARCH
	second["carry_days"] = 10
	second["morale"] = 100
	second["training"] = 100
	second["supplies"] = ArmySystem.supply_use(repo, ArmySystem.regiment(repo, second_foe), state) * 6
	state.foes[second_foe] = second
	return state


static func roundtrip(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true)))
