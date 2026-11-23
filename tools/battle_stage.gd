extends RefCounted
## A real battle staged through the engine for a shot or a bench (no fake panel,
## no hand-written result): one hostile column put within contact range of an
## own unit, then the game day entry point. With `arm` (a code suffix, e.g.
## foot) it is a FIELD battle of that arm: the first own unit of it with open
## dry ground 3 km off its camp leaves it for there, the first such foe 1 km
## beyond. Shared by tools/snapshot_screen.gd (--battle-case / --battle-arm) and
## tools/map3d/bench.gd (--battle-arm). Returns the own unit's code ("" none).
## `foe_arm` (default `arm`) picks the foe by its own code suffix: an arm the
## realms do not field (the axemen) fights the foe's foot.
## stage_militia is the siege that raises a town militia (--battle-case militia).


## Raises a unit of `arm` through the recruitment panel's own order (ARMY_RECRUIT)
## at the crown's first town, from its rural folk, and plays the days until it
## stands. Its code ends in `_<suffix>` so `stage` finds it. Returns it ("" none).
static func raise(arm: String, suffix: String) -> String:
	var realm := Game.data.resolve_realm("player_realm")
	var towns := Game.data.burgs.keys().filter(func(t: String) -> bool:
		return String(Game.data.burgs[t]["kingdom_code"]) == realm and ArmyGround.holds(Game.data, Game.state, realm, t))
	towns.sort()
	var officers := RecruitmentSystem.available_commanders(Game.data, Game.state, arm)
	if towns.is_empty() or officers.is_empty():
		push_error("raise %s: no held town or no commander" % arm)
		return ""
	var request := {"request_id": "raise_" + suffix, "mode": "new", "arm": arm, "total": 600,
		"source_province": String(Game.data.burgs[towns[0]]["province_code"]), "source_population_field": "rural_population",
		"assembly_town": towns[0], "noble_permille": 0, "commander_id": officers[0]}
	var done := Game.try_execute(ActionRequest.make("ARMY_RECRUIT", request))
	if not bool(done.get("ok", false)):
		push_error("raise %s: %s" % [arm, done.get("error", done)])
		return ""
	var code := "recruited:raise_" + suffix
	for day: int in 10:
		if MilitaryRoster.fit(Game.state, code) > 0:
			break
		Game.advance_day()
	print("raised %s: %s (%d fit)" % [arm, code, MilitaryRoster.fit(Game.state, code)])
	return code


static func stage(arm: String, foe_arm := "") -> String:
	if foe_arm == "":
		foe_arm = arm
	var ours: Array = []
	for code: String in Game.state.regiments:
		if not ArmySystem.is_naval(Game.data, Game.state, code) and (arm == "" or code.ends_with("_" + arm)):
			ours.append(code)
	ours.sort()
	var foes := Game.state.foes.keys().filter(func(c: String) -> bool: return foe_arm == "" or c.ends_with("_" + foe_arm))
	foes.sort()
	if ours.is_empty() or foes.is_empty():
		push_error("battle encounter showcase needs two real armies")
		return ""
	var own: Dictionary = Game.state.regiments[ours[0]]
	var foe: Dictionary = Game.state.foes[foes[0]]
	var off := Vector2i(1000, 0)
	if arm != "":  # a field battle: the unit leaves its camp for open dry ground, the foe 1 km beyond
		var grid := MarchPath.of_pack(Game.data)
		var found := false
		for code: String in ours:
			var at := Vector2i(int(Game.state.regiments[code]["x_m"]), int(Game.state.regiments[code]["y_m"]))
			for d: Vector2i in [Vector2i(1000, 0), Vector2i(-1000, 0), Vector2i(0, 1000), Vector2i(0, -1000)]:
				var spot := at + d * 3
				if found or not grid.clear(spot, spot + d) or grid.is_water(grid.cell_of(spot)) \
						or grid.is_water(grid.cell_of(spot + d)) \
						or ArmySystem.town_at(Game.data, ArmySystem.metres_to_pack(Game.data, spot)) != "" \
						or Game.state.regiments.keys().any(func(o: String) -> bool: return o != code \
							and not ArmySystem.is_naval(Game.data, Game.state, o) and Vector2(spot + d).distance_to(
							Vector2(int(Game.state.regiments[o]["x_m"]), int(Game.state.regiments[o]["y_m"]))) < 6000.0):
					continue  # no other unit of ours in the battle's reach
				ArmyGround.leave(Game.data, Game.state, code)
				own = Game.state.regiments[code]
				for k: String in ["x_m", "dest_x_m"]:
					own[k] = spot.x
				for k: String in ["y_m", "dest_y_m"]:
					own[k] = spot.y
				ours = [code]
				off = d
				found = true
	foe["x_m"] = int(own["x_m"]) + off.x
	foe["y_m"] = int(own["y_m"]) + off.y
	foe["dest_x_m"] = foe["x_m"]
	foe["dest_y_m"] = foe["y_m"]
	foe["order"] = ArmySystem.ORDER_STANDBY
	Game.advance_day()
	print("battle staged: %s vs %s" % [ours[0], foes[0]])
	return String(ours[0])


## A crown town with no defenders invested by the main raid host, so it raises
## its militia (SiegeRecord.ensure_for -> TownMilitia.raise): the host's columns
## stood at the first such town (code order, never the capital) and its mind
## set on the siege. With `fight` the days then run through the game's day
## entry point (each encounter notice acknowledged through Game) until the
## siege's assault is fought and the militia stands in its battle. Returns the
## militia's code ("" none).
static func stage_militia(fight := false) -> String:
	var repo: DataRepository = Game.data
	var s: GameState = Game.state
	var main := ""
	for h: Dictionary in repo.raid_hosts:
		if main == "" and String(h["role"]) == "main":
			main = String(h["host_code"])
	var towns: Array = repo.burgs.keys()
	towns.sort()
	for town: String in towns:
		if SiegeSystem.holder_of(repo, s, town) != repo.resolve_realm("player_realm") \
				or ArmyGround.seat_of(repo, s, town) != "" or String(repo.burgs[town].get("is_capital", "0")) == "1" \
				or not SiegeSystem.defenders_of(repo, s, town).is_empty() or not s.ai_hosts.has(main):
			continue
		var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
		for c: String in EnemyAi.regiments_of(s, main):
			var e: Dictionary = s.foes[c]
			for k: String in ["x_m", "dest_x_m"]:
				e[k] = at.x
			for k: String in ["y_m", "dest_y_m"]:
				e[k] = at.y
			e["order"] = ArmySystem.ORDER_GARRISON
		var mind: Dictionary = s.ai_hosts[main]
		mind["mode"] = EnemyAi.MODE_SIEGE
		mind["target_kind"] = EnemyAi.KIND_TOWN
		mind["target_id"] = town
		var militia: Array = SiegeRecord.ensure_for(repo, s, main).get("militia", [])
		print("militia staged at %s: %s" % [town, militia])
		if militia.is_empty():
			return ""
		var code := String(militia[0])
		for _day in (int(repo.bal("siege_assault_days")) + 3 if fight else 0):
			if not BattleSystem.battle_of(s, code).is_empty():
				break
			Game.advance_day()
			if not Game.pending_battle_decision().is_empty():
				Game.resolve_battle_decision(String(Game.pending_battle_decision()["token"]), "continue")
		if fight:
			print("militia battle on day %d: %s" % [s.absolute_day(), BattleSystem.battle_of(s, code).get("id", "none")])
		return code
	push_error("militia showcase: no empty crown town")
	return ""
