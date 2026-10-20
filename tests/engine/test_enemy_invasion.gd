extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const RunDir := preload("res://tests/run_dir.gd")
const Play := preload("res://tests/invasion_play.gd")
## The invasion on the real day loop (spec 2026-10-07-enemy-ai-and-battle-design
## §2 timeline, §3): TickEngine runs the hosts' minds once a day between the
## march and the battles, the border rumour reaches the crown
## raid_rumour_lead_days before the first host crosses, a spy who stands near a
## foe column counts it, the hosts' moves are told in a letter, and the whole
## run is deterministic and whole-numbered. No player order is given.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


## --- helpers ----------------------------------------------------------------

## A campaign after its opening tick (GameRoot's): tick 1, day 1.
func _opened(engine: TickEngine) -> GameState:
	var s := Play.opened(repo, engine)
	assert_eq(s.absolute_day(), 1)
	return s


## One day, exactly as Game.advance_day plays it: the thirtieth is the tick.
func _day(engine: TickEngine, s: GameState) -> void:
	Play.day(engine, s, true)


## Plays days until the absolute day `last` has ended.
func _play_through(engine: TickEngine, s: GameState, last: int) -> void:
	Play.play_through(engine, s, last, true)


func _host(role: String) -> String:
	return Play.host(repo, role)


func _first_appear() -> int:
	return Play.first_appear(repo)


func _letters(s: GameState, kind: String) -> Array:
	# Field reports arrive through local battle letters or remote king-report couriers.
	if kind == "battle":
		return Play.letters(s, kind) + Play.letters(s, "king_report")
	return Play.letters(s, kind)


func _texts(m: Dictionary) -> Array:
	var out: Array = [String(m["title"])]
	for f: Dictionary in m["facts"]:
		out.append(String(f.get("text", "")))
	return out


func _has_digit(text: String) -> bool:
	var re := RegEx.new()
	re.compile("[0-9]")
	return re.search(text) != null


func _floats_in(v: Variant, path: String, out: Array) -> void:
	Play.floats_in(v, path, out)


## --- the rumour (spec §2: about day 8, vague, source "rumour") ------------------

func test_rumour_arrives_before_the_invasion() -> void:
	var engine := TickEngine.new(repo)
	var s := _opened(engine)
	var on := _first_appear() - int(repo.bal("raid_rumour_lead_days"))
	assert_gt(on, 1, "the pack's timeline leaves room for the rumour")
	_play_through(engine, s, on - 1)
	assert_eq(_letters(s, "rumour").size(), 0, "no rumour before its day")
	_play_through(engine, s, on)
	var rumours := _letters(s, "rumour")
	assert_eq(rumours.size(), 1, "one rumour, as day %d ends" % on)
	if rumours.is_empty():
		return
	var m: Dictionary = rumours[0]
	assert_eq(int(m["day"]), on, "dated the day it came")
	assert_eq(String(m["column"]), "rumour", "filed as rumour")
	assert_gt((m["facts"] as Array).size(), 0, "it says something")
	# the place is the pack's name, which may carry a numeral of its own
	var first := ""
	for h: Dictionary in repo.raid_hosts:
		if first == "" and int(h["appear_day"]) == _first_appear():
			first = String(h["host_code"])
	var place := Intel.place_label(repo, s, ArmySystem.metres_to_pack(repo, EnemyAi.home_m(repo, first)))
	assert_true(" ".join(_texts(m)).contains(place), "it says where they gather: " + place)
	for t: String in _texts(m):
		assert_false(_has_digit(t.replace(place, "")), "a rumour gives no figure: " + t)
		assert_false(t.contains("[missing template"), "its words are in templates.csv: " + t)
		assert_false(t.contains("{"), "every slot filled: " + t)
	var raider := repo.realm_label("raider_realm")
	assert_true(" ".join(_texts(m)).contains(raider), "it names the raider realm through its slot")
	_play_through(engine, s, on + 3)
	assert_eq(_letters(s, "rumour").size(), 1, "and only once")


func test_rumour_templates_spell_no_kingdom() -> void:
	# the raw file: DataRepository fills the realm slots at load
	var raw := FileAccess.get_file_as_string("res://data/council/templates.csv")
	var found := 0
	for line: String in raw.split("\n"):
		if line.begins_with("raid_rumour,") or line.begins_with("host_news_") and not line.begins_with("host_news_title"):
			found += 1
			assert_true(line.contains("{raider_realm}"), "the realm by its slot: " + line)
			assert_false(_has_digit(line), "fixed prose with no figure: " + line)
			for k: Variant in repo.kingdoms:
				var label := String((repo.kingdoms[k] as Dictionary).get("label", ""))
				if label != "":
					assert_false(line.contains(label), "a template names no kingdom: " + line)
	assert_gt(found, 0, "the rumour's words are rows of templates.csv")


func test_warnings_are_once_and_only_for_a_campaign_with_hosts() -> void:
	var s := SuiteData.campaign(repo, 11)
	var on := _first_appear() - int(repo.bal("raid_rumour_lead_days"))
	s.tick = 1
	s.day = on - 1
	assert_eq(EnemyAi.warnings(repo, s), [], "not the day before")
	s.day = on
	assert_eq(EnemyAi.warnings(repo, s).size(), 1, "the day itself")
	s.day = on + 1
	assert_eq(EnemyAi.warnings(repo, s), [], "not the day after")
	var old := SuiteData.campaign(repo, 11)
	old.foes = {}
	old.ai_hosts = {}
	old.tick = 1
	old.day = on
	assert_eq(EnemyAi.warnings(repo, old), [], "a save without hosts hears nothing")


## --- the scout (spec §2: about day 12, a spy's credible report) -------------------

func test_scout_report_names_a_credible_estimate() -> void:
	var s := SuiteData.campaign(repo, 11)
	s.tick = 1
	s.day = 12
	var main := _host("main")
	var codes := EnemyAi.regiments_of(s, main)
	assert_gt(codes.size(), 0)
	var first: Dictionary = s.foes[codes[0]]
	var at := ArmySystem.metres_to_pack(repo, Vector2i(int(first["x_m"]), int(first["y_m"])))
	# the truth within the spy's reach: columns and men under arms
	var reach := int(round(repo.bal("spy_radius_km") * 1000.0))
	var cols := 0
	var men := 0
	for c: Variant in s.foes:
		var e: Dictionary = s.foes[c]
		var d := Vector2(float(e["x_m"]), float(e["y_m"])).distance_to(Vector2(float(first["x_m"]), float(first["y_m"])))
		if d <= float(reach):
			cols += 1
			men += ArmySystem.headcount(repo, ArmySystem.regiment(repo, String(c))) - int(e.get("dead", 0))
	assert_gt(men, 0)
	var r := SpySystem.report(repo, s, at, 999, 0)
	assert_eq(String(r["column"]), "credible", "a good spy's report is credible")
	var facts := {}
	for f: Dictionary in r["facts"]:
		facts[String(f["key"])] = f
	assert_true(facts.has("foe_columns"), "how many columns")
	assert_true(facts.has("foe_troops"), "about how many men")
	if facts.has("foe_columns") and facts.has("foe_troops"):
		assert_true(int(facts["foe_columns"]["lo"]) <= cols and cols <= int(facts["foe_columns"]["hi"]),
			"columns %d within the estimate" % cols)
		assert_true(int(facts["foe_troops"]["lo"]) <= men and men <= int(facts["foe_troops"]["hi"]),
			"men %d within the estimate" % men)
		assert_lt(int(facts["foe_troops"]["lo"]), int(facts["foe_troops"]["hi"]), "an estimate, never the exact roll")
		assert_eq(String(facts["foe_troops"]["label"]),
			String((repo.intel_facts["foe_troops"] as Dictionary)["label"]), "labelled by intel_facts.csv")
	# a spy far from every foe reports none
	var home := MapManors.home_province(repo, s)
	var prov: Dictionary = repo.provinces[home]
	var far := Vector2(float(prov["center_x"]), float(prov["center_y"]))
	var near_any := false
	for c: Variant in s.foes:
		var e: Dictionary = s.foes[c]
		var p := ArmySystem.metres_to_pack(repo, Vector2i(int(e["x_m"]), int(e["y_m"])))
		near_any = near_any or p.distance_to(far) * float(ArmySystem.metres_per_pack_px(repo)) <= float(reach)
	if not near_any:
		var keys: Array = (SpySystem.report(repo, s, far, 999, 0)["facts"] as Array).map(
			func(f: Dictionary) -> String: return String(f["key"]))
		assert_false("foe_columns" in keys, "no foe in reach, no foe fact")


## --- the wiring (spec §7: march → couriers → minds → battles) ----------------------

func test_the_minds_run_once_a_day_through_the_tick() -> void:
	# nothing within reach: every host withdraws where it stands (its home),
	# so it eats each day where it stands, the same ground every day
	repo.balance["ai_target_reach_km"] = 0.0
	var engine := TickEngine.new(repo)
	var s := _opened(engine)
	var main := _host("main")
	var appear := _first_appear()
	_play_through(engine, s, appear)
	assert_eq(String(s.ai_hosts[main]["mode"]), "WITHDRAW", "nothing worth taking: home")
	var c0: String = EnemyAi.regiments_of(s, main)[0]
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c0), s)
	var before := int(s.foes[c0]["supplies"])
	var last := Calendar.DAYS_PER_TICK + 2      # through the thirtieth day's tick
	var eaten := 0
	for d in range(appear + 1, last + 1):
		eaten += ArmySystem.day_bite(use, (d - 1) % Calendar.DAYS_PER_TICK + 1)
	_play_through(engine, s, last)
	assert_eq(int(s.foes[c0]["supplies"]), maxi(0, before - eaten), "one meal a day, the tick's day too")


func test_foes_withdraw_when_nothing_is_worth_it() -> void:
	repo.balance["ai_target_reach_km"] = 0.0
	var engine := TickEngine.new(repo)
	var s := _opened(engine)
	var appear := _first_appear()
	_play_through(engine, s, appear - 1)
	_day(engine, s)
	var modes: Array = engine.day_ai.filter(func(e: Dictionary) -> bool:
		return String(e["type"]) == "host_mode" and String(e["mode"]) == "WITHDRAW")
	assert_gt(modes.size(), 0, "the day's events on the engine (day_ai)")
	for h: String in EnemyAi.host_codes(s):
		if String(s.ai_hosts[h]["mode"]) != "ASSEMBLE":
			assert_eq(String(s.ai_hosts[h]["mode"]), "WITHDRAW", h + " goes home")
	var news := _letters(s, "host_news")
	assert_eq(news.size(), 1, "the day's moves in one letter")
	if news.size() == 1:
		for t: String in _texts(news[0]):
			assert_false(t.contains("[missing template"), t)
			assert_false(t.contains("{"), "every slot filled: " + t)
			for e: Dictionary in modes:
				assert_false(t.contains(String(e["why"])), "the enemy's reasons are not the crown's to read")


## --- the whole invasion, headless ---------------------------------------------------

## Plays `days` days from the opened campaign; returns what it saw.
func _invade(engine: TickEngine, s: GameState, days: int) -> Dictionary:
	var seen := {"targets": {}, "modes": {}, "advanced_on": {}, "events": []}
	for n in days:
		var today := s.absolute_day()
		_day(engine, s)
		seen["events"].append_array(engine.day_ai)
		for h: String in EnemyAi.host_codes(s):
			var m: Dictionary = s.ai_hosts[h]
			if String(m["target_id"]) != "":
				seen["targets"][h] = String(m["target_id"])
			seen["modes"][String(m["mode"])] = true
			if String(m["mode"]) != "ASSEMBLE" and not seen["advanced_on"].has(h):
				seen["advanced_on"][h] = today
	return seen


func test_invasion_runs_headless_for_thirty_five_days() -> void:
	var engine := TickEngine.new(repo)
	var s := _opened(engine)
	var start := {}
	for c: Variant in s.foes:
		start[c] = Vector2i(int(s.foes[c]["x_m"]), int(s.foes[c]["y_m"]))
	var seen := _invade(engine, s, 35)
	for row: Dictionary in repo.raid_hosts:
		var h := String(row["host_code"])
		assert_eq(int(seen["advanced_on"].get(h, -1)), int(row["appear_day"]), h + " leaves ASSEMBLE on its day")
	assert_gt((seen["targets"] as Dictionary).size(), 0, "a host targets something")
	var moved := 0
	for c: Variant in s.foes:
		if Vector2i(int(s.foes[c]["x_m"]), int(s.foes[c]["y_m"])) != start[c]:
			moved += 1
	assert_gt(moved, 0, "the foes march")
	var fought := _letters(s, "battle").size() > 0
	var modes: Dictionary = seen["modes"]
	# with no order given, a host reaches its target: a fight, a siege or a raid
	assert_true(fought or modes.has("SIEGE") or modes.has("RAID"),
		"the invasion is observable: %s, battles %s" % [modes.keys(), fought])
	assert_gt(_letters(s, "host_news").size(), 0, "the crossing is told")
	var floats: Array = []
	_floats_in(s.foes, "foes", floats)
	_floats_in(s.ai_hosts, "ai_hosts", floats)
	_floats_in(s.battles, "battles", floats)
	assert_eq(floats, [], "no float in the foes, the minds or the battles")
	gut.p("invasion: modes %s, targets %s, battles %d, moved %d" % [modes.keys(), seen["targets"],
		_letters(s, "battle").size(), moved])


func test_two_runs_from_one_save_are_identical() -> void:
	var a_engine := TickEngine.new(repo)
	var a := _opened(a_engine)
	var b_engine := TickEngine.new(repo)
	var b := GameState.from_dict(a.to_dict())
	_invade(a_engine, a, 35)
	_invade(b_engine, b, 35)
	assert_eq(SaveLoad.state_hash(a), SaveLoad.state_hash(b), "same save, same days, same state")


func test_save_and_load_mid_invasion_changes_nothing() -> void:
	var a_engine := TickEngine.new(repo)
	var a := _opened(a_engine)
	var b := GameState.from_dict(a.to_dict())
	_invade(a_engine, a, 35)
	var b_engine := TickEngine.new(repo)
	_invade(b_engine, b, 20)
	var path := RunDir.dir("invasion").path_join("mid_invasion.json")
	SaveLoad.save_game(b, path)
	var c := SaveLoad.load_game(path)
	_invade(TickEngine.new(repo), c, 15)
	assert_eq(SaveLoad.state_hash(c), SaveLoad.state_hash(a), "a save mid-invasion plays on the same")


## The minds and their letters draw no random number (spec §3.2): the
## stream's STATE (Rng.to_dict) is the same before and after step_day,
## think_day, warnings and host_news, every day from the rumour through the
## crossing and the march. (The rest of the day loop may draw; not asserted.)
func test_the_minds_and_their_letters_draw_no_random_number() -> void:
	var s := SuiteData.campaign(repo, 11)
	s.tick = 1
	var drawn: Array = []
	var events := 0
	for d in range(_first_appear() - int(repo.bal("raid_rumour_lead_days")), _first_appear() + 12):
		s.day = d
		var before: Dictionary = s.rng.to_dict()
		var ev: Array = EnemyAi.step_day(repo, s)
		ev.append_array(EnemyAi.think_day(repo, s))
		var letters: Array = EnemyAi.warnings(repo, s)
		letters.append(MissiveWriter.host_news(repo, s, ev))
		events += ev.size()
		if s.rng.to_dict() != before:
			drawn.append(d)
		ArmySystem.march_day(repo, s)
	assert_gt(events, 0, "the hosts did something")
	assert_eq(drawn, [], "no day drew from GameState.rng")


## --- contact on the real day loop ------------------------------------------------------

## The player's land regiments with men, in code order.
func _mine() -> Array:
	return Play.land_regiments(repo)


func _place_mine(s: GameState, code: String, at: Vector2i, order: String) -> void:
	Play.place(repo, s, code, at, order)


## The day loop to the main host's crossing, its target held from then on
## (ai_think_days out of the run's reach, so the test reads one plan).
func _crossed(engine: TickEngine) -> GameState:
	repo.balance["ai_think_days"] = 999.0
	var s := _opened(engine)
	_play_through(engine, s, _first_appear())
	var mind: Dictionary = s.ai_hosts[_host("main")]
	assert_eq(String(mind["mode"]), "ADVANCE")
	assert_ne(String(mind["target_id"]), "", "the main host has chosen")
	return s


func test_a_regiment_on_the_hosts_road_is_fought_on_the_day_loop() -> void:
	var engine := TickEngine.new(repo)
	var s := _crossed(engine)
	var main := _host("main")
	var mind: Dictionary = s.ai_hosts[main]
	var lead: Dictionary = s.foes[EnemyAi.regiments_of(s, main)[0]]
	var from := Vector2i(int(lead["x_m"]), int(lead["y_m"]))
	var to := EnemyAi.target_point_m(repo, String(mind["target_kind"]), String(mind["target_id"]))
	# halfway along the straight road the host marches, standing (no garrison)
	var mine: String = _mine()[0]
	@warning_ignore("integer_division")
	_place_mine(s, mine, (from + to) / 2, ArmySystem.ORDER_STANDBY)
	var fought_on := -1
	for n in 15:
		var today := s.absolute_day()
		_day(engine, s)
		if fought_on < 0 and not engine.day_battles.is_empty():
			fought_on = today
	assert_gt(fought_on, 0, "the host ran into the regiment on its road")
	assert_gt(_letters(s, "battle").size(), 0, "and the fight is reported")


func test_a_garrisoned_target_is_besieged_on_arrival_without_a_battle() -> void:
	var engine := TickEngine.new(repo)
	var s := _crossed(engine)
	var main := _host("main")
	var mind: Dictionary = s.ai_hosts[main]
	var town := String(mind["target_id"])
	assert_eq(String(mind["target_kind"]), "town", "the main host goes for a town")
	var mine: String = _mine()[0]
	_place_mine(s, mine, EnemyAi.target_point_m(repo, "town", town), ArmySystem.ORDER_GARRISON)
	assert_eq(ArmyGround.garrison_town(repo, s, mine), town, "the town is garrisoned")
	var arrived := -1
	for n in 20:
		var today := s.absolute_day()
		_day(engine, s)
		var siege := engine.day_ai.filter(func(e: Dictionary) -> bool:
			return String(e["type"]) == "host_mode" and String(e["host"]) == main and String(e["mode"]) == "SIEGE")
		if not siege.is_empty():
			arrived = today
			assert_eq(engine.day_battles, [], "no battle the day deployment begins")
			assert_eq(s.battles, [], "no assault before SiegeSystem (Task 9)")
			break
		assert_eq(engine.day_battles, [], "no battle on the road, day %d" % today)
	assert_gt(arrived, 0, "the leading columns reached the town and began deployment")
	assert_eq(String(s.ai_hosts[main]["mode"]), "SIEGE")
	assert_true(SiegeSystem.besieged(repo, s, town))
	gut.p("deployment before %s begun on day %d" % [town, arrived])

