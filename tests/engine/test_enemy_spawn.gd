extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The raid hosts take the field (spec 2026-10-07-enemy-ai-and-battle-design
## §2): every row of the pack's raid_hosts.csv raises the UNITS split from its
## pack regiments (EnemyAi.host_units, the army split) as foes in
## GameState.foes (never in regiments) and a mind in GameState.ai_hosts,
## stands at its assembly point until its appear_day, and marches EVENLY as
## the player's columns do. A raised unit leaves its camp and seat.

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()


func before_each() -> void:
	Intel.dev_all = false


func after_each() -> void:
	Intel.dev_all = false


func _all_foe_codes() -> Array:
	var out: Array = []
	for h: Dictionary in repo.raid_hosts:
		out.append_array(EnemyAi.host_units(repo, null, h))
	out.sort()
	return out


## --- the units a host raises ------------------------------------------------

func test_a_pack_regiment_raises_its_land_units() -> void:
	var raider := repo.resolve_realm("raider_realm")
	var pack: Dictionary = repo.world_table("military", "regiments")
	for h: Dictionary in repo.raid_hosts:
		for entry: String in h["regiments"]:
			var units := EnemyAi.host_units(repo, null, {"regiments": [entry]})
			assert_false(units.is_empty(), entry + " raises units")
			var sorted_units := units.duplicate()
			sorted_units.sort()
			assert_eq(units, sorted_units, "in code order")
			# the headcount of its foot, archers and horse, every man of them
			# (its guns are its kingdom's royal train's, which no host takes)
			var row: Dictionary = pack[entry]
			var want := 0
			var equipment := {"infantry": 0, "archers": 0, "cavalry": 0}
			for arm: String in equipment:
				want += int(row.get(arm, 0)) * int(repo.world_row("military", "unit_types", arm)["crew"])
			var men := 0
			for u: String in units:
				var r := ArmySystem.regiment(repo, u)
				assert_eq(String(r["parent_code"]), entry, u + " is split from " + entry)
				assert_eq(String(r["kingdom_code"]), raider)
				assert_ne(String(r.get("is_naval", "0")), "1", "no fleet")
				men += ArmySystem.headcount(repo, r)
				for arm: String in equipment:
					equipment[arm] += int(r.get(arm, 0))
			assert_eq(men, want, entry + ": the regiment's personnel, split")
			for arm: String in equipment:
				assert_eq(int(equipment[arm]), int(row.get(arm, 0)), "equipment remains conserved: " + arm)
	# a unit's own code raises that unit; an unknown code raises nothing; and
	# a unit named twice is raised once
	var one := String(EnemyAi.host_units(repo, null, repo.raid_hosts[0])[0])
	assert_eq(EnemyAi.host_units(repo, null, {"regiments": [one, one]}), [one])
	assert_eq(EnemyAi.host_units(repo, null, {"regiments": ["no_such_regiment"]}), [])


## --- spawning -------------------------------------------------------------

func test_new_campaign_spawns_every_host() -> void:
	var s := SuiteData.campaign(repo, 11)
	assert_gt(repo.raid_hosts.size(), 0, "the pack ships hosts")
	assert_eq(EnemyAi.host_codes(s).size(), repo.raid_hosts.size())
	var seen := 0
	for h: Dictionary in repo.raid_hosts:
		var code := String(h["host_code"])
		assert_true(s.ai_hosts.has(code), code)
		assert_eq(s.ai_hosts[code], {"mode": "ASSEMBLE", "target_kind": "", "target_id": "",
			"think_day": 0, "plunder": 0, "siege_progress": 0}, "the mind of " + code)
		var start := ArmySystem.pack_to_metres(repo, Vector2(float(h["start_x"]), float(h["start_y"])))
		var first := true
		for rc: String in EnemyAi.host_units(repo, s, h):
			seen += 1
			assert_true(s.foes.has(rc), rc)
			var f: Dictionary = s.foes[rc]
			assert_eq(String(f["host"]), code)
			var at := Vector2i(int(f["x_m"]), int(f["y_m"]))
			if first:
				# unit clearance (spec 2026-10-14): the first unit stands ON the
				# assembly point, the rest are spread round it (test_army_clearance.gd)
				assert_eq(at, start, "the first unit stands at the assembly point")
				first = false
			else:
				assert_lte(Vector2(at - start).length(), 3.0 * float(repo.bal("army_slot_spacing_m")) + 100.0, "the rest camp round the assembly point (three rings at most)")
			assert_eq(Vector2i(int(f["dest_x_m"]), int(f["dest_y_m"])), at)
			assert_eq(String(f["order"]), ArmySystem.ORDER_STANDBY)
			# the shape of a regiment's state, plus the host
			var shape := ArmySystem.starting_state(repo, ArmySystem.regiment(repo, rc, s))
			for k: String in shape:
				assert_true(f.has(k), "%s has %s" % [rc, k])
			assert_eq(int(f["supplies"]), int(shape["supplies"]))
			assert_eq(int(f["morale"]), int(shape["morale"]))
	assert_eq(s.foes.size(), seen, "no foe but the hosts'")
	# a raised unit left its camp and seat: no foe holds a town
	for town: String in s.town_seat:
		assert_false(ArmySystem.is_foe(s, String(s.town_seat[town])), town + "'s seat is no foe's")
	for rc: String in s.foes:
		assert_eq(String(s.foes[rc]["camp_town"]), "", rc + " camps by no town")
		assert_eq(ArmyGround.seated_in(repo, s, rc), "")
		assert_eq(ArmyGround.camped_by(repo, s, rc), "")
		assert_eq(ArmyGround.garrison_town(repo, s, rc), "")


func test_host_codes_and_regiments_of() -> void:
	var s := SuiteData.campaign(repo, 11)
	var codes := EnemyAi.host_codes(s)
	var sorted_codes := codes.duplicate()
	sorted_codes.sort()
	assert_eq(codes, sorted_codes, "dictionary order")
	for h: Dictionary in repo.raid_hosts:
		var mine := EnemyAi.regiments_of(s, String(h["host_code"]))
		assert_eq(mine, EnemyAi.host_units(repo, s, h), "the units of " + String(h["host_code"]))
	assert_eq(EnemyAi.regiments_of(s, "no_such_host"), [])


func test_spawn_is_deterministic_and_leaves_the_rng_alone() -> void:
	var a := GameState.new_campaign(repo, 5)
	var b := GameState.new_campaign(repo, 5)
	assert_eq(a.to_dict(), b.to_dict())
	var spawned := GameState.new()
	spawned.rng = Rng.new(5)
	var untouched := GameState.new()
	untouched.rng = Rng.new(5)
	EnemyAi.spawn(repo, spawned, repo.raid_hosts[0])
	assert_eq(spawned.rng.randi_range(0, 999999), untouched.rng.randi_range(0, 999999),
		"spawning draws no random number")


func test_foes_survive_the_save() -> void:
	var s := SuiteData.campaign(repo, 11)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.foes, s.foes)
	assert_eq(back.ai_hosts, s.ai_hosts)


## --- foes are not the player's -------------------------------------------

func test_foes_are_not_in_player_regiments() -> void:
	var s := SuiteData.campaign(repo, 11)
	for rc: String in _all_foe_codes():
		assert_false(s.regiments.has(rc), "%s is not a player regiment" % rc)
		assert_true(ArmySystem.is_foe(s, rc))
	ArmySystem.ensure(repo, s)
	ArmySystem.settle_month(repo, s)
	ArmySystem.eat_day(repo, s)
	ArmySystem.hunger_day(repo, s)
	for rc: String in _all_foe_codes():
		assert_false(s.regiments.has(rc), "still not, after the player-only passes")
	for rc: Variant in s.regiments:
		assert_false(s.foes.has(rc), "a player regiment is never a foe")


func test_a_foe_is_seated_once_at_its_foe_position() -> void:
	var s := SuiteData.campaign(repo, 11)
	var h: Dictionary = repo.raid_hosts[0]
	var rc := String(EnemyAi.host_units(repo, s, h)[0])
	var reg := ArmySystem.regiment(repo, rc, s)
	var at := ArmySystem.position_of(repo, s, reg)
	var start := ArmySystem.pack_to_metres(repo, Vector2(float(h["start_x"]), float(h["start_y"])))
	assert_eq(ArmySystem.pack_to_metres(repo, at), start, "every reader finds the first unit at the assembly point")
	# no town of the raider realm keeps a raised unit on its seat or in its
	# camp: a seat one held went to the camp it left (ArmyGround.refill)
	var raider := repo.resolve_realm("raider_realm")
	for r: Dictionary in MapObjects.regiments_of(repo, raider, s):
		var c := String(r["regiment_code"])
		if ArmySystem.is_foe(s, c):
			assert_eq(ArmyGround.seated_in(repo, s, c), "", c + " holds no seat")
			assert_eq(ArmyGround.camped_by(repo, s, c), "", c + " camps by no town")
	# a hostile regiment cutting a road is counted once per regiment, at its foe place
	var diplomacy: Dictionary = repo.world_table("political", "diplomacy")
	var key := "%s>%s" % [repo.resolve_realm("player_realm"), raider]
	var was := String(diplomacy[key]["stance"])
	diplomacy[key]["stance"] = "Enemy"
	var hostiles := SupplyLines._hostiles(repo, s)
	diplomacy[key]["stance"] = was
	var here := 0
	var on_point := 0
	for hs: Array in hostiles:
		var m := ArmySystem.pack_to_metres(repo, hs[0])
		if m == start:
			on_point += 1
		if Vector2(m - start).length() <= 3.0 * float(repo.bal("army_slot_spacing_m")) + 100.0:   # the units are spread round the point (clearance)
			here += 1
	assert_eq(on_point, 1, "the first unit stands on its point")
	assert_gte(here, EnemyAi.host_units(repo, s, h).size(), "the host is round its point")
	var old_home := ArmySystem.pack_to_metres(repo, Vector2(float(reg["x"]), float(reg["y"])))
	if old_home != start:
		for hs: Array in hostiles:
			assert_ne(ArmySystem.pack_to_metres(repo, hs[0]), old_home, "no ghost left at the pack's own quarters")
	assert_eq(hostiles.size(), MapObjects.regiments_of(repo, raider, s).size(), "each unit once")


func test_supply_lines_and_ledger_do_not_see_foes() -> void:
	var s := SuiteData.campaign(repo, 11)
	var foes := _all_foe_codes()
	var events := SupplyLines.day_step(repo, s)
	var text := str(events) + str(SupplyLines.warn_day(repo, s))
	for rc: String in foes:
		assert_false(text.contains(rc), "supply news names no foe")
		assert_eq(SupplyLines.line(s, rc), {}, "no supply line for " + rc)
	for row: Dictionary in repo.ledger_links:
		if String(row["status"]) != "live":
			continue
		var out := str(LedgerResolvers.run(row, repo, s, {}))
		for rc: String in foes:
			assert_false(out.contains(rc), "%s names %s" % [row["link_id"], rc])
	for nm: String in ["regiments"]:
		var ids := str(LedgerResolvers.instances(nm, repo, s))
		for rc: String in foes:
			assert_false(ids.contains(rc), "the LEDGER's %s omit %s" % [nm, rc])


func test_the_daily_meal_and_hunger_leave_foes_alone() -> void:
	var s := SuiteData.campaign(repo, 11)
	var before := s.foes.duplicate(true)
	for i in 5:
		ArmySystem.eat_day(repo, s)
		ArmySystem.hunger_day(repo, s)
	assert_eq(s.foes, before)


## --- the host's mind -----------------------------------------------------

func _at_day(s: GameState, absolute: int) -> void:
	@warning_ignore("integer_division")
	s.tick = 1 + (absolute - 1) / 30
	s.day = 1 + (absolute - 1) % 30
	assert_eq(s.absolute_day(), absolute)


func test_assemble_waits_until_appear_day() -> void:
	for h: Dictionary in repo.raid_hosts:
		var code := String(h["host_code"])
		var appear := int(h["appear_day"])
		var s := SuiteData.campaign(repo, 11)
		_at_day(s, appear - 1)
		for e: Dictionary in EnemyAi.step_day(repo, s):
			assert_ne(String(e.get("host", "")), code, "%s is not up the day before" % code)
		assert_eq(String(s.ai_hosts[code]["mode"]), "ASSEMBLE", "%s waits" % code)
		_at_day(s, appear)
		var events := EnemyAi.step_day(repo, s)
		assert_eq(String(s.ai_hosts[code]["mode"]), "ADVANCE", "%s sets out on its day" % code)
		assert_true(events.any(func(e: Dictionary) -> bool:
			return String(e["type"]) == "host_advance" and String(e["host"]) == code and int(e["day"]) == appear))
		assert_eq(EnemyAi.step_day(repo, s), [], "an advancing host is not reported again")


func test_only_the_hosts_whose_day_it_is_set_out() -> void:
	var s := SuiteData.campaign(repo, 11)
	var earliest := 9999
	var latest := 0
	for h: Dictionary in repo.raid_hosts:
		earliest = mini(earliest, int(h["appear_day"]))
		latest = maxi(latest, int(h["appear_day"]))
	assert_lt(earliest, latest, "the pack's hosts do not all come on one day")
	_at_day(s, earliest)
	var events := EnemyAi.step_day(repo, s)
	var up := 0
	for h: Dictionary in repo.raid_hosts:
		var due := int(h["appear_day"]) <= earliest
		up += 1 if due else 0
		assert_eq(String(s.ai_hosts[String(h["host_code"])]["mode"]), "ADVANCE" if due else "ASSEMBLE",
			String(h["host_code"]))
	assert_eq(events.size(), up, "one event for each host that sets out")
	_at_day(s, latest)
	EnemyAi.step_day(repo, s)
	for h: Dictionary in repo.raid_hosts:
		assert_eq(String(s.ai_hosts[String(h["host_code"])]["mode"]), "ADVANCE")


func test_step_day_never_moves_or_orders_a_foe_by_itself_before_its_day() -> void:
	var s := SuiteData.campaign(repo, 11)
	var before := s.foes.duplicate(true)
	EnemyAi.step_day(repo, s)
	assert_eq(s.foes, before, "the assembly is stood still")


## --- the march ------------------------------------------------------------

## A foe of the first host with real arms, sent `days_x10 / 10` days east.
func _march_foe(s: GameState, days_x10: int) -> String:
	for rc: String in _all_foe_codes():
		if ArmySystem.day_step_m(repo, s, rc) > 0:
			var f: Dictionary = s.foes[rc]
			var step := ArmySystem.day_step_m(repo, s, rc)
			@warning_ignore("integer_division")
			f["dest_x_m"] = int(f["x_m"]) + step * days_x10 / 10
			f["dest_y_m"] = int(f["y_m"])
			f["order"] = ArmySystem.ORDER_MARCH
			return rc
	return ""


func test_foe_marches_with_the_same_even_step() -> void:
	var s := SuiteData.campaign(repo, 11)
	var rc := _march_foe(s, 35)
	assert_ne(rc, "")
	var f: Dictionary = s.foes[rc]
	var from := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, rc))
	var to := ArmySystem.destination_of(repo, s, rc)
	var want := ArmySystem.march_days_between(repo, s, rc, from, to)
	assert_gte(want, 2, "a multi-day march")
	var days := 0
	var last_x := int(f["x_m"])
	while String(f["order"]) == ArmySystem.ORDER_MARCH and days < 40:
		var arrived := ArmySystem.march_day(repo, s)
		days += 1
		s.day += 1
		assert_eq(arrived, [], "a foe's arrival is not news")
		assert_gt(int(f["x_m"]), last_x, "it walks")
		last_x = int(f["x_m"])
	assert_eq(days, want, "arrives on the day march_days_between says")
	assert_eq(String(f["order"]), ArmySystem.ORDER_GARRISON, "and holds the ground")
	assert_eq(int(f["x_m"]), int(f["dest_x_m"]))
	assert_eq(int(f["y_m"]), int(f["dest_y_m"]))
	assert_false(s.regiments.has(rc), "it never entered the player's table")


func test_a_foe_in_a_battle_does_not_march() -> void:
	var s := SuiteData.campaign(repo, 11)
	var rc := _march_foe(s, 50)
	var f: Dictionary = s.foes[rc]
	var x := int(f["x_m"])
	var mine := String((MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0] as Dictionary)["regiment_code"])
	s.battles.append({"id": 1, "att": [rc], "def": [mine], "start_day": 1, "rounds": 1,
		"place_x_m": x, "place_y_m": int(f["y_m"]), "town": ""})
	ArmySystem.march_day(repo, s)
	assert_eq(int(f["x_m"]), x, "a column in a battle stands")
	s.battles.clear()
	ArmySystem.march_day(repo, s)
	assert_gt(int(f["x_m"]), x, "free of it, it marches")


func test_a_foe_that_fell_back_is_walked_home() -> void:
	var s := SuiteData.campaign(repo, 11)
	var rc := _march_foe(s, 30)
	var f: Dictionary = s.foes[rc]
	f["disengaging"] = 1
	var x := int(f["x_m"])
	ArmySystem.march_day(repo, s)
	assert_gt(int(f["x_m"]), x, "a disengaging foe with a march order walks")


func test_a_standing_foe_does_not_move() -> void:
	var s := SuiteData.campaign(repo, 11)
	var before := s.foes.duplicate(true)
	for i in 3:
		ArmySystem.march_day(repo, s)
	assert_eq(s.foes, before)


func test_foes_march_in_code_order_and_the_player_still_arrives_in_the_news() -> void:
	var s := SuiteData.campaign(repo, 11)
	var mine: Dictionary = {}
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			mine = r
			break
	var code := String(mine["regiment_code"])
	var e: Dictionary = s.regiments[code]
	e["dest_x_m"] = int(e["x_m"]) + 10
	e["order"] = ArmySystem.ORDER_MARCH
	var rc := _march_foe(s, 5)
	var arrived := ArmySystem.march_day(repo, s)
	assert_eq(arrived, [code], "the player's arrival is news, the foe's is not")
	assert_eq(String(s.foes[rc]["order"]), ArmySystem.ORDER_GARRISON)
