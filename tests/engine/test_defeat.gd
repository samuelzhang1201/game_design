extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## The cost of a lost town (spec 2026-10-07-enemy-ai-and-battle-design §6, not
## a Game Over): DefeatSystem.on_town_lost takes battle_defeat_treasury_permille
## of the crown's treasury and battle_defeat_morale of the people's contentment
## (each a WorldLedger line with its reason), moves every councillor's opinion
## by battle_defeat_opinion scaled through OpinionDrift's ideology weight (the
## BATTLE_LOST signature), and schedules the fixed-prose beat war_01. Once per
## loss (town, host, day); taking the town back refunds nothing. Hand-computed
## figures throughout.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

## The player's land units, in code order.
func _mine() -> Array:
	return Play.land_regiments(repo)


func _host(role: String) -> String:
	for h: Dictionary in repo.raid_hosts:
		if String(h["role"]) == role:
			return String(h["host_code"])
	return ""


func _town_m(town: String) -> Vector2i:
	return EnemyAi.target_point_m(repo, "town", town)


func _place(s: GameState, code: String, at: Vector2i, order: String) -> void:
	Play.place(repo, s, code, at, order)


## A town the campaign opens with one of the player's units on its seat, not
## the depot: [town, unit].
func _town_and_garrison(s: GameState) -> Array:
	var dep := TownStores.depot(repo, s)
	for c: String in _mine():
		var t := ArmyGround.seated_in(repo, s, c)
		if t != "" and t != dep:
			return [t, c]
	return ["", ""]


## A siege by hand (as test_siege's): the town's garrison is the one regiment,
## every other regiment at the depot, the main host's columns at the town, its
## mind SIEGE on it. Returns the town.
func _besiege(s: GameState, host: String) -> String:
	var tg := _town_and_garrison(s)
	var town := String(tg[0])
	assert_ne(town, "", "the pack quarters a regiment in a town of its own")
	var at := _town_m(town)
	var away := _town_m(TownStores.depot(repo, s))
	for c: String in s.regiments.keys():
		if c != String(tg[1]):
			_place(s, c, away, ArmySystem.ORDER_STANDBY)
	_place(s, String(tg[1]), at, ArmySystem.ORDER_GARRISON)
	for c: String in EnemyAi.regiments_of(s, host):
		_place(s, c, at, ArmySystem.ORDER_GARRISON)
	var mind: Dictionary = s.ai_hosts[host]
	mind["mode"] = "SIEGE"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	return town


func _label(town: String) -> String:
	return String((repo.burgs[town] as Dictionary).get("label", town))


func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == kind)


func _log_of(s: GameState, path: String, source: String) -> Array:
	return s.world_log.filter(func(e: Dictionary) -> bool:
		return String(e["path"]) == path and String(e["source"]) == source)


func _scheduled(s: GameState, id: String) -> Array:
	return (s.event_state["scheduled"] as Array).filter(func(e: Dictionary) -> bool:
		return String(e["event_id"]) == id)


func _opinions(s: GameState) -> Dictionary:
	var out := {}
	for seat: String in s.council:
		var c: Character = s.characters[s.council[seat]]
		out[seat] = [c.opinion, c.opinion_log.size()]
	return out


## --- the treasury --------------------------------------------------------------

## 10000 gold x 150 per mille = 1500 gold, one ledger line with its reason.
func test_treasury_hit() -> void:
	repo.balance["battle_defeat_treasury_permille"] = 150.0
	var s := SuiteData.campaign(repo, 7)
	var town := String(_town_and_garrison(s)[0])
	var host := _host("main")
	s.metrics["treasury"] = 10000.0
	var ev := DefeatSystem.on_town_lost(repo, s, town, host)
	assert_eq(int(s.metrics["treasury"]), 8500, "10000 - 10000 x 150 / 1000")
	var lines := _log_of(s, "metrics.treasury", "defeat")
	assert_eq(lines.size(), 1, "one ledger line")
	assert_eq(int(float(lines[0]["delta"])), -1500)
	assert_eq(String(lines[0]["reason"]), "lost %s to %s" % [_label(town), SiegeSystem.host_label(repo, host)])
	assert_eq(_of(ev, "defeat_town_lost").size(), 1, "one event for the loss")
	assert_eq(int(_of(ev, "defeat_town_lost")[0]["gold"]), 1500, "the event carries the gold lost")


## Whole gold, rounded down: 10001 x 150 / 1000 = 1500.15 -> 1500; 7 -> 1; 1 -> 0.
func test_treasury_hit_is_whole_gold_rounded_down() -> void:
	repo.balance["battle_defeat_treasury_permille"] = 150.0
	for case: Array in [[10001, 8501], [7, 6], [1, 1]]:
		var s := SuiteData.campaign(repo, 7)
		s.metrics["treasury"] = float(case[0])
		DefeatSystem.on_town_lost(repo, s, String(_town_and_garrison(s)[0]), _host("main"))
		assert_eq(int(s.metrics["treasury"]), int(case[1]), "treasury %d" % case[0])


## A share of a positive treasury never makes it negative; an empty or
## indebted treasury (the economy lets it go below 0: world_schema min
## -100000000) loses nothing more to a fall.
func test_treasury_never_goes_negative_from_a_loss() -> void:
	for start: int in [0, -500]:
		var s := SuiteData.campaign(repo, 7)
		s.metrics["treasury"] = float(start)
		DefeatSystem.on_town_lost(repo, s, String(_town_and_garrison(s)[0]), _host("main"))
		assert_eq(int(s.metrics["treasury"]), start, "nothing taken from %d" % start)
		assert_eq(_log_of(s, "metrics.treasury", "defeat").size(), 0, "no empty ledger line")
	var s2 := SuiteData.campaign(repo, 7)
	s2.metrics["treasury"] = 3.0
	repo.balance["battle_defeat_treasury_permille"] = 1000.0
	DefeatSystem.on_town_lost(repo, s2, String(_town_and_garrison(s2)[0]), _host("main"))
	assert_eq(int(s2.metrics["treasury"]), 0, "even the whole of it leaves 0, not less")


## --- the people ------------------------------------------------------------------

func test_morale_hit_has_a_reason() -> void:
	repo.balance["battle_defeat_morale"] = 8.0
	var s := SuiteData.campaign(repo, 7)
	var town := String(_town_and_garrison(s)[0])
	s.metrics["peasant_contentment"] = 50.0
	DefeatSystem.on_town_lost(repo, s, town, _host("main"))
	assert_eq(int(s.metrics["peasant_contentment"]), 42, "50 - 8")
	var lines := _log_of(s, "metrics.peasant_contentment", "defeat")
	assert_eq(lines.size(), 1)
	assert_eq(int(float(lines[0]["delta"])), -8)
	assert_eq(String(lines[0]["reason"]), "−8: lost %s to the raiders" % _label(town))
	# clamped at the schema's floor: the reason names what fell
	var s2 := SuiteData.campaign(repo, 7)
	s2.metrics["peasant_contentment"] = 5.0
	var ev2 := DefeatSystem.on_town_lost(repo, s2, town, _host("main"))
	assert_eq(int(s2.metrics["peasant_contentment"]), 0, "5 - 8 clamps to the schema's 0")
	var lines2 := _log_of(s2, "metrics.peasant_contentment", "defeat")
	assert_eq(lines2.size(), 1)
	assert_eq(String(lines2[0]["reason"]), "−5: lost %s to the raiders" % _label(town), "the 5 that fell")
	assert_eq(int(ev2[0]["morale"]), 5)
	# nothing left to fall: no line at all
	var s3 := SuiteData.campaign(repo, 7)
	s3.metrics["peasant_contentment"] = 0.0
	var ev3 := DefeatSystem.on_town_lost(repo, s3, town, _host("main"))
	assert_eq(_log_of(s3, "metrics.peasant_contentment", "defeat").size(), 0, "no zero line")
	assert_eq(int(ev3[0]["morale"]), 0)


## --- the council -----------------------------------------------------------------

## delta = -round(battle_defeat_opinion x (1 + w)), w = OpinionDrift.weight of
## the BATTLE_LOST signature (militarism 20, expansionism 10; norm 30):
##   marshal  (mil 70, exp 50, sens 70, prag 35): a = (1400+500)/3000 = 0.6333;
##            w = 0.6333 x 0.70 x 0.65 = 0.2882; 5 x 1.2882 = 6.44 -> -6
##   chaplain (mil -30, exp -20, sens 80, prag 30): a = (-600-200)/3000 = -0.2667;
##            w = -0.2667 x 0.80 x 0.70 = -0.1493; 5 x 0.8507 = 4.25 -> -4
##   chancellor (mil -10, exp -20, sens 60, prag 60): a = -400/3000 = -0.1333;
##            w = -0.1333 x 0.60 x 0.40 = -0.0320; 5 x 0.968 = 4.84 -> -5
func test_every_councillor_opinion_change_has_a_reason() -> void:
	repo.balance["battle_defeat_opinion"] = 5.0
	var s := SuiteData.campaign(repo, 7)
	var town := String(_town_and_garrison(s)[0])
	# the hand-computation's inputs are the founding council's
	var m: Character = s.characters[s.council["marshal"]]
	assert_eq([int(m.ideology["militarism"]), int(m.ideology["expansionism"]),
		int(m.ideology["policy_sensitivity"]), int(m.attributes["pragmatism"])], [70, 50, 70, 35])
	var ch: Character = s.characters[s.council["chaplain"]]
	assert_eq([int(ch.ideology["militarism"]), int(ch.ideology["expansionism"]),
		int(ch.ideology["policy_sensitivity"]), int(ch.attributes["pragmatism"])], [-30, -20, 80, 30])
	var before := _opinions(s)
	var ev := DefeatSystem.on_town_lost(repo, s, town, _host("main"))
	var want := {"marshal": -6, "chaplain": -4, "chancellor": -5}
	for seat: String in want:
		var c: Character = s.characters[s.council[seat]]
		assert_eq(c.opinion - int(before[seat][0]), int(want[seat]), seat)
	for seat: String in s.council:
		var c: Character = s.characters[s.council[seat]]
		var fresh: Array = c.opinion_log.slice(int(before[seat][1]))
		assert_eq(fresh.size(), 1, seat + " has one opinion change for the loss")
		for e: Dictionary in fresh:
			assert_lt(int(e["delta"]), 0, seat + " is not pleased by a lost town")
			assert_true(String(e["reason"]).begins_with("lost %s to the raiders (opposes, " % _label(town)),
				seat + "'s change carries its reason: " + String(e["reason"]))
	var told: Array = _of(ev, "defeat_town_lost")[0]["opinion"]
	assert_eq(told.size(), s.council.size(), "the event lists each councillor's change")


## --- the event --------------------------------------------------------------------

func test_loss_event_is_scheduled_and_text_names_no_realm() -> void:
	var s := SuiteData.campaign(repo, 7)
	s.event_state["scheduled"] = []
	s.pending_event = {}
	DefeatSystem.on_town_lost(repo, s, String(_town_and_garrison(s)[0]), _host("main"))
	var due := _scheduled(s, DefeatSystem.EVENT_ID)
	assert_eq(due.size(), 1, "the beat is scheduled once")
	assert_eq(int(due[0]["due_tick"]), s.tick, "for the next roll")
	# a chapter beat: chained only, never the random pool's
	assert_true(repo.events_by_id.has(DefeatSystem.EVENT_ID), "findable by id")
	for row: Dictionary in repo.events:
		assert_ne(String(row["event_id"]), DefeatSystem.EVENT_ID, "not in the random pool")
	var row: Dictionary = repo.events_by_id[DefeatSystem.EVENT_ID]
	assert_eq(String(row["trigger"]), "never")
	assert_eq(String(row["voice"]), "template", "fixed authored prose")
	# authored prose, slots only
	var authored := String(repo.event_scenes_authored.get(DefeatSystem.EVENT_ID, ""))
	assert_ne(authored.strip_edges(), "", "an authored scene")
	assert_ne(String(repo.event_titles.get(DefeatSystem.EVENT_ID, "")).strip_edges(), "", "a title")
	for slot: String in ["player_realm", "raider_realm", "neighbor_realm", "empire_realm"]:
		var code := repo.resolve_realm(slot)
		if code != "" and repo.kingdoms.has(code):
			assert_false(authored.contains(String((repo.kingdoms[code] as Dictionary)["label"])),
				"the scene names no kingdom")
	assert_true(authored.contains("{raider_realm}"), "the raiders are a slot")
	# it fires off the queue, and its two choices carry signatures and reasons
	var sys := EventSystem.new(repo)
	var ev := sys.roll(s)
	assert_eq(String(ev.get("event_id", "")), DefeatSystem.EVENT_ID)
	assert_eq((ev["choices"] as Array).size(), 2)
	var out := sys.apply_choice(String((ev["choices"] as Array)[0]["choice_id"]), s)
	assert_false(out.is_empty(), "a choice resolves")
	assert_gt((out["drift"] as Array).size(), 0, "the choice's signature moves the council")
	for d: Dictionary in out["drift"]:
		assert_ne(String(d["reason"]), "", "every drift has a reason")


## No dead war beat: every war_* row of the chapter table is one DefeatSystem
## schedules, and every beat it schedules is a war_* row there.
func test_every_war_beat_is_one_the_engine_schedules() -> void:
	var war: Array = []
	for row: Dictionary in repo.chapter_events:
		var id := String(row["event_id"])
		if id.begins_with(DefeatSystem.BEAT_PREFIX):
			war.append(id)
			assert_has(DefeatSystem.BEATS, id, id + " is a war beat nothing schedules")
	assert_gt(war.size(), 0, "the war's beats are in the chapter table")
	for id: String in DefeatSystem.BEATS:
		assert_has(war, id, id + " is scheduled but is no war_* chapter row")
	assert_has(DefeatSystem.BEATS, DefeatSystem.EVENT_ID)


## The prologue is month-exact: a town that falls while a chain beat waits for
## its answer must not take that beat's month. The chain beat the answer
## schedules wins its roll; war_01 waits for the next roll with no chain beat due.
func test_a_lost_town_never_delays_the_chain() -> void:
	var s := SuiteData.campaign(repo, 7)
	var sys := EventSystem.new(repo)
	s.event_state["scheduled"] = [{"event_id": "c0_12", "due_tick": s.tick}]
	s.pending_event = {}
	assert_eq(String(sys.roll(s).get("event_id", "")), "c0_12", "the last reckoning waits for its answer")
	DefeatSystem.on_town_lost(repo, s, String(_town_and_garrison(s)[0]), _host("main"))
	assert_false(sys.apply_choice("nothing", s).is_empty(), "answered: the ending is scheduled for next month")
	s.tick += 1
	var ending := String(sys.roll(s).get("event_id", ""))
	assert_true(ending in ["c0_13", "c0_14", "c0_15", "c0_16"], "the chain's ending on its own tick, not " + ending)
	sys.apply_choice("on", s)
	s.tick += 1
	assert_eq(String(sys.roll(s).get("event_id", "")), DefeatSystem.EVENT_ID, "the lost town's beat, the next roll")


## --- once per loss, nothing back ----------------------------------------------------

func test_triggers_once_per_loss() -> void:
	var s := SuiteData.campaign(repo, 7)
	s.event_state["scheduled"] = []
	s.metrics["treasury"] = 10000.0
	var town := String(_town_and_garrison(s)[0])
	var host := _host("main")
	assert_eq(DefeatSystem.on_town_lost(repo, s, town, host).size(), 1)
	var after := [int(s.metrics["treasury"]), int(s.metrics["peasant_contentment"]), _opinions(s), s.world_log.size()]
	assert_eq(DefeatSystem.on_town_lost(repo, s, town, host), [], "the same loss again is nothing")
	assert_eq([int(s.metrics["treasury"]), int(s.metrics["peasant_contentment"]), _opinions(s), s.world_log.size()],
		after, "nothing moves twice")
	assert_eq(_scheduled(s, DefeatSystem.EVENT_ID).size(), 1, "one beat")
	assert_eq(s.town_losses.size(), 1)
	assert_eq(s.town_losses[0], {"town": town, "host": host, "day": s.absolute_day()}, "the loss's key")
	# the same town lost again another day is a new loss
	s.day += 1
	assert_eq(DefeatSystem.on_town_lost(repo, s, town, host).size(), 1, "a second fall, another day")
	assert_eq(s.town_losses.size(), 2)


func test_capture_pays_the_cost_of_the_loss() -> void:
	repo.balance["battle_defeat_treasury_permille"] = 150.0
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.metrics["treasury"] = 10000.0
	s.event_state["scheduled"] = []
	var town := _besiege(s, main)
	s.ai_hosts[main]["siege_progress"] = 1000
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "the town fell")
	assert_eq(int(s.metrics["treasury"]), 8500, "and the crown paid for it")
	var kinds: Array = ev.map(func(e: Dictionary) -> String: return String(e.get("kind", "")))
	assert_true(kinds.has("defeat_town_lost"), "the cost is among the day's events")
	assert_lt(kinds.find("siege_fallen"), kinds.find("defeat_town_lost"), "the fall is told before its cost")
	assert_eq(s.town_losses.size(), 1)
	assert_eq(String(s.town_losses[0]["town"]), town)
	assert_eq(_scheduled(s, DefeatSystem.EVENT_ID).size(), 1, "the beat waits for the next roll")
	# the battle letter gives the cost a line, with the event's own figure
	var letter := MissiveWriter.battle_report(repo, s, SiegeSystem.news(ev))
	var text := "\n".join((letter["facts"] as Array).map(func(f: Dictionary) -> String: return String(f["text"])))
	assert_false(text.contains("[missing template"), text)
	assert_true(text.contains("1500"), "the gold lost is told: " + text)
	assert_true(text.contains(_label(town)), text)
	# the HOLD days after take nothing more
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(int(s.metrics["treasury"]), 8500, "a held town costs once")


## The letter's line names only what was lost: no "0 gold", no "falls by 0".
func test_letter_line_drops_a_zero_figure() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := String(_town_and_garrison(s)[0])
	for case: Array in [[1500, 8, true, true], [0, 8, false, true], [1500, 0, true, false], [0, 0, false, false]]:
		var e := {"kind": "defeat_town_lost", "town": town, "host": _host("main"), "day": s.absolute_day(),
			"gold": case[0], "morale": case[1], "opinion": [], "event_id": ""}
		var letter := MissiveWriter.battle_report(repo, s, [e])
		var text := "\n".join((letter["facts"] as Array).map(func(f: Dictionary) -> String: return String(f["text"])))
		assert_false(text.contains("[missing template"), text)
		assert_true(text.contains(_label(town)), text)
		assert_false(text.contains(" 0 "), "no zero figure: " + text)
		assert_eq(text.contains("1500"), bool(case[2]), text)
		assert_eq(text.contains("contentment"), bool(case[3]), text)


func test_recapture_refunds_nothing() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	s.metrics["treasury"] = 10000.0
	var town := _besiege(s, main)
	var cell := EnemyAi.target_cell(repo, s, "town", town)
	var was := MapManors.owner_of(repo, s, cell)
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	var after := [int(s.metrics["treasury"]), int(s.metrics["peasant_contentment"]), _opinions(s),
		_log_of(s, "metrics.treasury", "defeat").size(), s.town_losses.size()]
	MapManors.set_owner(repo, s, cell, was, "test: retaken")
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(_of(ev, "siege_liberated").size(), 1, "the town is free again")
	assert_eq(_of(ev, "defeat_town_lost").size(), 0, "and that costs nothing")
	assert_eq([int(s.metrics["treasury"]), int(s.metrics["peasant_contentment"]), _opinions(s),
		_log_of(s, "metrics.treasury", "defeat").size(), s.town_losses.size()], after,
		"nothing refunded, nothing taken")


## --- not a Game Over ------------------------------------------------------------------

func test_campaign_continues_after_losing_a_town() -> void:
	var main := _host("main")
	var s := SuiteData.campaign(repo, 7)
	var engine := TickEngine.new(repo)
	if s.tick == 0:
		engine.advance(s)               # the reign's opening tick, as a new reign plays it
	# the prologue's own queue cleared, so the loss's beat is the next due
	s.event_state["scheduled"] = []
	s.pending_event = {}
	_besiege(s, main)
	s.ai_hosts[main]["siege_progress"] = 1000
	SiegeSystem.settle_day(repo, s, [])
	assert_eq(s.town_losses.size(), 1, "a town is lost")
	var tick0 := s.tick
	var day0 := s.absolute_day()
	var fired: Array = []
	for i in 40:
		if s.day >= Calendar.DAYS_PER_TICK:
			var r := engine.advance(s)
			if not r.event.is_empty():
				fired.append(String(r.event["event_id"]))
				engine.events.apply_choice(String((r.event["choices"] as Array)[0]["choice_id"]), s)
		else:
			engine.advance_day(s)
	assert_eq(s.absolute_day(), day0 + 40, "the clock ran on, forty days")
	assert_gt(s.tick, tick0, "the month turned")
	assert_true(fired.has(DefeatSystem.EVENT_ID), "the beat was played at the month's roll: %s" % [fired])
	# the save holds, the loss with it
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.town_losses, s.town_losses, "the loss survives the save")
	assert_eq(back.absolute_day(), s.absolute_day())
	engine.advance_day(back)
	assert_eq(back.absolute_day(), s.absolute_day() + 1, "a loaded campaign plays on")


func test_old_save_has_no_losses() -> void:
	var s := SuiteData.campaign(repo, 7)
	var d := s.to_dict()
	d.erase("town_losses")
	assert_eq(GameState.from_dict(d).town_losses, [], "a save from before defeat: nothing lost")
