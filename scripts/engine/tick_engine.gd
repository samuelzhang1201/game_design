class_name TickEngine
extends RefCounted

var data: DataRepository
var actions: ActionSystem
var suggestions: SuggestionGenerator
var events: EventSystem
var last_month_report: TickReport

func _init(d: DataRepository) -> void:
	data = d
	actions = ActionSystem.new(d)
	suggestions = SuggestionGenerator.new(d, actions)
	events = EventSystem.new(d)

## One day (owner 2026-09-13: the smallest unit of time): the day now
## running (`state.day`) ENDS, and the next one begins. The thirtieth day's
## end is a tick. This compatibility adapter leaves an unstarted thirtieth
## day for advance(); production Game uses resolve_day for every boundary.
## Returns the works finished today, [{cell, building}], or [] when blocked.
func advance_day(state: GameState) -> Array:
	if state.day >= Calendar.DAYS_PER_TICK and state.day_resolution.is_empty():
		return []
	var out := resolve_day(state)
	return out["journal"]["works"] if out["status"] == "complete" else []


func resolve_decision(state: GameState, token: String, choice: String) -> Dictionary:
	if not state.day_resolution.is_empty():
		var incompatibility := DayResolution.incompatibility_reason(state.day_resolution)
		if not incompatibility.is_empty():
			return {"status": "error", "error": incompatibility}
	var pending: Dictionary = state.day_resolution.get("pending_decision", {})
	if pending.get("kind", "") == "battle_event" and pending.get("token", "") == token:
		var result := BattleEvents.choose(data, state, token, choice)
		if not result.status in ["accepted", "duplicate"]:
			return result
		if not choice in pending["choices"]:
			pending["choices"].append(choice)
	return DayResolution.acknowledge(state.day_resolution, token, choice)


## close_month retains advance()'s one-day-plus-month snapshot contract.
## Once begun, the saved transaction decides whether this day closes a month.
func resolve_day(state: GameState, close_month := false) -> Dictionary:
	if not state.day_resolution.is_empty():
		var incompatibility := DayResolution.incompatibility_reason(state.day_resolution)
		if not incompatibility.is_empty():
			return {"status": "error", "error": incompatibility}
	var custody := PrisonerSystem.migrate_legacy(data, state)
	if custody.has("error"):
		return {"status": "error", "error": custody["error"]}
	custody = PrisonerSystem.settle_unguarded(data, state)
	if custody.has("error"):
		return {"status": "error", "error": custody["error"]}
	if not state.day_resolution.is_empty() and not state.day_resolution.has("protocol_version"):
		return _resolve_legacy_day(state, close_month)
	if state.day_resolution.is_empty():
		var organization := MilitaryReorganization.reconcile(data, state)
		if organization.get("status", "error") == "error":
			return {"status": "error", "error": organization.get("error", "Cannot reconcile military organization.")}
		state.day_resolution = DayResolution.begin(state.day,
			close_month or state.day >= Calendar.DAYS_PER_TICK, state.absolute_day(), int(data.bal("battle_substeps")))
	var tx := state.day_resolution
	var journal: Dictionary = tx["journal"]
	if not journal.has("missive_start"):
		journal["missive_start"] = state.next_missive_id
	last_month_report = null
	_restore_day_outputs(tx)
	while int(tx["phase_cursor"]) < DayResolution.PHASES.size():
		if not (tx.get("pending_decision", {}) as Dictionary).is_empty():
			return {"status": "blocked", "decision": tx["pending_decision"].duplicate(true), "journal": journal.duplicate(true)}
		var cursor := int(tx["phase_cursor"])
		var outcome := _resolve_phase(state, tx, DayResolution.PHASES[cursor])
		_restore_day_outputs(tx)
		if outcome.get("status", "") == "error":
			return outcome
		if bool(outcome.get("blocked", false)) or outcome.get("status", "") == "blocked":
			return {"status": "blocked", "decision": tx["pending_decision"].duplicate(true), "journal": journal.duplicate(true)}
		tx["phase_cursor"] = cursor + 1
		tx["phase"] = DayResolution.PHASES[mini(cursor + 1, DayResolution.PHASES.size() - 1)]
	var out := {"status": "complete", "journal": journal.duplicate(true),
		"ended": int(tx.get("absolute_day", tx["day"])), "ticked": bool(tx["month_end"]) or bool(tx.get("settle_month_compat", false)), "report": last_month_report}
	state.day_resolution = {}
	return out


func _offer_battle_event(state: GameState, tx: Dictionary, id: int) -> Dictionary:
	var offer := BattleEvents.offer(data, state, id)
	if offer.status == "blocked":
		tx["pending_decision"] = offer.decision
		return offer
	if offer.status == "resolved":
		var event: Dictionary = offer.event
		var battle := BattleSystem.battle_by_id(state, id)
		var journal: Dictionary = tx["journal"]
		if not journal["battles"].any(func(prior: Dictionary) -> bool: return prior.get("token", "") == event.token):
			journal["battles"].append({"kind": "battle_event", "battle_id": id,
				"token": event.token, "event_id": event.event_id, "receipt": event.receipt.duplicate(true),
				"unit": event.unit, "att": battle.get("att", []).duplicate(), "def": battle.get("def", []).duplicate(),
				"town": battle.get("town", ""), "place_x_m": battle.get("place_x_m", 0), "place_y_m": battle.get("place_y_m", 0)})
		tx["pending_decision"] = {}
	return offer


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
			ArmySystem.ensure(data, state)
			BattleTaskSystem.track_day(data, state)
			ArmyTasks.step_day(data, state)
			var moving: Array = []
			var budgets: Dictionary = {}
			var march_entries: Dictionary = {}
			for table: Dictionary in [state.regiments, state.foes]:
				var codes: Array = table.keys()
				codes.sort()
				for code_value: Variant in codes:
					var code := String(code_value)
					if BattleSystem.may_withdraw(state, code):
						ArmySystem._resume_departure(data, state, code, table[code])
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
			if int(tx.get("protocol_version", 4)) == 3:
				KingSystem.step_day(data, state)
			CampSystem.finish_day(data, state, state.absolute_day())
			Sighting.update(data, state)
		"SUPPLY_AND_CONDUCT":
			day_supply = SupplyLines.set_out_events(day_couriers)
			day_supply.append_array(SupplyLines.day_step(data, state))
			ArmySystem.eat_day(data, state)
			EnemyAi.eat_day(data, state)
			ArmySystem.hunger_day(data, state)
			day_conduct = ArmyConduct.day_step(data, state)
			RecruitmentSystem.step_day(data, state)
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
			_route_battle_reports(state, fights)
			if not day_supply.is_empty():
				MissiveLog.add(data, state, MissiveWriter.supply_dispatch(data, state, day_supply))
			if not day_conduct.is_empty():
				MissiveLog.add(data, state, MissiveWriter.conduct_dispatch(data, state, day_conduct))
		"MONTH_END_IF_NEEDED":
			if bool(tx.get("month_end", false)) or bool(tx.get("settle_month_compat", false)):
				last_month_report = _settle_month(state)
				last_month_report.finished_works = journal["works"].duplicate(true)
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
			if int(tx.get("protocol_version", 4)) >= 4:
				KingSystem.step_substep(data, state, tx)
			var host_arrivals := EnemyAi.arrival_substep(data, state, tx.get("march_entries", {}))
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
		if int(tx.get("protocol_version", 4)) == 3:
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
			if battle_id in tx.get("substep_battle_ids", []) and not battle_id in tx.get("acknowledged_encounters", []):
				DayResolution.block_on_encounter(tx, battle_id)
				return {"blocked": true}
			var offer := _offer_battle_event(state, tx, battle_id)
			if offer.get("status", "") in ["blocked", "error"]:
				return offer
			var result := BattleSystem.step_battle(data, state, battle_id)
			if result["status"] == "error":
				return result
			if result["status"] == "blocked":
				tx["pending_decision"] = result["decision"]
				return {"blocked": true}
			_append_substep_battle_events(journal, result["events"], int(tx["substep_index"]))
			(tx["processed_battle_ids"] as Array).append(battle_id)
			tx["battle_index"] = index + 1
		if not (tx["over_battle_ids"] as Array).is_empty():
			state.battles = state.battles.filter(func(b: Dictionary) -> bool:
				return not int(b["id"]) in (tx["over_battle_ids"] as Array))
		tx["battle_ids"] = []
		tx["battle_index"] = 0
		tx["battle_step"] = ""
		tx["substep_battle_ids"] = []
		tx["substep_index"] = int(tx["substep_index"]) + 1
	BattleSystem.finish_day(data, state)
	return {"blocked": false}


func _append_substep_battle_events(journal: Dictionary, events: Array, substep_index: int) -> void:
	for event: Dictionary in events:
		var recorded := event.duplicate(true)
		recorded["substep_index"] = substep_index
		(journal["battles"] as Array).append(recorded)


func _resolve_legacy_day(state: GameState, close_month := false) -> Dictionary:
	var tx := state.day_resolution
	var journal: Dictionary = tx["journal"]
	if not journal.has("missive_start"):
		journal["missive_start"] = state.next_missive_id
	if tx["phase"] == "prepare":
		journal["works"] = _before_battles(state, journal)
		_capture_day(journal)
		journal["battles"] = BattleSystem.prepare_day(data, state)
		tx["battle_ids"] = state.battles.map(func(b: Dictionary) -> int: return int(b["id"]))
		tx["battle_ids"].sort()
		tx["phase"] = "encounters"
	if tx["phase"] == "encounters":
		for event: Dictionary in journal["battles"]:
			if event["kind"] != "start":
				continue
			var token := "%d:encounter:%d" % [int(tx["day"]), int(event["battle_id"])]
			if token in tx["consumed_tokens"]:
				continue
			tx["pending_decision"] = {"token": token, "kind": "encounter",
				"battle_id": int(event["battle_id"]), "choices": ["continue"], "selected": ""}
			return {"status": "blocked", "decision": tx["pending_decision"].duplicate(true)}
		tx["pending_decision"] = {}
		tx["phase"] = "battles"
	if tx["phase"] == "battles":
		while int(tx["battle_index"]) < tx["battle_ids"].size():
			var id := int(tx["battle_ids"][int(tx["battle_index"])])
			var offer := BattleEvents.offer(data, state, id)
			if offer.status == "blocked":
				tx["pending_decision"] = offer.decision
				return {"status": "blocked", "decision": offer.decision.duplicate(true)}
			if offer.status == "resolved":
				var event: Dictionary = offer.event
				var battle := BattleSystem.battle_by_id(state, id)
				if not journal["battles"].any(func(prior: Dictionary) -> bool: return prior.get("token", "") == event.token):
					journal["battles"].append({"kind": "battle_event", "battle_id": id,
						"token": event.token, "event_id": event.event_id, "receipt": event.receipt.duplicate(true),
						"unit": event.unit, "att": battle.get("att", []).duplicate(), "def": battle.get("def", []).duplicate(),
						"town": battle.get("town", ""), "place_x_m": battle.get("place_x_m", 0), "place_y_m": battle.get("place_y_m", 0)})
				tx["pending_decision"] = {}
			var step := BattleSystem.step_battle(data, state, id)
			if step["status"] == "error":
				return {"status": "error", "error": step["error"], "battle_id": id}
			if step["status"] == "blocked":
				tx["pending_decision"] = step["decision"]
				return {"status": "blocked", "decision": step["decision"].duplicate(true)}
			journal["battles"].append_array(step["events"])
			tx["battle_index"] = int(tx["battle_index"]) + 1
		BattleSystem.finish_day(data, state)
		tx["phase"] = "finish"
	_restore_day(journal)
	_after_battles(state)
	_capture_day(journal)
	var report: TickReport = null
	if bool(tx["month_end"]):
		report = _settle_month(state)
		report.finished_works = journal["works"].duplicate(true)
	else:
		state.day += 1
	var out := {"status": "complete", "journal": journal.duplicate(true),
		"ended": int(tx["day"]), "ticked": bool(tx["month_end"]), "report": report}
	state.day_resolution = {}
	return out


func _capture_day(journal: Dictionary) -> void:
	journal["arrivals"] = day_arrivals.duplicate(true)
	journal["couriers"] = day_couriers.duplicate(true)
	journal["supply"] = day_supply.duplicate(true)
	journal["conduct"] = day_conduct.duplicate(true)
	journal["ai"] = day_ai.duplicate(true)
	journal["sieges"] = day_siege.duplicate(true)
	journal["raids"] = day_raid.duplicate(true)


func _restore_day(journal: Dictionary) -> void:
	day_arrivals = journal["arrivals"].duplicate(true)
	day_couriers = journal["couriers"].duplicate(true)
	day_battles = journal["battles"].duplicate(true)
	day_supply = journal["supply"].duplicate(true)
	day_conduct = journal["conduct"].duplicate(true)
	day_ai = journal.get("ai", []).duplicate(true)
	if not journal.has("ai"):
		for record: Dictionary in journal.get("reports", []):
			if String(record.get("kind", "")) == "host_events":
				day_ai.append_array(record.get("events", []))
	day_siege = journal["sieges"].duplicate(true)
	day_raid = journal["raids"].duplicate(true)


## The day `state.day` ends (owner 2026-10-06: 顶栏日期滞后一天 — the date shown
## is the day being played, and all of it happens as that day ends): works
## step, the columns march, the couriers ride, the host eats. Returns the
## works finished.
func _before_battles(state: GameState, journal: Dictionary) -> Array:
	day_supply = []
	day_conduct = []
	day_siege = []
	day_raid = []
	var done := MapManors.advance_works(data, state)
	# A day on the road for every regiment under a march order (owner
	# 2026-09-22). The arrivals go on day_arrivals rather than into the
	# return value, which is the finished WORKS and is asserted as such by
	# tests/engine/test_tick_engine.gd.
	day_arrivals = ArmySystem.march_day(data, state)
	# A seat whose town has fallen is cleared (spec 2026-10-07-army-split-
	# and-ground §4.4).
	ArmyGround.reconcile(data, state)
	# Following reads the column's actual endpoint after its march and settlement.
	if not journal.has("king_advanced"):
		KingSystem.step_day(data, state)
		journal["king_advanced"] = true
		journal["king_state"] = state.king_state.duplicate(true)
	if state.king_state.is_empty() and journal.has("king_state"):
		state.king_state = journal["king_state"].duplicate(true)
	# A province or a camp the realm lost, or a camp left empty, forgets its
	# laws (laws spec §2.4, R13).
	LawSystem.reconcile(data, state)
	# The couriers ride AFTER the columns march (owner 2026-10-02: a one-day
	# courier arrives as the day ENDS): he reaches the column where its day
	# left it, and the order he delivers is marched on from tomorrow.
	day_couriers = CourierSystem.ride_day(data, state)
	# The raider realm's hosts (spec 2026-10-07-enemy-ai-and-battle §2-3), ONCE
	# a day: after the march and the couriers, so a host reads the places and
	# the garrisons the day's battles will read; BEFORE the battles, so a column
	# that marched into a garrisoned town's reach today has put its host in
	# SIEGE before the contacts are taken. step_day (the meal, retreat, arrival,
	# the columns sent on) then think_day the same day, so a host that set out
	# or stood aside today chooses before its columns march tomorrow.
	day_ai = EnemyAi.step_day(data, state)
	day_ai.append_array(EnemyAi.think_day(data, state))
	for m: Dictionary in EnemyAi.warnings(data, state):
		MissiveLog.add(data, state, m)
	var news := MissiveWriter.host_news(data, state, day_ai)
	if not news.is_empty():
		MissiveLog.add(data, state, news)
	# The scouts' and contact letters (spec 2026-10-14-unit-clearance-and-scouting-
	# design §c), once a day after the hosts have moved and before the battles: a
	# foe at hand of a column of ours is told BEFORE the battle letter that its
	# contact may start.
	Sighting.scout_day(data, state)
	return done


func _after_battles(state: GameState) -> void:
	# The sieges' day (spec §5.1-5.2) right AFTER the battles, once: an
	# assault is that day's town battle, and its outcome moves the siege. The
	# siege's news rides in the same battle letter, after the fighting.
	day_siege = SiegeSystem.settle_day(data, state, day_battles)
	# The raids' day (spec §5.3) right after the sieges, once: a host the day's
	# battles beat pays its spoils, a raiding host takes its day (a siege whose
	# garrison left has just turned its host RAID), one that stripped its manor
	# sets out again. Its own events (TickEngine.day_raid); its news rides in
	# the same battle letter, after the siege's.
	day_raid = RaidSystem.settle_day(data, state, day_battles)
	# A line held another day (spec 2026-10-11-war-room-front-line-design §3),
	# read after the stances have settled.
	CampSystem.finish_day(data, state, state.absolute_day())
	# the sieges' and the raids' mode changes (EnemyAi.set_mode's host_mode
	# events) join the day's record of the hosts; their news is the battle letter's
	day_ai.append_array(day_siege.filter(func(e: Dictionary) -> bool: return e.has("type")))
	day_ai.append_array(day_raid.filter(func(e: Dictionary) -> bool: return e.has("type")))
	var fights: Array = day_battles + SiegeSystem.news(day_siege) + RaidSystem.news(day_raid)
	_route_battle_reports(state, fights)
	# The crown's sight (spec 2026-10-10-player-sight-and-ghosts), once a day
	# when every column has marched and fought: the rumour's host ghost on its
	# day, each foe the crown sees refreshed where it stands, the stale and
	# the destroyed forgotten.
	Sighting.update(data, state)
	# The supply lines' day (spec 2026-10-07-army-supply-lines §3.2): the towns
	# refill their garrisons, the wagons roll, before the host eats.
	# a supply warrant a courier delivered today sets its wagons out: said first
	day_supply = SupplyLines.set_out_events(day_couriers)
	day_supply.append_array(SupplyLines.day_step(data, state))
	# The host eats a day of its month (owner 2026-09-30).
	ArmySystem.eat_day(data, state)
	EnemyAi.eat_day(data, state)
	# A hungry host loses heart every day (spec 2026-10-07-army-supply-lines §3.7).
	ArmySystem.hunger_day(data, state)
	# Living off the land and desertion (spec 2026-10-10-foraging-and-desertion
	# §3.3): after the meal, so the warnings below read what foraging left.
	day_conduct = ArmyConduct.day_step(data, state)
	# Assembly completes at the day-end; the new unit first acts tomorrow.
	RecruitmentSystem.step_day(data, state)
	# The day's supply warnings, read off what the host has left after eating.
	day_supply.append_array(SupplyLines.warn_day(data, state))
	# The month's economy is computed a bucket a day (spec §11.2).
	RealmEconomy.step_day(data, state)
	# The day's supply news goes out as ONE letter, when there is any (spec
	# 2026-10-07-army-supply-lines §5.5): day_supply holds all of the day now.
	if not day_supply.is_empty():
		MissiveLog.add(data, state, MissiveWriter.supply_dispatch(data, state, day_supply))
	if not day_conduct.is_empty():
		MissiveLog.add(data, state, MissiveWriter.conduct_dispatch(data, state, day_conduct))

## Each battlefield has its own immutable report and physical courier.
func _route_battle_reports(state: GameState, fights: Array) -> void:
	var grouped: Dictionary = {}
	var other: Array = []
	for fight: Dictionary in fights:
		var id := int(fight.get("battle_id", -1))
		if id < 0:
			other.append(fight)
			continue
		if not grouped.has(id):
			grouped[id] = []
		grouped[id].append(fight)
	var ids := grouped.keys()
	ids.sort()
	for id: int in ids:
		var events: Array = grouped[id]
		var place: Dictionary = {}
		for event: Dictionary in events:
			if event.has("place_x_m"):
				place = event.duplicate(true)
				break
		var report := MissiveWriter.king_report_payload(data, state, events)
		report["battle_id"] = id
		report["day"] = state.absolute_day()
		report["event_tokens"] = []
		for event: Dictionary in events:
			if event.kind == "battle_event":
				report.event_tokens.append(event.token)
		var at := Vector2i(int(place.get("place_x_m", 0)), int(place.get("place_y_m", 0)))
		var local := BattleSystem._within(KingSystem.position(state), at, int(data.bal("king_command_radius_m")))
		if local:
			MissiveLog.add(data, state, MissiveLog.battle_payload(MissiveWriter.battle_report(data, state, events), report))
			BattleEvents.receive_report(state, report)
		else:
			place["report"] = report
			var courier := CourierSystem.dispatch_king_report(data, state, id, place)
			if not courier.is_empty():
				state.king_state["last_report_dispatched"] = {"courier_id": int(courier.id), "battle_id": id,
					"day": state.absolute_day(), "fee_gold": 0}
	if not other.is_empty():
		MissiveLog.add(data, state, MissiveWriter.battle_report(data, state, other))


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
	if state.tick == 0 and state.day_resolution.is_empty():
		_restore_day(DayResolution.begin(state.absolute_day(), false)["journal"])
		return _settle_month(state)
	var out := resolve_day(state, true)
	return out["report"] if out["status"] == "complete" else null


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
