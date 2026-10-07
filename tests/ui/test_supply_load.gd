extends GutTest
## Final review 11: an old save is migrated as it loads (Game.load_campaign
## runs ArmySystem.ensure), not on the first day — its regiments read the
## carried load and no more than a train can carry the moment it is shown.

func test_an_old_save_reads_its_load_as_it_loads() -> void:
	Game.start_campaign(42)
	Game.set_clock_speed(0)
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break
	var entry: Dictionary = Game.state.regiments[code]
	entry.erase("carry_days")   # as a save from before the carried load
	entry["supplies"] = 1000000
	assert_true(Game.save_campaign())
	assert_true(Game.load_campaign())
	var back: Dictionary = Game.state.regiments[code]
	assert_eq(int(back["carry_days"]), int(Game.data.bal("army_carry_default_days")))
	var use := ArmySystem.supply_use(Game.data, ArmySystem.regiment(Game.data, code), Game.state)
	assert_eq(int(back["supplies"]), ArmySystem.max_units(Game.data, use), "no more than a train carries")
