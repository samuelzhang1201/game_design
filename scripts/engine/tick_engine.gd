class_name TickEngine
extends RefCounted

var data: DataRepository
var actions: ActionSystem
var suggestions: SuggestionGenerator
var events: EventSystem
var last_day_result: Dictionary = {}
var last_month_report: TickReport

func _init(d: DataRepository) -> void:
	data = d
	actions = ActionSystem.new(d)
	suggestions = SuggestionGenerator.new(d, actions)
	events = EventSystem.new(d)

## Resolve one complete day as a saved synchronous transaction. Effects and
## cursor movement are persisted together before the method returns to a caller.
func resolve_day(state: GameState) -> Dictionary:
	last_month_report = null
	if state.day_resolution.is_empty():
		var tx := DayResolution.begin(state.day, state.day >= Calendar.DAYS_PER_TICK,
			state.absolute_day(), int(data.bal("battle_substeps")))
		state.day_resolution = tx
	var tx: Dictionary = state.day_resolution
	var incompatibility := DayResolution.incompatibility_reason(tx)
	if not incompatibility.is_empty():
		return {"status": "incompatible", "reason": incompatibility}
	_restore_day_outputs(tx)
	while true:
		if not (tx.get("pending_decision", {}) as Dictionary).is_empty():
			return {"status": "blocked", "decision": (tx["pending_decision"] as Dictionary).duplicate(true),
				"journal": (tx["journal"] as Dictionary).duplicate(true)}
		var cursor := int(tx.get("phase_cursor", 0))
		if cursor >= DayResolution.PHASES.size():
			break
		var phase := DayResolution.PHASES[cursor]
		var outcome := _resolve_phase(state, tx, phase)
		if bool(outcome.get("blocked", false)):
			_restore_day_outputs(tx)
			return {"status": "blocked", "decision": (tx["pending_decision"] as Dictionary).duplicate(true),
				"journal": (tx["journal"] as Dictionary).duplicate(true)}
		tx["phase_cursor"] = cursor + 1
		tx["phase"] = DayResolution.PHASES[cursor + 1] if cursor + 1 < DayResolution.PHASES.size() else "COMPLETE"
		_restore_day_outputs(tx)
	# The calendar phase already advanced an ordinary day or settled the
	# month-end tick before this completed transaction is cleared.
	var result := {"status": "complete", "finished": (tx["journal"]["works"] as Array).duplicate(true),
		"journal": (tx["journal"] as Dictionary).duplicate(true),
		"resolved_day": int(tx.get("day", state.day))}
	state.day_resolution = {}
	return result


## Legacy day callers still receive the finished-work array. A blocked day
## returns no completed work and keeps its transaction in GameState.
func advance_day(state: GameState) -> Array:
	last_day_result = resolve_day(state)
	return (last_day_result.get("finished", []) as Array).duplicate(true)


func _restore_day_outputs(tx: Dictionary) -> void:
	var journal: Dictionary = tx.get("journal", {})
	day_arrivals = (journal.get("arrivals", []) as Array).duplicate(true)
	day_couriers = (journal.get("couriers", []) as Array).duplicate(true)
	day_battles = (journal.get("battles", []) as Array).duplicate(true)
	day_siege = (journal.get("sieges", []) as Array).duplicate(true)
	day_raid = (journal.get("raids", []) as Array).duplicate(true)
	day_supply = (journal.get("supply", []) as Array).duplicate(true)
	day_conduct = (journal.get("conduct", []) as Array).duplicate(true)
	day_ai = []
	for record: Dictionary in journal.get("reports", []):
		if String(record.get("kind", "")) == "host_events":
			day_ai.append_array(record.get("events", []))


func _save_host_events(journal: Dictionary, events: Array) -> void:
	var reports: Array = journal.get("reports", [])
	reports = reports.filter(func(record: Dictionary) -> bool:
		return String(record.get("kind", "")) != "host_events")
	reports.append({"kind": "host_events", "events": events.duplicate(true)})
	journal["reports"] = reports


func _resolve_phase(state: GameState, tx: Dictionary, phase: String) -> Dictionary:
	var journal: Dictionary = tx["journal"]
	match phase:
		"WORKS":
			journal["works"] = MapManors.advance_works(data, state)
		"MARCH_ORDERS_AND_ROUTE_SETUP":
			var moving: Array = []
			var budgets: Dictionary = {}
			var march_entries: Dictionary = {}
			for table: Dictionary in [state.regiments, state.foes]:
				var codes: Array = table.keys()
				codes.sort()
				for code_value: Variant in codes:
					var code := String(code_value)
					if String(table[code].get("order", "")) == ArmySystem.ORDER_MARCH:
						moving.append(code)
						var budget := ArmySystem.day_walk_budget(data, state, code)
						var entry: Dictionary = table[code].duplicate(true)
						var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
						entry["finish_today"] = budget >= int(ceil(MarchRoute.length_from(here,
							ArmySystem._path_of(entry))))
						budgets[code] = budget
						march_entries[code] = entry
			tx["march_entries"] = march_entries
			tx["marching_codes"] = moving
			tx["march_budgets"] = budgets
		"COURIERS":
			journal["couriers"] = CourierSystem.ride_day(data, state)
		"AI_AND_SCOUT":
			day_ai = EnemyAi.step_day(data, state)
			day_ai.append_array(EnemyAi.think_day(data, state))
			for m: Dictionary in EnemyAi.warnings(data, state):
				MissiveLog.add(data, state, m)
			_save_host_events(journal, day_ai)
		"SIGHTING_AND_INTEL_REFRESH":
			Sighting.scout_day(data, state)
		"FIXED_TACTICAL_SUBSTEPS":
			return _resolve_battles(state, tx)
		"SIEGES":
			day_siege = SiegeSystem.settle_day(data, state, day_battles)
			journal["sieges"] = day_siege.duplicate(true)
		"RAIDS":
			var raids := RaidSystem.settle_day(data, state, day_battles)
			journal["raids"] = raids
			day_raid = raids.duplicate(true)
			day_ai.append_array(day_siege.filter(func(e: Dictionary) -> bool: return e.has("type")))
			day_ai.append_array(day_raid.filter(func(e: Dictionary) -> bool: return e.has("type")))
			_save_host_events(journal, day_ai)
		"CAMPS_AND_SIGHTING":
			ArmySystem.hold_day(data, state)
			Sighting.update(data, state)
		"SUPPLY_AND_CONDUCT":
			day_supply = SupplyLines.set_out_events(day_couriers)
			day_supply.append_array(SupplyLines.day_step(data, state))
			ArmySystem.eat_day(data, state)
			ArmySystem.hunger_day(data, state)
			day_conduct = ArmyConduct.day_step(data, state)
			day_supply.append_array(SupplyLines.warn_day(data, state))
			journal["supply"] = day_supply.duplicate(true)
			journal["conduct"] = day_conduct.duplicate(true)
		"DAILY_ECONOMY":
			RealmEconomy.step_day(data, state)
		"REPORTS":
			var host_news := MissiveWriter.host_news(data, state, day_ai)
			if not host_news.is_empty():
				MissiveLog.add(data, state, host_news)
			var fights: Array = day_battles + SiegeSystem.news(day_siege) + RaidSystem.news(day_raid)
			if not fights.is_empty():
				MissiveLog.add(data, state, MissiveWriter.battle_report(data, state, fights))
			if not day_supply.is_empty():
				MissiveLog.add(data, state, MissiveWriter.supply_dispatch(data, state, day_supply))
			if not day_conduct.is_empty():
				MissiveLog.add(data, state, MissiveWriter.conduct_dispatch(data, state, day_conduct))
		"MONTH_END_IF_NEEDED":
			if bool(tx.get("month_end", false)) or bool(tx.get("settle_month_compat", false)):
				last_month_report = _settle_month(state)
		"CALENDAR":
			if not bool(tx.get("month_end", false)) and not bool(tx.get("settle_month_compat", false)):
				state.day = mini(int(tx["day"]) + 1, Calendar.DAYS_PER_TICK)
		"COMPLETE":
			pass
	return {"blocked": false}


func _resolve_battles(state: GameState, tx: Dictionary) -> Dictionary:
	var journal: Dictionary = tx["journal"]
	if not tx.has("over_battle_ids"):
		tx["over_battle_ids"] = []
	if not tx.has("processed_battle_ids"):
		tx["processed_battle_ids"] = []
	while int(tx["substep_index"]) < int(tx.get("substep_count", DayResolution.DEFAULT_SUBSTEP_COUNT)):
		if String(tx.get("battle_step", "")) == "":
			var arrivals := ArmySystem.march_day_saved(data, state, int(tx["substep_count"]),
				int(tx["substep_index"]), tx.get("march_entries", {}), tx.get("march_budgets", {}))
			(journal["arrivals"] as Array).append_array(arrivals)
			ArmyGround.reconcile(data, state)
			LawSystem.reconcile(data, state)
			var host_arrivals := EnemyAi.arrival_substep(data, state)
			if not host_arrivals.is_empty():
				day_ai.append_array(host_arrivals)
				_save_host_events(journal, day_ai)
			var contacts := BattleSystem.prepare_day(data, state) if int(tx["substep_index"]) == 0 \
				else BattleSystem.discover_contacts(data, state)
			_append_substep_battle_events(journal, contacts, int(tx["substep_index"]))
			var started: Array = []
			for event: Dictionary in contacts:
				if String(event.get("kind", "")) == "start":
					started.append(int(event["battle_id"]))
			tx["substep_battle_ids"] = started
			tx["battle_step"] = "contacted"
		for battle_id: int in tx.get("substep_battle_ids", []):
			if battle_id in (tx.get("acknowledged_encounters", []) as Array):
				continue
			if (tx.get("pending_decision", {}) as Dictionary).is_empty():
				DayResolution.block_on_encounter(tx, battle_id)
			return {"blocked": true}
		if String(tx.get("battle_step", "")) != "fighting":
			var ids: Array = []
			for battle: Dictionary in state.battles:
				var id := int(battle["id"])
				if not id in (tx.get("over_battle_ids", []) as Array) \
						and not id in (tx.get("processed_battle_ids", []) as Array):
					ids.append(id)
			ids.sort()
			tx["battle_ids"] = ids
			tx["battle_index"] = 0
			tx["battle_step"] = "fighting"
		while int(tx["battle_index"]) < (tx["battle_ids"] as Array).size():
			var index := int(tx["battle_index"])
			var battle_id := int(tx["battle_ids"][index])
			var result := BattleSystem.step_battle(data, state, battle_id)
			_append_substep_battle_events(journal, result["events"], int(tx["substep_index"]))
			(tx["processed_battle_ids"] as Array).append(battle_id)
			if bool(result["over"]):
				(tx["over_battle_ids"] as Array).append(battle_id)
			tx["battle_index"] = index + 1
		if not (tx["over_battle_ids"] as Array).is_empty():
			state.battles = state.battles.filter(func(b: Dictionary) -> bool:
				return not int(b["id"]) in (tx["over_battle_ids"] as Array))
		tx["battle_ids"] = []
		tx["battle_index"] = 0
		tx["battle_step"] = ""
		tx["substep_battle_ids"] = []
		tx["substep_index"] = int(tx["substep_index"]) + 1
	BattleSystem.finish_day(state, tx.get("over_battle_ids", []))
	return {"blocked": false}


func _append_substep_battle_events(journal: Dictionary, events: Array, substep_index: int) -> void:
	for event: Dictionary in events:
		var recorded := event.duplicate(true)
		recorded["substep_index"] = substep_index
		(journal["battles"] as Array).append(recorded)


## Compatibility for TickEngine.advance and older internal callers.
func _end_day(state: GameState) -> Array:
	var result := resolve_day(state)
	return (result.get("finished", []) as Array).duplicate(true)

## The regiments that reached their destination in the last advance_day, in
## code order — read by Game for the news bar and by nothing else.
var day_arrivals: Array = []

## The couriers' events of the last day (CourierSystem.ride_day), for the news bar.
var day_couriers: Array = []

## The supply lines' events of the last day (SupplyLines.day_step), for the
## marshal's dispatches.
var day_supply: Array = []

## The foraging and desertion events of the last day (ArmyConduct.day_step),
## for the marshal's report.
var day_conduct: Array = []

## The battles' events of the last day (BattleSystem.settle_day), for the
## battle report.
var day_battles: Array = []

## The sieges' events of the last day (SiegeSystem.settle_day), the quiet
## siege_day included; the battle letter carries SiegeSystem.news of them.
var day_siege: Array = []

## The raids' events of the last day (RaidSystem.settle_day: raid_spoils,
## raid_begin, the quiet raid_day, host_mode); the battle letter carries
## RaidSystem.news of them.
var day_raid: Array = []

## The hosts' events of the last day (EnemyAi.step_day then think_day:
## host_advance, host_mode), for the host-news letter.
var day_ai: Array = []

## The buildings the last advance() left idle that were working the month
## before (M5), [{cell, building, missing}] in cell then code order — read
## by Game for the news bar, ONCE per spell idle; never in the TickReport.
var newly_idle: Array = []

## The month's hazard news (Hazards: the toll, then the endings), for the news bar.
var month_hazard_news: Array = []

func _newly_idle(state: GameState, was_idle: Dictionary) -> Array:
	var out: Array = []
	var keys: Array = state.idle_buildings.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var codes: Array = (state.idle_buildings[key] as Array).duplicate()
		codes.sort()
		for code: String in codes:
			if not code in (was_idle.get(key, []) as Array):
				out.append({"cell": int(key), "building": code,
					"missing": IndustrySystem.missing_of(data, state, int(key), code)})
	return out


func advance(state: GameState) -> TickReport:
	# The reign's opening call settles the initial ledger but does not consume
	# its first playable day. Every later call resumes the saved day transaction.
	last_month_report = null
	if state.tick == 0:
		day_arrivals = []
		day_couriers = []
		day_battles = []
		day_siege = []
		day_raid = []
		day_ai = []
		day_supply = []
		day_conduct = []
		return _settle_month(state)
	var had_saved_transaction := not state.day_resolution.is_empty()
	if not had_saved_transaction:
		var tx := DayResolution.begin(state.day, state.day >= Calendar.DAYS_PER_TICK,
			state.absolute_day(), int(data.bal("battle_substeps")))
		if state.day < Calendar.DAYS_PER_TICK:
			tx["settle_month_compat"] = true
		state.day_resolution = tx
	var day_result := resolve_day(state)
	if String(day_result["status"]) == "blocked" or String(day_result["status"]) == "incompatible":
		var blocked := TickReport.new()
		blocked.status = String(day_result["status"])
		blocked.pending_decision = (day_result.get("decision", {}) as Dictionary).duplicate(true)
		return blocked
	var report := last_month_report if last_month_report != null else TickReport.new()
	report.finished_works = (day_result.get("finished", []) as Array).duplicate(true)
	return report


func _settle_month(state: GameState) -> TickReport:
	var r := TickReport.new()
	# The month that just ended is settled BEFORE the tick moves: its lines
	# are the month's own (growth of tick t), and the ledger reasons carry
	# its tick.
	_settle_economy(state, r)
	# Buildings eat (spec 2026-09-30-ledger-industry-trade-design, M5): with
	# this month's goods in, the lord's input buildings buy next month's
	# inputs, or stand idle. No RealmEconomy.forget(): the province key and
	# the realm signature carry idle_buildings, so only a province whose
	# idle set moved goes stale — and the tick below stales them all anyway,
	# to be recomputed by the day buckets, not in one lump at the month's turn.
	var was_idle: Dictionary = state.idle_buildings.duplicate(true)
	for l: Dictionary in IndustrySystem.settle_month(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(int(l["delta"])), String(l["reason"]))
	newly_idle = _newly_idle(state, was_idle)
	# The war workshops (spec 2026-09-30-ledger-supply-design §2): this
	# month's civil goods are in; turn the lord's share into arms before the
	# supply lines ship.
	for l: Dictionary in WorkshopSystem.settle_month(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(int(l["delta"])), String(l["reason"]))
	# The trade tolls (spec 2026-09-30-ledger-industry-trade-design, M6):
	# after the workshops, with the month's other flows. A toll reads only
	# ownership, the deals and the steward, and pays into the TREASURY, which
	# neither the workshops (the lord's goods) nor the supply lines (the
	# strategic goods) touch — so its place among them changes no figure;
	# it stands here, before the supply lines, so the month's income is all
	# in before anything of the month is spent.
	for l: Dictionary in MarketSystem.settle_month(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(int(l["delta"])), String(l["reason"]))
	# The provinces' wealth tiers are settled with the month (Ruling 15):
	# state, so no reader's timing can decide what a spy's report says.
	Intel.settle_wealth_tiers(data, state)
	# Whatever else moved the strategic pools this month (the workshops'
	# lines, the industry's inputs) is settled into the towns.
	TownStores.reconcile(data, state)
	# The steward's report on the month just settled (owner 2026-09-28): ground
	# truth. The reign's OPENING tick (tick 0, the one GameRoot runs once at
	# start before any day is played) settles no real month, so it files no
	# report (fix round 1 finding 3) — tick is 0 here only on that one call;
	# every later settled month has already been incremented past it.
	if state.tick > 0:
		MissiveLog.add(data, state, MissiveWriter.monthly(data, state, state.tick))
	# The regiments' month (owner 2026-09-17; morale, spec 2026-09-30-ledger-
	# supply-design §4): wounded return, morale drifts toward what the stores
	# just refilled allow, training grows (the supplies are eaten daily).
	ArmySystem.settle_month(data, state)
	# The columns that lived off the land settle their month right after it
	# (spec 2026-10-10-foraging-and-desertion §3.3 step 8, ruling R8), so the
	# drift and the wound recovery above do not undo the foraging's gain and
	# wounds. Once per advance: once a month, the reign's opening tick included
	# (no unit has foraged then).
	ArmyConduct.settle_units(data, state)
	# The camp laws' month (laws spec §4.2): each realm line scaled by the
	# share of the host's men under its value.
	for l: Dictionary in LawEffects.month_lines(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(l["delta"]), String(l["reason"]))
	# The development axes' month (spec 2026-10-12-development-axes §5): the
	# laws' drift and the untended decay, one DEVELOPMENT outcome.
	DevelopmentSystem.settle_month(data, state)
	# Their tier effects pay AFTER the settlement, so a tier reached this month
	# pays this month.
	for l: Dictionary in DevelopmentSystem.month_lines(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(l["delta"]), String(l["reason"]))
	# The marshal's month (spec 2026-10-07-army-supply-lines §5.5): his
	# report, his skims banked, the lines' counters reset.
	var supply_rows := SupplyLines.settle_month(data, state)
	if state.tick > 0:
		MissiveLog.add(data, state, MissiveWriter.marshal_report(data, state, state.tick, supply_rows))
	# The hazards take their month's toll (spec 2026-10-07-war-room-p2 §2.3).
	month_hazard_news = Hazards.settle_regiments(data, state)
	state.tick += 1
	state.day = 1
	month_hazard_news.append_array(Hazards.settle_month(data, state))
	r.tick = state.tick
	r.season = state.season()
	r.year = state.year()
	r.outcomes = state.recent_outcomes
	state.recent_outcomes = []
	_drift(state, r)
	r.relationship_deltas = RelationshipGraph.drift(state, data)
	r.claim_resolutions = ClaimLedger.resolve_due(data, state, state.tick)
	for pr in state.promises:
		if String(pr["status"]) == "open" and state.tick > int(pr["tick_due"]):
			pr["status"] = "broken"
			var who: String = String(pr["character_id"])
			if state.characters.has(who):
				var c: Character = state.characters[who]
				c.change_opinion(int(data.bal("promise_broken_opinion")),
					"a promise broken: " + String(pr["promise_code"]), state.tick)
				if not "grudge" in c.flags:
					c.flags.append("grudge")
			r.promise_events.append({"character_id": who,
				"promise_code": String(pr["promise_code"]), "status": "broken"})
	r.concerns = ConcernScanner.scan(state, data)
	r.suggestions = suggestions.generate(state, r.concerns)
	r.event = events.roll(state).duplicate(true)
	return r



## The month's settlement (spec §5): the crown's provinces in full, the
## crown's share of the rest, less the ministers' salaries and the court's
## ration; the harvest in autumn. Whole gold, from RealmEconomy's sums.
func _settle_economy(state: GameState, r: TickReport) -> void:
	# Every key is there: GameState.default_metrics is the one place a
	# metric's presence is settled, for a fresh campaign and an old save alike.
	var m := state.metrics
	var p := RealmEconomy.purses(data, state)
	var lord: Dictionary = p["lord"]
	var crown_share: Dictionary = p["realm_share"]
	# Two purses (owner 2026-09-14). The LORD's: the provinces the player's
	# house controls pay into it in full — gold, strategic and civil goods.
	_apply(r, m, "lord_gold", float(int(lord["tax"])), "taxes of your own provinces")
	_apply(r, m, "lord_strategic", float(int(lord["strategic"])), "your own provinces' strategic goods")
	_apply(r, m, "lord_civil", float(int(lord["civil"])), "your own provinces' civil goods")
	# The CROWN's treasury and stores: its share of every other province.
	_apply(r, m, "treasury", float(int(crown_share["tax"])), "the crown's share of the realm's taxes")
	_apply(r, m, "strategic", float(int(crown_share["strategic"])),
		"the crown's share of the realm's strategic goods")
	_apply(r, m, "grain", float(int(crown_share["civil"])), "the crown's share of the realm's civil goods")
	# ...and the same goods into the towns that hold them (spec 2026-10-07-army-
	# supply-lines §3.1): the metrics just raised are the towns' sums.
	TownStores.deposit_month(data, state)
	_set_metric(r, m, "tax_income", float(int(lord["tax"]) + int(crown_share["tax"])), "taxes collected this month")
	# The court is the crown's: its ministers and its table.
	var salaries := 0
	for seat: String in state.council:
		salaries += int(float((data.seats.get(seat, {}) as Dictionary).get("salary_gold", 0)))
	_apply(r, m, "treasury", float(-salaries), "ministers' salaries")
	var people := court_people(data, state)
	var ration := ration_of(data, state)
	_apply(r, m, "grain", float(-ration), "the court's ration")
	# The harvest and the buildings are the lord's own fields and walls.
	if Calendar.season_name(state.tick + 1) == "Autumn":
		_apply(r, m, "lord_civil", float(int(roundf(float(people) / 1000.0 * data.bal("harvest_civil_per_1000")))),
			"the harvest comes in")
	var built := MapManors.crown_building_effects(data, state)
	_apply(r, m, "lord_gold", float(int(built["treasury"])), "tolls and rents of your buildings")
	_apply(r, m, "lord_civil", float(int(built["grain"])), "your mills and granaries")
	# The floor is a line like any other (invariant 4): what could not be
	# eaten is written off with its reason, never cut silently.
	for pool: String in ["grain", "lord_civil"]:
		if m[pool] < 0.0:
			_apply(r, m, pool, -m[pool], "the stores cannot fall below empty")
	if data.bal("economy_check_full") > 0.0:
		var bad := RealmEconomy.check_full(data, state)
		if not bad.is_empty():
			push_error("economy_check_full: %d province(s) differ from the cache: %s" % [bad.size(), str(bad[0])])

## The people of the provinces the crown controls — the mouths the court's
## ration feeds and the harvest is counted by. Also read by the LEDGER.
static func court_people(repo: DataRepository, state: GameState) -> int:
	var people := 0
	for code: String in MapManors.controlled_provinces(repo, state):
		people += RealmEconomy._figure(repo, state, "economy.provinces.%s.rural_population" % code)
		people += RealmEconomy._figure(repo, state, "economy.provinces.%s.urban_population" % code)
	return people

## The province the court sits in, whose grain law rations its table: the
## realm's capital's province while the realm holds it, else the crown's
## home province (MapManors.home_province).
static func court_province(repo: DataRepository, state: GameState) -> String:
	var realm := repo.resolve_realm("player_realm")
	var cap := String((repo.kingdoms.get(realm, {}) as Dictionary).get("capital_burg", ""))
	var code := String((repo.burgs.get(cap, {}) as Dictionary).get("province_code", ""))
	if code != "" and MapOwnership.owner_of(repo, state, code) == realm:
		return code
	return MapManors.home_province(repo, state)

## The court's ration of civil goods this month, halved while the grain law
## in force where the court sits is `ration` (`market` and `release` feed it
## in full; spec 2026-10-08-laws-tab-design §4.3). Whole gold (invariant 11).
static func ration_of(repo: DataRepository, state: GameState) -> int:
	var ration := int(roundf(float(court_people(repo, state)) / 1000.0 * repo.bal("ration_gold_per_1000")))
	if LawSystem.value(repo, state, "grain_ration", court_province(repo, state)) == "ration":
		@warning_ignore("integer_division")  # whole gold (invariant 11)
		ration = ration / 2
	return ration

func _drift(state: GameState, r: TickReport) -> void:
	var m := state.metrics
	var cap := data.bal("admin_base")
	if state.council.has("chancellor"):
		var ch: Character = state.characters[state.council["chancellor"]]
		var capacity_bonus_per_skill: float = float(data.seats["chancellor"]["capacity_bonus_per_skill"])
		cap += ch.skills["sk_admin"] * capacity_bonus_per_skill
	else:
		cap -= data.bal("chancellor_vacancy_penalty")
	_set_metric(r, m, "admin_capacity", cap, "council administration")
	# What the crown's finished buildings do each tick (2026-09-13): a
	# chapel's sermons, a hall's order, its walls (the gold and the goods
	# are settled with the month, in _settle_economy).
	var built := MapManors.crown_building_effects(data, state)
	_apply(r, m, "church_opinion", float(built["church_opinion"]), "the crown's chapels")
	_apply(r, m, "peasant_contentment", float(built["peasant_contentment"]), "lords in residence")
	_apply(r, m, "unrest", float(built["unrest"]), "the crown's walls")
	# the tax in force across the realm, weighted by each province's people
	# (laws, spec 2026-10-08 §4.3), not the decreed mirror
	var taxed := LawSystem.weighted_number(data, state, "tax_rate")
	var unrest_delta: float = (taxed - data.bal("unrest_tax_pivot")) * data.bal("unrest_tax_pressure") - data.bal("unrest_decay")
	if m["grain"] <= 0.0:
		unrest_delta += data.bal("unrest_famine")
	_apply(r, m, "unrest", unrest_delta, "tax pressure and the mood of the villages")
	m["unrest"] = clampf(m["unrest"], 0.0, 100.0)
	_drift_toward(r, m, "peasant_contentment", data.bal("drift_baseline"), data.bal("contentment_drift"), "life goes on")
	_drift_toward(r, m, "legitimacy", data.bal("drift_baseline"), data.bal("legitimacy_drift"), "memory of the crown settles")
	_drift_toward(r, m, "church_opinion", data.bal("drift_baseline"), data.bal("church_drift"), "sermons soften")
	if m["army_quality"] > data.bal("army_floor"):
		_apply(r, m, "army_quality", -data.bal("army_decay"), "drills lapse")

func _apply(r: TickReport, m: Dictionary, metric: String, delta: float, reason: String) -> void:
	if is_zero_approx(delta):
		return
	m[metric] = m[metric] + delta
	r.metric_deltas.append({"metric": metric, "delta": delta, "reason": reason})

func _set_metric(r: TickReport, m: Dictionary, metric: String, value: float, reason: String) -> void:
	var delta: float = value - m[metric]
	m[metric] = value
	if not is_zero_approx(delta):
		r.metric_deltas.append({"metric": metric, "delta": delta, "reason": reason})

func _drift_toward(r: TickReport, m: Dictionary, metric: String, baseline: float, rate: float, reason: String) -> void:
	var delta := clampf(baseline - m[metric], -rate, rate)
	_apply(r, m, metric, delta, reason)
