extends GutTest
const People := preload("res://tests/fixtures/military_people.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const RunDir := preload("res://tests/run_dir.gd")
const Play := preload("res://tests/invasion_play.gd")
## The prologue's invasion end to end (spec 2026-10-07-enemy-ai-and-battle-
## design, all of it) on the REAL day loop of a suite campaign. Weak trials
## use the authored defender-routed outcome and main-host HOLD; strong trials
## retain normal combat rules. For the player's defence: on the main host's crossing day the
## town it chose is garrisoned as if the march had already been carried out
## (Play.arrive: the first unit takes the seat, the rest camp round the town —
## the town's garrison all the same, ArmyGround.garrison_town).
##   A  WEAK: the units of the pack's smallest land regiment hold it — the rumour comes,
##      the hosts cross on their days, the main host sits down before the
##      town, fights its defenders and occupies its gate; the loss costs the crown
##      (treasury, contentment, the council, the war beat) and the campaign
##      plays on; a later counterattack can send the host home and liberate it.
##   B  STRONG: the units of the three largest hold it, behind walls and a citadel (the
##      test gives the town them; the host keeps its plan, ai_think_days out of
##      reach — with its own mind it turns away from a garrison it sees) — the
##      town never falls, the garrison never starves, the host goes home.
## Both are deterministic: the same save played twice is the same state, and
## a save on day SAVE_DAY played on equals the run that never stopped. The
## war's state holds no float; each battle round records its one saved-stream draw.

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
	Play.play_through(engine, s, Play.first_appear(repo), true)
	var mind: Dictionary = s.ai_hosts[Play.host(repo, "main")]
	assert_eq(String(mind["mode"]), "ADVANCE", "the main host has crossed")
	assert_eq(String(mind["target_kind"]), "town", "the main host goes for a town")
	return String(mind["target_id"])


## The defence of `scenario` ("weak" | "strong"): the player's smallest
## pack regiment, or of its three largest (Play.regiment_units).
func _garrison(scenario: String) -> Array:
	var weak := scenario == "weak"
	return Play.regiment_units(repo, weak, 1 if weak else 3)


## Sets the repository up for `scenario` BEFORE its campaign is made (every
## run of it shares the data): STRONG walls the chosen town and holds the
## host's plan. Returns the town.
func _prepare(scenario: String) -> String:
	var town := _chosen_town()
	if scenario == "weak":
		for row: Dictionary in repo.battle_outcomes:
			if row["tier"] == "defender_routed":
				var outcome := row.duplicate(true)
				outcome["eff_min"] = 0
				outcome["eff_max"] = 1000
				repo.battle_outcomes = [outcome]
				break
	if scenario == "strong":
		repo.burgs[town]["features"] = "walls|citadel"
		ArmySystem.forget_grids()
		repo.balance["ai_think_days"] = 999.0
	return town



func _opened_trial(engine: TickEngine, scenario: String) -> GameState:
	var state := Play.opened(repo, engine)
	if scenario == "weak":
		for code: String in EnemyAi.regiments_of(state, Play.host(repo, "main")):
			var entry: Dictionary = state.foes[code]
			ArmySystem.apply_hold(entry, "hold", -1, int(entry.get("stance_order_id", 0)) + 1)
	return state

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
		"fought": [], "main_fought": [], "target_contacts": [], "target_battles": {},
		"garrison_battle_dead": 0, "gate_at_fall": false, "occupied_at_fall": [], "first_assault_over": -1,
		"homeward_motion": [], "main_withdrawals": [], "mode_at_fall": "",
		"crown_held_at_fall": true, "liberated": -1, "liberation": {}}
	for k: String in blank:
		if not seen.has(k):
			seen[k] = blank[k]
	var main := Play.host(repo, "main")
	var cross := Play.first_appear(repo)
	while s.absolute_day() <= last:
		var today := s.absolute_day()
		var before := {"treasury": float(s.metrics["treasury"]),
			"content": float(s.metrics["peasant_contentment"])}
		var homeward_before := {}
		if String(s.ai_hosts[main]["mode"]) in EnemyAi.HOMEWARD:
			for code: String in EnemyAi.regiments_of(s, main):
				var entry: Dictionary = s.foes[code]
				homeward_before[code] = {"at": Vector2i(int(entry["x_m"]), int(entry["y_m"])),
					"can_march": CampSystem.can_march(s, code, today)}
		Play.day(engine, s, true)
		for code: String in homeward_before:
			var entry: Dictionary = s.foes[code]
			var at := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
			seen["homeward_motion"].append({"code": code, "day": today,
				"can_march": homeward_before[code]["can_march"], "moved": at != homeward_before[code]["at"]})
		if int(seen["rumour"]) < 0 and not Play.letters(s, "rumour").is_empty():
			seen["rumour"] = today
		for h: String in EnemyAi.host_codes(s):
			if String(s.ai_hosts[h]["mode"]) != "ASSEMBLE" and not (seen["left"] as Dictionary).has(h):
				seen["left"][h] = today
		if today == cross:
			var town := String(s.ai_hosts[main]["target_id"])
			seen["town"] = town
			for c: String in garrison:
				Play.arrive(repo, s, c, Play.town_m(repo, town))
			seen["garrison"] = garrison.duplicate()
		for e: Dictionary in engine.day_siege:
			if String(e.get("town", "")) != String(seen["town"]) or String(e.get("host", "")) != main:
				continue
			match String(e.get("kind", "")):
				"siege_begin":
					if int(seen["siege_begin"]) < 0:
						seen["siege_begin"] = today
				"siege_day":
					if String(e.get("town", seen["town"])) != String(seen["town"]):
						continue      # another host's siege of another town (the claims are the chosen town's)
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
					seen["occupied_at_fall"] = (s.ai_hosts[main].get("occupied", {}) as Dictionary).keys()
					seen["mode_at_fall"] = String(s.ai_hosts[main]["mode"])
					seen["crown_held_at_fall"] = EnemyAi.target_held(repo, s, "town", String(seen["town"]))
					for code: String in EnemyAi.live_regiments(repo, s, main):
						if BattleSystem.town_contact(repo, s, String(seen["town"]), code) == String(seen["town"]):
							seen["gate_at_fall"] = true
				"defeat_town_lost":
					seen["defeat"] = e
					seen["beat_scheduled"] = (s.event_state["scheduled"] as Array).any(
						func(sc: Dictionary) -> bool: return String(sc["event_id"]) == DefeatSystem.EVENT_ID)
				"siege_lifted":
					seen["lifted"] = today
				"siege_liberated":
					seen["liberated"] = today
					seen["liberation"] = e
		for e: Dictionary in engine.day_battles:
			for left: Dictionary in e.get("left", []):
				var code := String(left["code"])
				if String(left["why"]) == "withdrawn" and String(s.foes.get(code, {}).get("host", "")) == main:
					var enemy_side := "def" if left["side"] == "att" else "att"
					seen["main_withdrawals"].append({"code": code, "day": today,
						"separated": BattleSystem._separated(repo, s, code, e.get(enemy_side, []))})
			var k := String(e.get("kind", ""))
			var participants: Array = (e.get("att", []) as Array) + (e.get("def", []) as Array)
			var main_present := participants.any(func(c: String) -> bool:
				return String((s.foes.get(c, {}) as Dictionary).get("host", "")) == main)
			var target_guard_present := participants.any(func(c: String) -> bool: return c in seen["garrison"])
			if k in ["start", "round"] and main_present:
				if not today in seen["main_fought"]: seen["main_fought"].append(today)
				if target_guard_present:
					if not today in seen["fought"]: seen["fought"].append(today)
					seen["target_battles"][int(e["battle_id"])] = true
					if k == "start":
						var contact := e.duplicate(true)
						contact["on"] = today
						seen["target_contacts"].append(contact)
			if k == "round":
				for code: String in e.get("results", {}):
					if code in seen["garrison"]:
						seen["garrison_battle_dead"] += int(e["results"][code]["dead"])
			if k == "start" and String(e["town"]) == String(seen["town"]):
				var a := e.duplicate()
				a["on"] = today
				seen["assaults"].append(a)
			if k == "end" and String(e["town"]) == String(seen["town"]) and int(seen["first_assault_over"]) < 0:
				seen["first_assault_over"] = today
		var dead := 0
		for c: String in seen["garrison"]:
			dead += People.count(s, c, "dead")
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
	var s := _opened_trial(engine, "weak")
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
	# The defenders may fight in their outer camp before the gate is taken.
	# A town label is not required for that real engagement.
	var contacts: Array = seen["target_contacts"]
	assert_gt(contacts.size(), 0, "the main host fought the target's defenders")
	var first_contact := int(contacts[0]["on"]) if not contacts.is_empty() else -1
	assert_gte(first_contact, begun, "contact follows the host's deployment")
	assert_true(first_contact in seen["battle_letters"], "the engagement has a battle report")
	var fell := int(seen["fell"])
	assert_gte(fell, first_contact, "the target falls after its defenders are engaged")
	assert_gt(fell, 0, "the main target really falls within the scenario")
	assert_true(bool(seen["gate_at_fall"]), "occupation requires a real column at the gate")
	assert_eq(String(seen["mode_at_fall"]), "HOLD", "capture takes effect as HOLD on the fall day")
	assert_false(bool(seen["crown_held_at_fall"]), "the town is not the crown's at capture")
	var cells: Array = seen["occupied_at_fall"]
	assert_gt(cells.size(), 0, "manors taken")
	var capture_log: Array = s.manor_log.filter(func(l: Dictionary) -> bool:
		return String(l["reason"]) == String(seen["fallen"].get("reason", "")))
	assert_eq(capture_log.size(), cells.size(), "each target manor moved once")
	for l: Dictionary in capture_log:
		assert_true(str(int(l["cell"])) in cells, "a taken manor")
		assert_true(String(l["reason"]).begins_with("taken by ") and String(l["reason"]).contains("siege of " + label),
			"with its reason: " + String(l["reason"]))
	if int(seen["liberated"]) < 0:
		assert_eq(String(s.ai_hosts[main]["mode"]), "HOLD", "the host holds the town")
		assert_false(EnemyAi.target_held(repo, s, "town", town), "the town is not the crown's")
	else:
		assert_gt(int(seen["liberated"]), fell, "liberation follows actual capture")
		assert_gt(int(seen["home"]), fell, "the host retreats after capture")
		assert_eq(String(seen["liberation"]["why"]), "retreat")
		assert_eq(String(s.ai_hosts[main]["mode"]), "RETREAT")
		assert_true(EnemyAi.target_held(repo, s, "town", town), "retreat restores the crown's town")
		var reason := "liberated: %s left %s" % [SiegeSystem.host_label(repo, main), label]
		var liberation_log: Array = s.manor_log.filter(func(line: Dictionary) -> bool: return line["reason"] == reason)
		assert_eq(liberation_log.size(), cells.size(), "each occupied manor is restored exactly once")
		for cell: Variant in cells:
			assert_eq(liberation_log.filter(func(line: Dictionary) -> bool: return int(line["cell"]) == int(cell)).size(), 1)
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
	var lines: Array = s.world_log.filter(func(l: Dictionary) -> bool:
		return String(l["source"]) == "defeat" and String(l["reason"]).contains("lost " + label + " to "))
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
	assert_eq(s.town_losses.filter(func(l: Dictionary) -> bool: return String(l["town"]) == town).size(), 1, "target loss is charged once")
	assert_eq(_war_floats(s), [], "no float in the war's state")
	# and the campaign plays on: three more months, every event answered
	var events := EventSystem.new(repo)
	var presented: Array = []
	while s.absolute_day() <= 3 * Calendar.DAYS_PER_TICK:
		Play.day(engine, s, true)
		if not s.pending_event.is_empty():
			presented.append(String(s.pending_event["event_id"]))
			var first: Dictionary = (s.pending_event["choices"] as Array)[0]
			assert_false(events.apply_choice(String(first["choice_id"]), s).is_empty(), "answered")
	assert_eq(s.tick, 4, "into the fourth month")
	assert_eq(_war_floats(s), [], "still no float")
	gut.p("weak: rumour d%d, cross %s, siege d%d, first contact d%d, fell d%d (%d manors), gold -%d, content -%d, %d opinions; then events %s" % [
		int(seen["rumour"]), seen["left"], begun, first_contact, fell, cells.size(), int(d["gold"]), int(d["morale"]),
		ops.size(), presented])


## --- B: a strong defence holds until the besieger retreats ----------------------

func test_strong_walled_defence_holds_and_forces_supply_retreat() -> void:
	_prepare("weak")
	var weak_garrison := _garrison("weak")
	var weak_state := _opened_trial(TickEngine.new(repo), "weak")
	var weak_seen := _run(TickEngine.new(repo), weak_state, DAYS, weak_garrison)
	var weak_fall := int(weak_seen["fell"])
	repo = SuiteData.repo()
	Weather.forget()
	var town := _prepare("strong")
	var garrison := _garrison("strong")
	var starting_heads := 0
	for code: String in garrison:
		starting_heads += ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))
	var engine := TickEngine.new(repo)
	var s := Play.opened(repo, engine)
	var seen := _run(engine, s, DAYS, garrison)
	var main := Play.host(repo, "main")
	assert_eq(String(seen["town"]), town, "the walled town")
	assert_gt(int(seen["siege_begin"]), 0, "the host sat down before it")
	assert_gt((seen["target_contacts"] as Array).size(), 0, "the main host fought the defenders, including outer camps")
	assert_eq(int(seen["fell"]), -1, "the town never falls")
	assert_true(EnemyAi.target_held(repo, s, "town", town), "still the crown's")
	var label := String(repo.burgs[town]["label"])
	assert_true(s.manor_log.filter(func(l: Dictionary) -> bool:
		return String(l["reason"]).ends_with(": siege of " + label)).is_empty(), "no target manor captured")
	assert_true(s.town_losses.filter(func(l: Dictionary) -> bool: return String(l["town"]) == town).is_empty(), "no target loss paid")
	assert_true((s.world_log as Array).filter(func(l: Dictionary) -> bool:
		return String(l["source"]) == "defeat" and String(l["reason"]).contains("lost " + label + " to ")).is_empty(), "no target defeat line")
	assert_eq(int(seen["hungry"]), 0, "the garrison never starved")
	assert_gt(int(seen["lifted"]), 0, "the siege is lifted")
	assert_gt(int(seen["home"]), int(seen["siege_begin"]), "the host goes home")
	assert_true(String(s.ai_hosts[main]["mode"]) in EnemyAi.HOMEWARD, "RETREAT or WITHDRAW")
	for c: String in garrison:
		assert_gt(ArmySystem.fit_count(repo, s, c), 0,
			c + " still stands")
	var home := int(seen["home"])
	assert_gt((seen["main_fought"] as Array).filter(func(d: int) -> bool: return d >= home).size(), 0,
		"the main host remains exposed while withdrawing through physical contact")
	assert_gt((seen["homeward_motion"] as Array).filter(func(e: Dictionary) -> bool: return e["moved"]).size(), 0,
		"surviving homeward columns leave by marching")
	for motion: Dictionary in seen["homeward_motion"]:
		if not bool(motion["can_march"]):
			assert_false(motion["moved"], "%s waits for its camp departure gate on day %d" % [motion["code"], motion["day"]])
	assert_gt((seen["main_withdrawals"] as Array).size(), 0, "columns actually disengage before the trial ends")
	for left: Dictionary in seen["main_withdrawals"]:
		assert_true(left["separated"], "%s leaves combat only after physical separation" % left["code"])
	var total := int(seen["dead"][DAYS])
	assert_gt(total, 0, "the real encounters cost the garrison")
	assert_eq(total, int(seen["garrison_battle_dead"]),
		"all recorded garrison deaths equal its round-by-round battle losses, across hosts")
	assert_eq(_war_floats(s), [], "no float in the war's state")
	var best := 0
	for e: Dictionary in seen["siege_days"]:
		best = maxi(best, int(e["progress"]))
	gut.p("strong: siege d%d, assaults %d, repulsed rounds %d, best progress %d, lifted d%d, home d%d (%s), garrison dead %d (reported %d)" % [
		int(seen["siege_begin"]), (seen["assaults"] as Array).size(), (seen["repulsed"] as Array).size(), best,
		int(seen["lifted"]), home, s.ai_hosts[main]["mode"], total, int(seen["garrison_battle_dead"])])


## --- determinism ------------------------------------------------------------------

## `scenario` from one opened save: played twice to DAYS, and saved to disk on
## SAVE_DAY, loaded and played on — all three the same state.
func _deterministic(scenario: String) -> void:
	_prepare(scenario)
	var garrison := _garrison(scenario)
	var opened := _opened_trial(TickEngine.new(repo), scenario).to_dict()
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


## With authored event opportunities disabled, the AI, siege and raids draw
## nothing; each completed battle round consumes exactly its recorded draw.
func test_round_only_war_randomness_with_event_opportunities_disabled() -> void:
	repo.battle_events.clear()
	_prepare("weak")
	var garrison := _garrison("weak")
	var engine := TickEngine.new(repo)
	var s := _opened_trial(engine, "weak")
	var rounds := 0
	var kinds := {}
	var cross := Play.first_appear(repo)
	while s.absolute_day() <= DAYS:
		var today := s.absolute_day()
		var copy := GameState.from_dict(s.to_dict())
		var copy_engine := TickEngine.new(repo)
		var tx := DayResolution.begin(copy.day, copy.day >= Calendar.DAYS_PER_TICK,
			copy.absolute_day())
		copy.day_resolution = tx
		var before_setup := copy.rng.to_dict()
		for phase: String in DayResolution.PHASES.slice(0, 5):
			copy_engine._resolve_phase(copy, tx, phase)
			copy_engine._restore_day_outputs(tx)
		assert_eq(copy.rng.to_dict(), before_setup,
			"day setup and AI do not draw randomness on day %d" % today)
		var before: Dictionary = copy.rng.to_dict()
		var expected_rng := Rng.from_dict(before)
		tx.phase = "FIXED_TACTICAL_SUBSTEPS"
		tx.phase_cursor = DayResolution.PHASES.find(tx.phase)
		var tactical := copy_engine._resolve_phase(copy, tx, "FIXED_TACTICAL_SUBSTEPS")
		copy_engine._restore_day_outputs(tx)
		while bool(tactical.get("blocked", false)):
			var decision := copy_engine.resolve_decision(copy, String(tx.pending_decision.token), "continue")
			assert_eq(decision.status, "accepted")
			if decision.status != "accepted":
				return
			tactical = copy_engine._resolve_phase(copy, tx, "FIXED_TACTICAL_SUBSTEPS")
			copy_engine._restore_day_outputs(tx)
		var fights: Array = copy_engine.day_battles
		for event: Dictionary in fights:
			if event.get("kind", "") == "round":
				assert_eq(int(event["roll"]), expected_rng.randi_range(0, 999),
					"battle %d round %d records the next saved draw" % [event["battle_id"], event["round"]])
				rounds += 1
		assert_eq(copy.rng.to_dict(), expected_rng.to_dict(), "one draw per battle round on day %d" % today)
		var after_battles := copy.rng.to_dict()
		copy_engine._resolve_phase(copy, tx, "SIEGES")
		copy_engine._restore_day_outputs(tx)
		copy_engine._resolve_phase(copy, tx, "RAIDS")
		copy_engine._restore_day_outputs(tx)
		var siege: Array = copy_engine.day_siege
		var raid: Array = copy_engine.day_raid
		for e: Dictionary in fights + siege + raid:
			kinds[String(e.get("kind", e.get("type", "")))] = true
		assert_eq(copy.rng.to_dict(), after_battles, "siege and raids do not draw randomness on day %d" % today)
		_run(engine, s, today, garrison if today == cross else [], {"rumour": 0, "left": {}, "town": "",
			"siege_begin": 0, "siege_days": [], "repulsed": [], "assaults": [], "battle_letters": [], "fell": 0,
			"fallen": {}, "defeat": {}, "before": {}, "home": 0, "lifted": 0, "beat_scheduled": false, "hungry": 0})
	for k: String in ["start", "round", "siege_begin", "siege_fallen", "defeat_town_lost"]:
		assert_true(kinds.has(k), "the copies played a " + k)
	assert_gt(rounds, 0, "the seeded invasion exercised real battle draws")
