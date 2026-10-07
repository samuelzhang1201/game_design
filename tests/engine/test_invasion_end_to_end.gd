extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const RunDir := preload("res://tests/run_dir.gd")
const Play := preload("res://tests/invasion_play.gd")
## The prologue's invasion end to end (spec 2026-10-07-enemy-ai-and-battle-
## design, all of it) on the REAL day loop of a suite campaign, with no hand
## on the engine but the player's defence: on the main host's crossing day the
## town it chose is garrisoned as if the march had already been carried out.
##   A  WEAK: the pack's smallest land regiment holds it — the rumour comes,
##      the hosts cross on their days, the main host sits down before the
##      town, wears it down, storms it and takes it; the loss costs the crown
##      (treasury, contentment, the council, the war beat) and the campaign
##      plays on.
##   B  STRONG: the three largest hold it, behind walls and a citadel (the
##      test gives the town them; the host keeps its plan, ai_think_days out of
##      reach — with its own mind it turns away from a garrison it sees) — the
##      town never falls, the garrison never starves, the host goes home.
## Both are deterministic: the same save played twice is the same state, and
## a save on day SAVE_DAY played on equals the run that never stopped. The
## war's state holds no float, and the war's systems draw no random number.

const DAYS := 45
const SAVE_DAY := 20

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- the scenarios ------------------------------------------------------------

## The town the main host chooses on its crossing day (no defence anywhere).
func _chosen_town() -> String:
	var engine := TickEngine.new(repo)
	var s := Play.opened(repo, engine)
	Play.play_through(engine, s, Play.first_appear(repo))
	var mind: Dictionary = s.ai_hosts[Play.host(repo, "main")]
	assert_eq(String(mind["mode"]), "ADVANCE", "the main host has crossed")
	assert_eq(String(mind["target_kind"]), "town", "the main host goes for a town")
	return String(mind["target_id"])


## The defence of `scenario` ("weak" | "strong"): its regiments, by size.
func _garrison(scenario: String) -> Array:
	var weak := scenario == "weak"
	return Play.by_size(repo, Play.land_regiments(repo), weak).slice(0, 1 if weak else 3)


## Sets the repository up for `scenario` BEFORE its campaign is made (every
## run of it shares the data): STRONG walls the chosen town and holds the
## host's plan. Returns the town.
func _prepare(scenario: String) -> String:
	var town := _chosen_town()
	if scenario == "strong":
		repo.burgs[town]["features"] = "walls|citadel"
		ArmySystem.forget_grids()
		repo.balance["ai_think_days"] = 999.0
	return town


## Plays the opened campaign `s` until the absolute day `last` has ended; as
## the crossing day ends, `garrison` takes the main host's town. Returns what
## was seen, by absolute day: {rumour, left {host: day}, town, siege_begin,
## siege_days [siege_day events], repulsed, assaults [battle start events at
## the town, with day], battle_letters [days], fell, fallen (event), defeat
## (event), before {treasury, content} of the fall's day, home (the main
## host's first homeward day), lifted, beat_scheduled}.
func _run(engine: TickEngine, s: GameState, last: int, garrison: Array, seen: Dictionary = {}) -> Dictionary:
	var blank := {"rumour": -1, "left": {}, "town": "", "siege_begin": -1, "siege_days": [], "repulsed": [],
		"assaults": [], "battle_letters": [], "fell": -1, "fallen": {}, "defeat": {}, "before": {},
		"home": -1, "lifted": -1, "beat_scheduled": false, "hungry": 0, "garrison": [], "dead": {},
		"fought": [], "first_assault_over": -1}
	for k: String in blank:
		if not seen.has(k):
			seen[k] = blank[k]
	var main := Play.host(repo, "main")
	var cross := Play.first_appear(repo)
	while s.absolute_day() <= last:
		var today := s.absolute_day()
		var before := {"treasury": float(s.metrics["treasury"]),
			"content": float(s.metrics["peasant_contentment"])}
		Play.day(engine, s)
		if int(seen["rumour"]) < 0 and not Play.letters(s, "rumour").is_empty():
			seen["rumour"] = today
		for h: String in EnemyAi.host_codes(s):
			if String(s.ai_hosts[h]["mode"]) != "ASSEMBLE" and not (seen["left"] as Dictionary).has(h):
				seen["left"][h] = today
		if today == cross:
			var town := String(s.ai_hosts[main]["target_id"])
			seen["town"] = town
			for c: String in garrison:
				Play.place(s, c, Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
			seen["garrison"] = garrison.duplicate()
		for e: Dictionary in engine.day_siege:
			match String(e.get("kind", "")):
				"siege_begin":
					if int(seen["siege_begin"]) < 0:
						seen["siege_begin"] = today
				"siege_day":
					var d := e.duplicate()
					d["on"] = today
					seen["siege_days"].append(d)
					seen["hungry"] = int(seen["hungry"]) + (1 if bool(e["starving"]) else 0)
				"siege_repulsed":
					seen["repulsed"].append(e)
				"siege_fallen":
					seen["fell"] = today
					seen["fallen"] = e
					seen["before"] = before
				"defeat_town_lost":
					seen["defeat"] = e
					seen["beat_scheduled"] = (s.event_state["scheduled"] as Array).any(
						func(sc: Dictionary) -> bool: return String(sc["event_id"]) == DefeatSystem.EVENT_ID)
				"siege_lifted":
					seen["lifted"] = today
		for e: Dictionary in engine.day_battles:
			var k := String(e.get("kind", ""))
			if k in ["start", "round"] and not today in seen["fought"]:
				seen["fought"].append(today)
			if k == "start" and String(e["town"]) == String(seen["town"]):
				var a := e.duplicate()
				a["on"] = today
				seen["assaults"].append(a)
			if k == "end" and String(e["town"]) == String(seen["town"]) and int(seen["first_assault_over"]) < 0:
				seen["first_assault_over"] = today
		var dead := 0
		for c: String in seen["garrison"]:
			dead += int(s.regiments[c].get("dead", 0))
		seen["dead"][today] = dead
		if s.missives.any(func(m: Dictionary) -> bool:
				return String(m["kind"]) == "battle" and int(m["day"]) == today):
			seen["battle_letters"].append(today)
		if int(seen["home"]) < 0 and String(s.ai_hosts[main]["mode"]) in EnemyAi.HOMEWARD:
			seen["home"] = today
	return seen


## The war's state in memory holds no float (it is saved whole).
func _war_floats(s: GameState) -> Array:
	var out: Array = []
	Play.floats_in(s.foes, "foes", out)
	Play.floats_in(s.ai_hosts, "ai_hosts", out)
	Play.floats_in(s.battles, "battles", out)
	Play.floats_in(s.town_losses, "town_losses", out)
	return out


## --- A: a weak defence loses the town ----------------------------------------

func test_weak_defence_loses_the_town_and_the_campaign_plays_on() -> void:
	var expected_town := _prepare("weak")
	var garrison := _garrison("weak")
	var engine := TickEngine.new(repo)
	var s := Play.opened(repo, engine)
	var seen := _run(engine, s, DAYS, garrison)
	var main := Play.host(repo, "main")
	var town := String(seen["town"])
	assert_eq(town, expected_town, "the main host's town")
	var label := String(repo.burgs[town]["label"])
	# the rumour, before anyone crosses
	var appear := Play.first_appear(repo)
	assert_eq(int(seen["rumour"]), appear - int(repo.bal("raid_rumour_lead_days")), "the rumour on its day")
	# every host leaves ASSEMBLE on its own appear_day
	for row: Dictionary in repo.raid_hosts:
		var h := String(row["host_code"])
		assert_eq(int(seen["left"].get(h, -1)), int(row["appear_day"]), h + " crosses on its day")
	# the siege: begun on arrival, worn down a day at a time
	var begun := int(seen["siege_begin"])
	assert_gt(begun, appear, "the main host sat down before the town after crossing")
	var progress := 0
	var last_day := 0
	for e: Dictionary in seen["siege_days"]:
		assert_gt(int(e["on"]), last_day, "one siege day a day")
		last_day = int(e["on"])
		assert_gt(int(e["gain"]), 0, "the siege gains, day %d" % int(e["on"]))
		var lost := 0
		for r: Dictionary in seen["repulsed"]:
			if int(r["day"]) == int(e["on"]):
				lost += int(r["lost"])
		progress = mini(1000, maxi(0, progress - lost) + int(e["gain"]))
		assert_eq(int(e["progress"]), progress, "accumulated, day %d" % int(e["on"]))
	assert_gt((seen["siege_days"] as Array).size(), 1, "several days of siege")
	# the assault: an ordinary town battle, reported by letter
	var assaults: Array = seen["assaults"]
	assert_gt(assaults.size(), 0, "the town was stormed")
	if assaults.is_empty():
		return
	var stormed := int(assaults[0]["on"])
	assert_eq(stormed, begun + int(repo.bal("siege_assault_days")), "on the siege's assault day")
	assert_true(int(assaults[0]["def"].size()) > 0 and garrison[0] in assaults[0]["def"], "the garrison defends")
	assert_true(stormed in seen["battle_letters"], "the assault's letter, day %d" % stormed)
	# the fall
	var fell := int(seen["fell"])
	assert_gte(fell, stormed, "the town falls, at the earliest to the storm")
	assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "the host holds the town")
	assert_false(EnemyAi.target_held(repo, s, "town", town), "the town is not the crown's")
	var cells: Array = (s.ai_hosts[main]["occupied"] as Dictionary).keys()
	assert_gt(cells.size(), 0, "manors taken")
	assert_eq(s.manor_log.size(), cells.size(), "only the taken manors moved")
	for l: Dictionary in s.manor_log:
		assert_true(str(int(l["cell"])) in cells, "a taken manor")
		assert_true(String(l["reason"]).begins_with("taken by ") and String(l["reason"]).contains("siege of " + label),
			"with its reason: " + String(l["reason"]))
	assert_eq(s.territory_log.size(), 0, "no province, border or capital moved")
	# what the loss cost: the hand formulas on the figures before the fall's day
	var d: Dictionary = seen["defeat"]
	assert_false(d.is_empty(), "the loss is paid")
	if d.is_empty():
		return
	var before: Dictionary = seen["before"]
	@warning_ignore("integer_division")
	var gold := int(before["treasury"]) * int(repo.bal("battle_defeat_treasury_permille")) / 1000
	assert_gt(gold, 0, "a treasury to lose from")
	assert_eq(int(d["gold"]), gold, "treasury × battle_defeat_treasury_permille / 1000")
	var morale := mini(int(repo.bal("battle_defeat_morale")), int(before["content"]))
	assert_eq(int(d["morale"]), morale, "battle_defeat_morale points of contentment")
	var lines: Array = s.world_log.filter(func(l: Dictionary) -> bool: return String(l["source"]) == "defeat")
	var paths: Array = lines.map(func(l: Dictionary) -> String: return String(l["path"]))
	assert_eq(paths, ["metrics.treasury", "metrics.peasant_contentment"], "one ledger line each")
	for l: Dictionary in lines:
		assert_true(String(l["reason"]).contains("lost " + label), "with its reason: " + String(l["reason"]))
	if lines.size() == 2:
		assert_eq(int(float(lines[0]["delta"])), -gold, "the treasury line")
		assert_eq(roundi(float(lines[1]["delta"])), -morale, "the contentment line")
	var ops: Array = d["opinion"]
	assert_eq(ops.size(), s.council.size(), "every seat of the council feels it")
	for o: Dictionary in ops:
		assert_lt(int(o["delta"]), 0, "a loss, never a gain")
		var c: Character = s.characters[String(o["character_id"])]
		var logged: Array = c.opinion_log.filter(func(l: Dictionary) -> bool:
			return String(l["reason"]) == String(o["reason"]) and int(l["delta"]) == int(o["delta"]))
		assert_eq(logged.size(), 1, "%s's opinion moved once with its reason: %s" % [o["character_id"], o["reason"]])
		assert_true(String(o["reason"]).contains("lost %s to the raiders" % label), String(o["reason"]))
	assert_eq(String(d["event_id"]), DefeatSystem.EVENT_ID, "the war beat")
	assert_true(bool(seen["beat_scheduled"]), "scheduled for the roll")
	assert_eq(s.town_losses.size(), 1, "one loss")
	assert_eq(_war_floats(s), [], "no float in the war's state")
	# and the campaign plays on: three more months, every event answered
	var events := EventSystem.new(repo)
	var presented: Array = []
	while s.absolute_day() <= 3 * Calendar.DAYS_PER_TICK:
		Play.day(engine, s)
		if not s.pending_event.is_empty():
			presented.append(String(s.pending_event["event_id"]))
			var first: Dictionary = (s.pending_event["choices"] as Array)[0]
			assert_false(events.apply_choice(String(first["choice_id"]), s).is_empty(), "answered")
	assert_eq(s.tick, 4, "into the fourth month")
	assert_eq(_war_floats(s), [], "still no float")
	gut.p("weak: rumour d%d, cross %s, siege d%d, stormed d%d, fell d%d (%d manors), gold -%d, content -%d, %d opinions; then events %s" % [
		int(seen["rumour"]), seen["left"], begun, stormed, fell, cells.size(), int(d["gold"]), int(d["morale"]),
		ops.size(), presented])


## --- B: a strong defence holds ---------------------------------------------------

func test_strong_walled_defence_holds_and_the_host_goes_home() -> void:
	var town := _prepare("strong")
	var garrison := _garrison("strong")
	var engine := TickEngine.new(repo)
	var s := Play.opened(repo, engine)
	var seen := _run(engine, s, DAYS, garrison)
	var main := Play.host(repo, "main")
	assert_eq(String(seen["town"]), town, "the walled town")
	assert_gt(int(seen["siege_begin"]), 0, "the host sat down before it")
	assert_gt((seen["assaults"] as Array).size(), 0, "and stormed it")
	assert_eq(int(seen["fell"]), -1, "the town never falls")
	assert_true(EnemyAi.target_held(repo, s, "town", town), "still the crown's")
	assert_eq(s.manor_log.size(), 0, "no manor taken")
	assert_eq(s.town_losses.size(), 0, "no loss paid")
	assert_true((s.world_log as Array).filter(func(l: Dictionary) -> bool:
		return String(l["source"]) == "defeat").is_empty(), "no defeat line")
	assert_eq(int(seen["hungry"]), 0, "the garrison never starved")
	assert_gt(int(seen["lifted"]), 0, "the siege is lifted")
	assert_gt(int(seen["home"]), int(seen["siege_begin"]), "the host goes home")
	assert_true(String(s.ai_hosts[main]["mode"]) in EnemyAi.HOMEWARD, "RETREAT or WITHDRAW")
	for c: String in garrison:
		assert_gt(ArmySystem.fit_heads(ArmySystem.headcount(repo, ArmySystem.regiment(repo, c)), s.regiments[c]), 0,
			c + " still stands")
	# a host going home fights no more: no battle from the day it turns home,
	# and the garrison's dead are what the assaults cost — at most the first
	# assault's toll again for each later one, nothing after the host leaves
	var home := int(seen["home"])
	assert_eq((seen["fought"] as Array).filter(func(d: int) -> bool: return d >= home), [],
		"no blow struck from the day the host turned home (day %d)" % home)
	var first_over := int(seen["first_assault_over"])
	assert_gt(first_over, 0, "the first assault was fought out")
	var first_toll := int(seen["dead"].get(first_over, 0))
	assert_gt(first_toll, 0, "and cost the garrison")
	var total := int(seen["dead"][DAYS])
	var bound := first_toll * (seen["assaults"] as Array).size()
	assert_lte(total, bound, "the garrison's dead %d within %d assaults' worth of the first (%d)" % [
		total, (seen["assaults"] as Array).size(), first_toll])
	assert_eq(total, int(seen["dead"][home]), "not one more dead after the host turned home")
	assert_eq(_war_floats(s), [], "no float in the war's state")
	var best := 0
	for e: Dictionary in seen["siege_days"]:
		best = maxi(best, int(e["progress"]))
	gut.p("strong: siege d%d, assaults %d, repulsed rounds %d, best progress %d, lifted d%d, home d%d (%s), garrison dead %d (first assault %d)" % [
		int(seen["siege_begin"]), (seen["assaults"] as Array).size(), (seen["repulsed"] as Array).size(), best,
		int(seen["lifted"]), home, s.ai_hosts[main]["mode"], total, first_toll])


## --- determinism ------------------------------------------------------------------

## `scenario` from one opened save: played twice to DAYS, and saved to disk on
## SAVE_DAY, loaded and played on — all three the same state.
func _deterministic(scenario: String) -> void:
	_prepare(scenario)
	var garrison := _garrison(scenario)
	var opened := Play.opened(repo, TickEngine.new(repo)).to_dict()
	var a := GameState.from_dict(opened)
	var seen := _run(TickEngine.new(repo), a, DAYS, garrison)
	var b := GameState.from_dict(opened)
	_run(TickEngine.new(repo), b, DAYS, garrison)
	assert_eq(SaveLoad.state_hash(b), SaveLoad.state_hash(a), scenario + ": the same save twice, the same state")
	var c := GameState.from_dict(opened)
	var mid := _run(TickEngine.new(repo), c, SAVE_DAY, garrison)
	assert_gt(int(mid["siege_begin"]), 0, scenario + ": saved mid-siege")
	var path := RunDir.dir("invasion_e2e").path_join("%s_day_%d.json" % [scenario, SAVE_DAY])
	assert_true(SaveLoad.save_game(c, path), "saved")
	var loaded := SaveLoad.load_game(path)
	_run(TickEngine.new(repo), loaded, DAYS, garrison, mid)
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(a), scenario + ": a save on day %d plays on the same" % SAVE_DAY)
	assert_eq(_war_floats(loaded), [], scenario + ": no float after the load")
	gut.p("%s: fell %d, home %d, hash %s" % [scenario, int(seen["fell"]), int(seen["home"]), SaveLoad.state_hash(a).left(12)])


func test_weak_defence_is_deterministic_and_saves_mid_run() -> void:
	_deterministic("weak")


func test_strong_defence_is_deterministic_and_saves_mid_run() -> void:
	_deterministic("strong")


## --- the war draws no random number ---------------------------------------------------

## Every day of scenario A — the crossing, the march, the siege, the storm, the
## fall and its cost — the war's systems run on a copy of the day's state in
## TickEngine's order (march, couriers, then the minds, the battles, the
## siege with the defeat inside it, the raids) and leave GameState.rng's
## STATE as it found it. The rest of the day loop may draw; not asserted.
func test_the_war_draws_no_random_number() -> void:
	_prepare("weak")
	var garrison := _garrison("weak")
	var engine := TickEngine.new(repo)
	var s := Play.opened(repo, engine)
	var drawn: Array = []
	var kinds := {}
	var cross := Play.first_appear(repo)
	while s.absolute_day() <= DAYS:
		var today := s.absolute_day()
		var copy := GameState.from_dict(s.to_dict())
		ArmySystem.march_day(repo, copy)
		CourierSystem.ride_day(repo, copy)
		var before: Dictionary = copy.rng.to_dict()
		var ai := EnemyAi.step_day(repo, copy)
		ai.append_array(EnemyAi.think_day(repo, copy))
		EnemyAi.warnings(repo, copy)
		MissiveWriter.host_news(repo, copy, ai)
		var fights := BattleSystem.settle_day(repo, copy)
		var siege := SiegeSystem.settle_day(repo, copy, fights)
		var raid := RaidSystem.settle_day(repo, copy, fights)
		for e: Dictionary in fights + siege + raid:
			kinds[String(e.get("kind", e.get("type", "")))] = true
		if copy.rng.to_dict() != before:
			drawn.append(today)
		_run(engine, s, today, garrison if today == cross else [], {"rumour": 0, "left": {}, "town": "",
			"siege_begin": 0, "siege_days": [], "repulsed": [], "assaults": [], "battle_letters": [], "fell": 0,
			"fallen": {}, "defeat": {}, "before": {}, "home": 0, "lifted": 0, "beat_scheduled": false, "hungry": 0})
	for k: String in ["start", "round", "siege_begin", "siege_fallen", "defeat_town_lost"]:
		assert_true(kinds.has(k), "the copies played a " + k)
	assert_eq(drawn, [], "no day of the war drew from GameState.rng")
