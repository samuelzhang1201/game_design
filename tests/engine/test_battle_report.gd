extends GutTest
const People := preload("res://tests/fixtures/military_people.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## The battle report and the day hook (spec 2026-10-07-enemy-ai-and-battle-design
## §4.5): TickEngine._end_day settles the battles after the couriers ride, and a
## day with a battle files ONE letter whose numbers are the engine's and whose
## words are templates.csv `battle_*`; a calm day files nothing.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## The player's land units of 400 men or more, in code order.
func _mine() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, r) >= 400:
			out.append(String(r["regiment_code"]))
	out.sort()
	return out


## The raider hosts' units (EnemyAi.host_units) of 400 men or more, in code order.
func _theirs() -> Array:
	var out: Array = []
	for h: Dictionary in repo.raid_hosts:
		for c: String in EnemyAi.host_units(repo, null, h):
			var reg := ArmySystem.regiment(repo, c)
			if String(reg.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, reg) >= 400:
				out.append(c)
	out.sort()
	return out


## A unit's opening ground, in metres (where the tests meet the enemy).
func _spot(_s: GameState, code: String) -> Vector2i:
	var r := ArmySystem.regiment(repo, code)
	return ArmySystem.pack_to_metres(repo, Vector2(float(r["x"]), float(r["y"])))


## A suite campaign with the player's army parked out of the way
## (Play.park_army): a camp round the tests' ground would join their battles.
func _campaign(seed_value: int) -> GameState:
	var s := SuiteData.campaign(repo, seed_value)
	Play.park_army(repo, s, _spot(s, _mine()[0]))
	return s


func _place(s: GameState, code: String, at: Vector2i) -> void:
	var e: Dictionary = s.regiments[code]
	e["x_m"] = at.x
	e["y_m"] = at.y
	e["dest_x_m"] = at.x
	e["dest_y_m"] = at.y
	e["order"] = ArmySystem.ORDER_STANDBY


func _foe(s: GameState, code: String, at: Vector2i) -> void:
	var st := ArmySystem.starting_state(repo, ArmySystem.regiment(repo, code))
	st["x_m"] = at.x
	st["y_m"] = at.y
	st["dest_x_m"] = at.x
	st["dest_y_m"] = at.y
	st["battle_plan"] = "attack"
	s.foes[code] = st


## One outcome row for every eff, so a round's result is known by hand.
func _one_tier(att_loss: int, def_loss: int, share: int, att_morale: int, def_morale: int,
		rout := "none") -> void:
	repo.battle_outcomes.clear()
	repo.battle_outcomes.append({"tier": "hand_made", "eff_min": 0, "eff_max": 1000,
		"attacker_loss_permille": att_loss, "defender_loss_permille": def_loss,
		"wounded_share_permille": share, "attacker_morale": att_morale,
		"defender_morale": def_morale, "rout": rout})
	repo.balance["battle_variance_permille"] = 0.0
	for k: String in repo.battle_stances:
		repo.battle_stances[k]["retreat_odds_permille"] = 0


## A campaign with one foe on top of one of the player's columns: the foe attacks.
func _meeting(seed_value := 7) -> Array:
	var s := _campaign(seed_value)
	var p: String = _mine()[0]
	var f: String = _theirs()[0]
	var at := _spot(s, p)
	_place(s, p, at)
	_foe(s, f, at + Vector2i(1000, 0))
	return [s, p, f]


func _battle_letters(s: GameState) -> Array:
	return s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "battle")


func _text_of(m: Dictionary) -> String:
	var parts: Array = []
	for f: Dictionary in m["facts"]:
		parts.append(String(f.get("text", "")))
	return "\n".join(parts)


func _round_events(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "round")


## --- the hook ---------------------------------------------------------------

func test_battle_day_writes_one_missive() -> void:
	_one_tier(100, 100, 500, -10, -10)
	var m := _meeting()
	var s: GameState = m[0]
	var engine := TickEngine.new(repo)
	Play.day(engine, s, true)
	assert_false(engine.day_battles.is_empty(), "the day's battle events are kept")
	var letters := _battle_letters(s)
	assert_eq(letters.size(), 1, "one letter")
	assert_eq(String(letters[0]["column"]), "credible", "a battle report carries estimates of the foe: never ground truth")
	assert_eq(String(letters[0]["subject"]["kind"]), "regiment")
	assert_eq(String(letters[0]["subject"]["code"]), String(m[1]))
	# the next day the battle goes on: its own letter, still one
	Play.day(engine, s, true)
	assert_eq(_battle_letters(s).size(), 2, "a letter a day while it is fought")


func test_two_battles_in_a_day_are_one_letter() -> void:
	_one_tier(100, 100, 500, -10, -10)
	var mine := _mine()
	var theirs := _theirs()
	if mine.size() < 2 or theirs.size() < 2:
		pending("the pack has fewer than two land regiments a side")
		return
	var s := _campaign(7)
	var far := Vector2i(200_000, 0)
	_place(s, mine[0], _spot(s, mine[0]))
	_place(s, mine[1], _spot(s, mine[0]) + far)
	_foe(s, theirs[0], _spot(s, mine[0]) + Vector2i(1000, 0))
	_foe(s, theirs[1], _spot(s, mine[0]) + far + Vector2i(1000, 0))
	var engine := TickEngine.new(repo)
	Play.day(engine, s, true)
	assert_eq(s.battles.size(), 2, "two battles")
	assert_eq(_round_events(engine.day_battles).size(), 2)
	assert_eq(_battle_letters(s).size(), 1, "one letter for the day")


func test_calm_day_writes_nothing() -> void:
	var s := SuiteData.campaign(repo, 7)
	var engine := TickEngine.new(repo)
	var before := s.missives.size()
	Play.day(engine, s, true)
	assert_true(engine.day_battles.is_empty())
	assert_eq(_battle_letters(s).size(), 0)
	var added: Array = s.missives.slice(before).map(func(x: Dictionary) -> String: return String(x["kind"]))
	assert_false("battle" in added, "a calm day files no battle letter (other kinds are not ours): %s" % str(added))


func test_a_delivered_stance_takes_hold_the_day_the_courier_lands() -> void:
	# settle_day runs AFTER ride_day inside the one day: the day he lands the
	# battles still run on the old stance, but stance_next is the stance by
	# the day's end
	var s := SuiteData.campaign(repo, 7)
	var code: String = _mine()[0]
	var actions := ActionSystem.new(repo)
	actions.execute(ActionRequest.make("ARMY_STANCE", {"regiment": code, "stance": "hold"}), s)
	assert_eq(s.couriers.size(), 1)
	var engine := TickEngine.new(repo)
	for day in int(repo.bal("courier_max_days")):
		Play.day(engine, s, true)
		if s.couriers.is_empty():
			break
	assert_true(s.couriers.is_empty(), "delivered")
	assert_eq(String(s.regiments[code]["stance"]), "hold", "settled in the day's own end")
	assert_false(s.regiments[code].has("stance_next"))


## --- the numbers -------------------------------------------------------------

func test_report_numbers_come_from_the_engine() -> void:
	_one_tier(100, 200, 500, -10, -10)
	var m := _meeting()
	var s: GameState = m[0]
	var engine := TickEngine.new(repo)
	Play.day(engine, s, true)
	var round_ev: Dictionary = _round_events(engine.day_battles)[0]
	var results: Dictionary = round_ev["results"]
	assert_eq(results.size(), 2)
	var text := _text_of(_battle_letters(s)[0])
	var p := String(m[1])
	var f := String(m[2])
	for code: String in results:
		var r: Dictionary = results[code]
		assert_gt(int(r["dead"]) + int(r["wounded"]), 0, "the hand-made tier costs men")
	# our own regiment's losses exactly, the engine's own numbers
	var pr: Dictionary = results[p]
	var p_label := String(ArmySystem.regiment(repo, p)["label"])
	assert_string_contains(text, "%s: %d dead, %d wounded" % [p_label, int(pr["dead"]), int(pr["wounded"])])
	# the enemy's as our men's count: the fog's estimate of its dead and wounded
	var fr: Dictionary = results[f]
	var span := SpySystem.estimate(repo, int(fr["dead"]) + int(fr["wounded"]),
		int(repo.bal("battle_foe_estimate_quality")), 0, int(repo.intel_facts["foe_losses"]["round_to"]))
	assert_string_contains(text, "%d–%d" % [int(span[0]), int(span[1])], "the enemy's losses as a span")
	# and the state agrees with what the letter says (the dead are the state's dead)
	for code: String in results:
		assert_eq(People.count(s, code, "dead"), int(results[code]["dead"]))


func test_every_morale_change_carries_a_reason() -> void:
	_one_tier(100, 100, 500, -10, -10)
	var m := _meeting()
	var s: GameState = m[0]
	var engine := TickEngine.new(repo)
	Play.day(engine, s, true)
	var round_ev: Dictionary = _round_events(engine.day_battles)[0]
	var text := _text_of(_battle_letters(s)[0])
	var changed := 0
	for code: String in round_ev["results"]:
		var r: Dictionary = round_ev["results"][code]
		if int(r["morale"]) == 0 or ArmySystem.is_foe(s, code):
			continue
		changed += 1
		assert_ne(String(r["reason"]), "", "the engine gave a reason")
		var label := String(ArmySystem.regiment(repo, code)["label"])
		assert_string_contains(text, "%s: %d dead, %d wounded; morale %+d (%s)" % [label,
			int(r["dead"]), int(r["wounded"]), int(r["morale"]), String(r["reason"])])
	assert_eq(changed, 1, "our side lost heart and says why")


func test_a_regiment_that_leaves_is_named_with_why() -> void:
	_one_tier(1000, 100, 500, -10, -10)
	var m := _meeting()
	var s: GameState = m[0]
	var engine := TickEngine.new(repo)
	Play.day(engine, s, true)
	var ends: Array = engine.day_battles.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "end")
	assert_eq(ends.size(), 1, "a side with no fit personnel ends the battle")
	var text := _text_of(_battle_letters(s)[0])
	var round_ev: Dictionary = _round_events(engine.day_battles)[0]
	assert_false((round_ev["left"] as Array).is_empty())
	for l: Dictionary in round_ev["left"]:
		assert_string_contains(text, String(ArmySystem.regiment(repo, String(l["code"]))["label"]))
		assert_eq(String(l["why"]), "broken")
		assert_string_contains(text, MissiveWriter.battle_words(repo, "battle_left_broken",
			{"unit": String(ArmySystem.regiment(repo, String(l["code"]))["label"])}, s.absolute_day()))
	assert_false(text.contains("[missing template"), text)


## --- the fog (spec §2: the enemy's figures are estimates) --------------------------

## A battle letter tells our own regiments' dead, wounded and morale exactly,
## with the engine's reasons; of the enemy it gives ONE estimated span of its
## dead and wounded — never a foe regiment's exact dead, wounded or morale, its
## morale reason, nor either side's exact strength or the odds that would give
## the enemy's strength away.
func test_the_letter_gives_no_exact_foe_figure() -> void:
	_one_tier(100, 200, 500, -10, -10)
	var m := _meeting()
	var s: GameState = m[0]
	var f := String(m[2])
	var engine := TickEngine.new(repo)
	Play.day(engine, s, true)
	var round_ev: Dictionary = _round_events(engine.day_battles)[0]
	var fr: Dictionary = round_ev["results"][f]
	var text := _text_of(_battle_letters(s)[0])
	var f_label := String(ArmySystem.regiment(repo, f)["label"])
	assert_false(text.contains("%s: %d dead" % [f_label, int(fr["dead"])]), "no foe regiment's exact dead")
	assert_false(text.contains(String(fr["reason"])) and String(fr["reason"]) != String(round_ev["results"][m[1]]["reason"]),
		"no foe morale reason")
	assert_false(text.contains("morale %+d" % int(fr["morale"])) and int(fr["morale"]) != int(round_ev["results"][m[1]]["morale"]),
		"no foe morale")
	for k: String in ["att_power", "def_power"]:
		assert_false(text.contains(str(int(round_ev[k]))), "no exact strength (%s %d)" % [k, int(round_ev[k])])
	assert_false(text.contains("%d in a thousand" % int(round_ev["odds"])), "no odds")
	var facts: Array = (_battle_letters(s)[0]["facts"] as Array).filter(func(x: Dictionary) -> bool:
		return String(x["key"]).begins_with("loss@"))
	assert_eq(facts.size(), 1, "one loss line: ours")
	# the siege's words give no besieger strength
	var raw := FileAccess.get_file_as_string("res://data/council/templates.csv")
	for line: String in raw.split("\n"):
		if line.begins_with("siege_") or line.begins_with("battle_"):
			assert_false(line.contains("{attack}") or line.contains("{att_power}") or line.contains("{def_power}")
				or line.contains("{odds}"), "no enemy strength in: " + line)


## --- the words -----------------------------------------------------------------

func test_report_text_uses_templates_and_no_realm_names() -> void:
	for key: String in ["battle_start", "battle_join_att", "battle_join_def", "battle_round", "battle_loss", "battle_title",
			"battle_end_won", "battle_end_lost", "battle_end_draw", "battle_end_none", "battle_end_withdrawn",
			"battle_left_ordered", "battle_left_broken", "battle_left_rout", "battle_left_evade",
			"battle_left_retreat"]:
		assert_true(repo.templates.any(func(r: Dictionary) -> bool: return String(r["key"]) == key), key)
	# the authored cells never spell a kingdom: they say {player_realm} etc.
	var names: Array = []
	for k: String in repo.kingdoms:
		names.append(String(repo.kingdoms[k].get("label", k)))
	for row: Dictionary in repo.templates:
		if not String(row["key"]).begins_with("battle_"):
			continue
		var authored := String((row.get("_authored", {}) as Dictionary).get("text", row["text"]))
		for n: String in names:
			assert_false(n != "" and authored.contains(n), "%s names %s" % [row["key"], n])
	# the letter is the templates' words, filled
	_one_tier(100, 100, 500, -10, -10)
	var m := _meeting()
	var s: GameState = m[0]
	var engine := TickEngine.new(repo)
	Play.day(engine, s, true)
	var letter: Dictionary = _battle_letters(s)[0]
	var text := _text_of(letter)
	assert_false(text.contains("{") or text.contains("[missing") or text.contains("%"), text)
	var start: Dictionary = engine.day_battles.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "start")[0]
	var place := BattleSystem.place_label(repo, s, start)
	assert_string_contains(text, place)
	assert_string_contains(String(letter["title"]), place)
	var p_label := String(ArmySystem.regiment(repo, String(m[1]))["label"])
	var f_label := String(ArmySystem.regiment(repo, String(m[2]))["label"])
	assert_string_contains(String(((letter["facts"] as Array)[0] as Dictionary)["text"]), f_label)
	assert_string_contains(String(((letter["facts"] as Array)[0] as Dictionary)["text"]), p_label)


## Finish the route by placing the real routed unit beyond contact with every opponent.
func _separate_routed_side(s: GameState, engine: TickEngine, meeting: Array, rout: String) -> void:
	assert_eq(s.battles.size(), 1, "rout starts withdrawal; the battle persists while in contact")
	var code := String(meeting[2] if rout == "attacker" else meeting[1])
	var entry := ArmySystem.state_of(repo, s, code)
	var reach := int(repo.bal("battle_contact_km")) * 1000
	entry["x_m"] = int(s.battles[0]["place_x_m"]) + reach * 3
	entry["y_m"] = int(s.battles[0]["place_y_m"])
	entry["dest_x_m"] = entry["x_m"]
	entry["dest_y_m"] = entry["y_m"]
	entry["order"] = ArmySystem.ORDER_STANDBY
	Play.day(engine, s, true)


func _ending_text(rout: String) -> Array:
	_one_tier(100, 100, 500, -10, -10, rout)
	var m := _meeting()
	var s: GameState = m[0]
	var engine := TickEngine.new(repo)
	Play.day(engine, s, true)
	_separate_routed_side(s, engine, m, rout)
	var end: Dictionary = engine.day_battles.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "end")[0]
	var place := BattleSystem.place_label(repo, s, end)
	return [_text_of(_battle_letters(s).back()), place, int(end["rounds"])]


func test_the_ending_is_told_from_the_players_side() -> void:
	# the attacker (the foe) routs: we hold the field
	var won := _ending_text("attacker")
	var want_won := MissiveWriter.battle_words(repo, "battle_end_won", {"place": won[1], "rounds": won[2]}, 0)
	assert_string_contains(String(won[0]), want_won)
	assert_false(String(won[0]).contains(MissiveWriter.battle_words(repo, "battle_end_lost",
		{"place": won[1], "rounds": won[2]}, 0)))
	# the defender (us) routs: the foe holds the field
	var lost := _ending_text("defender")
	var want_lost := MissiveWriter.battle_words(repo, "battle_end_lost", {"place": lost[1], "rounds": lost[2]}, 0)
	assert_string_contains(String(lost[0]), want_lost)
	assert_ne(want_won, want_lost, "told differently")
	assert_false(want_won.contains("{") or want_lost.contains("{"))


## --- the cap -------------------------------------------------------------------

func test_battle_letters_are_capped_apart() -> void:
	repo.balance["missive_keep_battle"] = 3.0
	repo.balance["missive_keep_per_column"] = 2.0
	var s := SuiteData.campaign(repo, 7)
	s.missives.clear()
	var first := MissiveLog.add(repo, s, MissiveLog.make("receipt", "credible", 1, {}, "r", []))
	for i in 5:
		MissiveLog.add(repo, s, MissiveLog.make("battle", "credible", 1, {}, "b%d" % i, []))
	var kinds: Array = s.missives.map(func(x: Dictionary) -> String: return String(x["kind"]))
	assert_eq(kinds.count("battle"), 3, "missive_keep_battle caps the battle letters")
	assert_eq(kinds.count("receipt"), 1, "a battle letter never pushes a receipt off")
	assert_true(MissiveLog.find(s, first).has("id"))
	# the newest three stay
	var titles: Array = s.missives.filter(func(x: Dictionary) -> bool: return String(x["kind"]) == "battle") \
		.map(func(x: Dictionary) -> String: return String(x["title"]))
	titles.sort()
	assert_eq(titles, ["b2", "b3", "b4"])
	# and the other kinds still run on their own cap
	for i in 4:
		MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 1, {}, "p%d" % i, []))
	kinds = s.missives.map(func(x: Dictionary) -> String: return String(x["kind"]))
	assert_eq(kinds.count("spy"), 2)
	assert_eq(kinds.count("battle"), 3)


func test_the_cap_key_exists() -> void:
	assert_true(repo.balance.has("missive_keep_battle"))
	assert_gt(int(repo.bal("missive_keep_battle")), 0)


## --- Under arms (Task 3 review) --------------------------------------------------

func test_under_arms_does_not_count_the_dead() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code: String = _mine()[0]
	var reg := ArmySystem.regiment(repo, code)
	var heads := ArmySystem.headcount(repo, reg)
	assert_false(People.move(repo, s, code, "fit", "dead", 123, "reported_dead").has("error"))
	assert_false(People.move(repo, s, code, "fit", "wounded", 45, "reported_wounded").has("error"))
	var card := MapObjects.army_card(repo, code, s)
	var under := ""
	for st: Dictionary in card["stats"]:
		if String(st["key"]) == "army":
			under = String(st["text"])
	assert_eq(under, "%d (45 wounded)" % (heads - 123))
	assert_has(card["fields"], ["Under arms", str(heads - 123)])
	var rows: Dictionary = {}
	for sec: Dictionary in WarFolio.sections(repo, s, code):
		if String(sec["key"]) == "composition":
			for r: Dictionary in sec["rows"]:
				rows[String(r["label"])] = String(r["text"])
	assert_eq(rows["Under arms"], WarRoom.group(heads - 123))
	assert_eq(rows["Fit"], WarRoom.group(heads - 123 - 45))
