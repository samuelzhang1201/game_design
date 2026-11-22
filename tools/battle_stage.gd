extends RefCounted
## A real battle staged through the engine for a shot or a bench (no fake panel,
## no hand-written result): one hostile column put within contact range of an
## own unit, then the game day entry point. With `arm` (a code suffix, e.g.
## foot) it is a FIELD battle of that arm: the first own unit of it with open
## dry ground 3 km off its camp leaves it for there, the first such foe 1 km
## beyond. Shared by tools/snapshot_screen.gd (--battle-case / --battle-arm) and
## tools/map3d/bench.gd (--battle-arm). Returns the own unit's code ("" none).


static func stage(arm: String) -> String:
	var ours: Array = []
	for code: String in Game.state.regiments:
		if not ArmySystem.is_naval(Game.data, Game.state, code) and (arm == "" or code.ends_with("_" + arm)):
			ours.append(code)
	ours.sort()
	var foes := Game.state.foes.keys().filter(func(c: String) -> bool: return arm == "" or c.ends_with("_" + arm))
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
