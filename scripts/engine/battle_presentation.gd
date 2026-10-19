class_name BattlePresentation
extends RefCounted
## The view receives copied facts and delivered estimates, never battle truth.

static func snapshot(repo: DataRepository, state: GameState, realm: String) -> Dictionary:
	var out := {"battles": [], "decision": {}, "enemies": [], "reports": [], "detailed_reports": [], "prisoners": {}}
	if state == null or realm != repo.resolve_realm("player_realm"):
		return out
	for battle: Dictionary in state.battles:
		var units: Array = []
		var side := ""
		for candidate: String in BattleSystem.SIDES:
			for code: String in battle.get(candidate, []):
				if not state.regiments.has(code) or ArmySystem.realm_of(repo, code, state) != realm:
					continue
				side = candidate
				var reading := known_unit(repo, state, code)
				var commander := String(state.military_rosters.get(code, {}).get("commander_id", ""))
				var unit := {"code": code, "label": String(ArmySystem.regiment(repo, code, state).get("label", code)),
					"known": not reading.is_empty(),
					"commander": state.characters[commander].display_name if state.characters.has(commander) else "The field officers"}
				if not reading.is_empty():
					for key: String in ["fit", "wounded", "morale", "supplies"]: unit[key] = int(reading[key])
					unit["observed_day"] = int(reading.day)
				units.append(unit)
		if units.is_empty():
			continue
		var id := int(battle["id"])
		out["battles"].append({"id": id, "place": BattleSystem.place_label(repo, state, battle),
			"units": units, "action": BattleOrders.kind(battle, side),
			"formation": String(battle.get("formations", {}).get(side, {}).get("current", "line")),
			"agreements": BattleRules.summary(repo, battle), "king_present": KingSystem.present(repo, state, id),
			"orders": order_options(repo, state, battle, side, String(units[0]["code"])),
			"warrants": warrants(state, id), "formation_view": formation_view(repo, state, battle, side)})
	var keys := state.sightings.keys()
	keys.sort()
	for key: String in keys:
		var sight: Dictionary = state.sightings[key]
		out["enemies"].append({"code": String(sight.get("code", key)), "kind": String(sight.get("kind", "unit")),
			"x_m": int(sight.get("x_m", 0)), "y_m": int(sight.get("y_m", 0)),
			"estimate": int(sight.get("men", 0)), "source": String(sight.get("source", "unknown")),
			"observed_day": int(sight.get("day", 0))})
	var pending: Dictionary = state.day_resolution.get("pending_decision", {})
	if not pending.is_empty() and String(pending.get("selected", "")) == "":
		out["decision"] = decision(repo, state, pending)
	for report: Dictionary in state.king_state.get("battle_reports", []):
		var lines: PackedStringArray = [String(report.get("title", "Battlefield report"))]
		for fact: Dictionary in report.get("facts", []):
			lines.append(String(fact.get("text", "")))
		out["reports"].append({"battle_id": int(report.get("battle_id", -1)),
			"day": int(report.get("day", 0)), "received_day": int(report.get("received_day", 0)),
			"text": "\n".join(lines)})
	out.detailed_reports = detailed_reports(state, realm)
	out["prisoners"] = prisoner_view(repo, state, realm)
	for token: String in state.battle_events:
		var record: Dictionary = state.battle_events[token]
		if int(record.get("received_day", -1)) < 0 or String(record.get("selected", "")) == "": continue
		var receipt: Dictionary = record.get("receipt", {})
		out["reports"].append({"token": token, "battle_id": int(record.get("battle_id", -1)),
			"day": int(record.get("day", 0)), "received_day": int(record["received_day"]),
			"text": "%s — %s. %s" % [repo.event_titles.get(String(record.get("event_id", "")), "Battlefield report"), record["selected"], receipt.get("reason", "")]})
	return out

## Frozen battle totals and subsequent received transactions have separate histories.
static func detailed_reports(state: GameState, realm: String) -> Array:
	var reports := {}
	var batch_battles := {}
	var received: Array = state.king_state.get("battle_reports", [])
	for report: Dictionary in received:
		var detail: Dictionary = report.get("details", {})
		if not detail.is_empty() and not reports.has(int(detail.battle_id)):
			var copy := detail.duplicate(true)
			copy["received_day"] = int(report.get("received_day", 0))
			copy["settlements"] = []
			reports[int(detail.battle_id)] = copy
		for batch: Dictionary in detail.get("prisoners", []):
			batch_battles[String(batch.id)] = int(detail.battle_id)
		for batch: Dictionary in report.get("custody", []):
			batch_battles[String(batch.id)] = int(batch.battle_id)
	for report: Dictionary in received:
		for settlement: Dictionary in report.get("settlements", []):
			var id := int(settlement.get("battle_id", report.get("battle_id", -1)))
			if reports.has(id) and not settlement in reports[id].settlements:
				reports[id].settlements.append(settlement.duplicate(true))
	for proposal: Dictionary in state.prisoner_proposals.values():
		var visible := PrisonerCommunications.projection(state, String(proposal.request.id))
		if visible.get("status", "") != "fulfilled" or not realm in proposal.get("frozen", {}).get("required_parties", []): continue
		var result: Dictionary = visible.get("result", {})
		var by_battle := {}
		for civilian: Dictionary in result.get("civilians", []):
			var id := int(batch_battles.get(String(civilian.batch_id), -1))
			if not reports.has(id): continue
			if not by_battle.has(id): by_battle[id] = []
			by_battle[id].append(civilian.duplicate(true))
		for id: int in by_battle:
			var settlement := result.duplicate(true)
			settlement["battle_id"] = id
			settlement["kind"] = proposal.get("request", {}).get("kind", "Settlement")
			settlement["civilians"] = by_battle[id]
			settlement["released"] = 0
			for civilian: Dictionary in by_battle[id]: settlement.released += int(civilian.count)
			var duplicate := false
			for existing: Dictionary in reports[id].settlements:
				if existing.get("id", "") == result.get("id", "") and result.has("id"): duplicate = true
			if not duplicate: reports[id].settlements.append(settlement)
	return reports.values()

static func formation_view(repo: DataRepository, state: GameState, battle: Dictionary, side: String) -> Dictionary:
	# Suitability hints use our terrain and centre; unseen enemy positions cannot colour them.
	var own := battle.duplicate(true)
	own["def" if side == "att" else "att"] = []
	return BattleRules.encounter_view(repo, state, own)

static func decision(repo: DataRepository, state: GameState, pending: Dictionary) -> Dictionary:
	var out := {"token": String(pending.get("token", "")), "kind": String(pending.get("kind", "")),
		"battle_id": int(pending.get("battle_id", -1)), "selected": String(pending.get("selected", ""))}
	if out["kind"] == "encounter":
		out["choices"] = ["continue"]
	elif out["kind"] == "battle_event":
		var record: Dictionary = state.battle_events.get(out["token"], {})
		var id := String(record.get("event_id", ""))
		out["event_id"] = id
		out["title"] = String(repo.event_titles.get(id, "Battlefield decision"))
		out["scene"] = String(repo.event_scenes.get(id, ""))
		out["art_key"] = String(repo.battle_events.get(id, {}).get("art_key", ""))
		out["options"] = BattleEvents.choices_for(repo, state, record)
	return out

static func warrants(state: GameState, id: int) -> Array:
	var out: Array = []
	for token: String in state.battle_orders:
		var row: Dictionary = state.battle_orders[token]
		if int(row.get("request", {}).get("battle_id", -1)) != id:
			continue
		out.append({"id": token, "kind": String(row["request"].get("kind", "")),
			"status": String(row.get("status", "")), "reserved_gold": int(row.get("reserved_gold", 0)),
			"reason": String(row.get("reason", ""))})
	return out

static func order_options(repo: DataRepository, state: GameState, battle: Dictionary, side: String, code: String) -> Array:
	var out: Array = []
	var actions := ActionSystem.new(repo)
	for kind: String in repo.battle_orders:
		var row: Dictionary = repo.battle_orders[kind]
		var params := {"regiment": code, "battle_id": int(battle["id"]), "kind": kind,
			"request_id": "preview:%d:%s" % [int(battle["id"]), kind]}
		var req := ActionRequest.make("BATTLE_ORDER", params)
		var quote := BattleOrders.preview(repo, state, actions._battle_warrant(req, state))
		var fee := actions._fee_for(state, code)
		var reserve := int(quote["reserved_gold"])
		var filing := int(OrderCosts.gold_of(repo, "BATTLE_ORDER")) if fee == 0 and reserve == 0 and kind != "surrender" else 0
		var cooldown := maxi(0, int(battle.get("inspire_cooldown", {}).get(side, 0)) - state.absolute_day()) if kind == "inspire" else 0
		out.append({"id": kind, "label": String(row["label"]), "regiment": code,
			"reason": actions.validate(req, state), "courier_gold": fee, "filing_gold": filing,
			"reserved_gold": reserve, "cooldown_days": cooldown,
			"effects_text": effect_text(kind, row), "local": KingSystem.can_command(repo, state, code)})
	return out

## One crown unit's task choices and ledger status on its battlefield; empty off any.
## Opponents are named only (seen in contact); their strength stays with intel.
static func task_view(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	if state == null or not state.regiments.has(code) or ArmySystem.is_foe(state, code) \
			or ArmySystem.realm_of(repo, code, state) != repo.resolve_realm("player_realm"):
		return {}
	for battle: Dictionary in state.battles:
		var side := BattleRules.side_of(battle, code)
		if side == "":
			continue
		var out := {"battle_id": int(battle["id"]), "place": BattleSystem.place_label(repo, state, battle),
			"tasks": [], "targets": [], "formations": [], "current": {}, "pending": [], "refused": {}}
		for task: String in repo.battle_behaviors:
			out.tasks.append({"id": task, "label": String(repo.battle_behaviors[task]["label"])})
		for enemy: String in battle["def" if side == "att" else "att"]:
			if BattleSystem._can_fight(repo, state, enemy) and not bool(BattleSystem._stored(state, enemy).get("captured", false)):
				out.targets.append({"code": enemy, "label": String(ArmySystem.regiment(repo, enemy, state).get("label", enemy))})
		for shape: String in repo.battle_formations:
			out.formations.append({"id": shape, "label": String(repo.battle_formations[shape]["label"])})
		var ledger: Dictionary = state.unit_tasks.get(code, {})
		var newest := -1
		for id: String in ledger.get("orders", {}):
			var record: Dictionary = ledger["orders"][id]
			if int(record["request"]["battle_id"]) != int(battle["id"]):
				continue
			var row := _task_row(repo, state, record)
			if id == String(ledger.get("current_id", "")):
				out.current = row
			elif record["status"] == "pending":
				out.pending.append(row)
			elif record["status"] in ["invalid", "superseded"] and int(record["sequence"]) > newest:
				newest = int(record["sequence"])
				out.refused = row
		out.pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.sequence < b.sequence)
		return out
	return {}

static func _task_row(repo: DataRepository, state: GameState, record: Dictionary) -> Dictionary:
	var request: Dictionary = record["request"]
	var task := String(request["task"])
	var target := String(request["target_unit"])
	return {"id": String(request["id"]), "sequence": int(record["sequence"]), "status": String(record["status"]),
		"reason": String(record.get("reason", "")),
		"task": "Cancel task" if task == "cancel" else String(repo.battle_behaviors.get(task, {}).get("label", task)),
		"target": "" if target == "" else String(ArmySystem.regiment(repo, target, state).get("label", target)),
		"formation": String(repo.battle_formations.get(String(request["formation"]), {}).get("label", ""))}

## The exact request a choice would send and what ActionSystem says of it now:
## the refusal, the filing gold, the courier fee (none when local or joining a
## waiting courier) and whether it is delivered here. Task "cancel" cancels.
static func task_quote(repo: DataRepository, state: GameState, code: String, task: String,
		target := "", formation := "") -> Dictionary:
	var view := task_view(repo, state, code)
	if view.is_empty():
		return {"reason": "The unit is not on a battlefield.", "params": {}, "action_code": ""}
	var id := int(view["battle_id"])
	var params := {"request_id": "task-ui:%d:%s:%d" % [id, code, int(state.unit_tasks.get(code, {}).get("issued_sequence", 0)) + 1],
		"regiment": code, "battle_id": id}
	var action := "BATTLE_TASK_CANCEL" if task == "cancel" else "BATTLE_TASK"
	if action == "BATTLE_TASK":
		params.merge({"task": task, "target_unit": target, "formation": formation})
	var actions := ActionSystem.new(repo)
	return {"action_code": action, "params": params,
		"reason": actions.validate(ActionRequest.make(action, params), state),
		"filing_gold": int(OrderCosts.gold_of(repo, action)), "courier_gold": actions._fee_for(state, code),
		"local": KingSystem.can_command(repo, state, code)}

static func effect_text(kind: String, row: Dictionary) -> String:
	match kind:
		"attack": return "Attack %d‰; defence %d‰; extra carried supplies %d‰ each attack day. Commits available reserves." % [int(row["attack_permille"]), int(row["defence_permille"]), int(row["extra_supply_permille"])]
		"hold": return "Defence %d‰. Holds the line, consumes normal supplies and gives up pursuit." % int(row["defence_permille"])
		"inspire": return "+%d morale, +%d more with the king present; %d days of resistance, %d days cooldown. The reserved reward is paid on arrival." % [int(row["morale_gain"]), int(row["king_morale_bonus"]), int(row["inspire_duration_days"]), int(row["cooldown_days"])]
		"retreat": return "Withdraw along a real route, yielding ground and losing morale and stores. Camp departure and lawful pursuit still apply."
		"surrender": return "If accepted, surrender all surviving troops and their equipment. Rejection preserves the current action."
	return ""

static func map_snapshot(repo: DataRepository, state: GameState, realm: String) -> Dictionary:
	var out := {"map_units": {}, "battle_signals": []}
	if state == null or realm != repo.resolve_realm("player_realm"): return out
	for battle: Dictionary in state.battles:
		for side: String in BattleSystem.SIDES:
			var own: Array[String] = []
			for code: String in battle.get(side, []):
				if state.regiments.has(code) and ArmySystem.realm_of(repo, code, state) == realm:
					own.append(code)
			if own.is_empty(): continue
			var action := BattleOrders.kind(battle, side)
			for code: String in own:
				var clip := "GARRISON"
				if int(battle.get("rounds", 0)) > 0:
					clip = "ATTACK" if action == "attack" else "DEFEND"
				out["map_units"][code] = {"action": clip}
			var id := int(battle["id"])
			if "red_flag" in BattleRules.legal_actions(repo, state, id, side):
				out["battle_signals"].append({"key": "%d:%s:refusal" % [id, side], "kind": "refusal", "unit_code": own[0]})
			if int(battle.get("rounds", 0)) == 0 and BattleRules._policy(battle, "herald_safety", state.absolute_day()) == "protect":
				out["battle_signals"].append({"key": "%d:%s:herald" % [id, side], "kind": "herald", "unit_code": own[0]})
	return out

static func local_unit(repo: DataRepository, state: GameState, code: String) -> bool:
	var unit := ArmySystem.state_of(repo, state, code)
	return not unit.is_empty() and BattleSystem._within(KingSystem.position(state),
		Vector2i(int(unit.get("x_m", 0)), int(unit.get("y_m", 0))), int(repo.bal("king_command_radius_m")))

## Copied observations travel with a report. Reading an own holder is not delivery.
static func custody_observations(repo: DataRepository, state: GameState, realm: String, battle_id := -1) -> Array:
	var out: Array = []
	var batches: Array = state.prisoner_batches.values()
	var observed_day := state.absolute_day()
	if battle_id >= 0:
		var record: Dictionary = state.battle_records.get(str(battle_id), {})
		batches = record.custody if record.has("custody") else BattleReport.custody_batches(repo, state, battle_id)
		if record.has("custody"): observed_day = int(record.end_day)
	batches = batches.duplicate()
	batches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))
	for batch: Dictionary in batches:
		var id := String(batch.id)
		var holder := String(batch.get("holder_code", ""))
		var holder_realm := ArmySystem.realm_of(repo, holder, state) if holder != "" else ""
		if holder_realm != realm and batch.get("origin_realm", "") != realm and not realm in batch.get("previous_holder_realms", []) and not local_unit(repo, state, holder): continue
		var named: Array = []
		for person: String in batch.get("named_ids", []):
			var character: Character = state.characters.get(person) as Character
			if person == "you" or (character != null and character.category == "player"): continue
			named.append({"id": person, "name": character.display_name if character != null else person})
		out.append({"id": id, "holder_code": holder, "holder_label": String(ArmySystem.regiment(repo, holder, state).get("label", holder)) if holder != "" else "Released to civilian life",
			"holder_realm": holder_realm, "holder_realm_label": repo.realm_label(holder_realm) if holder_realm != "" else "",
			"captor_code": PrisonerSystem.captor_of(batch), "origin_realm": batch.get("origin_realm", ""),
			"origin_label": repo.realm_label(String(batch.get("origin_realm", ""))),
			"count": int(batch.commoners) + int(batch.nobles) if batch.get("disposition", "") == "held" else 0,
			"commoners": int(batch.commoners), "nobles": int(batch.nobles), "wounded_count": int(batch.wounded_subset),
			"named": named, "battle_id": int(batch.get("battle_id", -1)), "historical_count": int(batch.get("initial_count", int(batch.commoners) + int(batch.nobles))),
			"released_count": int(batch.get("released_count", 0)), "observed_day": observed_day, "current_verified": false, "reason": batch.get("reason", "")})
	return out

static func prisoner_view(repo: DataRepository, state: GameState, realm: String) -> Dictionary:
	var known := {}
	for report: Dictionary in state.king_state.get("battle_reports", []):
		for row: Dictionary in report.get("custody", []):
			if not known.has(row.id) or int(row.observed_day) > int(known[row.id].observed_day): known[row.id] = row.duplicate(true)
	# Only a local fulfillment or a received receipt updates remote custody.
	for proposal: Dictionary in state.prisoner_proposals.values():
		var visible := PrisonerCommunications.projection(state, String(proposal.request.id))
		if visible.get("status", "") != "fulfilled" or not realm in proposal.get("frozen", {}).get("required_parties", []): continue
		for civilian: Dictionary in visible.get("result", {}).get("civilians", []):
			var id := String(civilian.batch_id)
			if not known.has(id): continue
			var newly_released := maxi(0, int(civilian.get("released_total", 0)) - int(known[id].get("released_count", 0)))
			if newly_released == 0: continue
			known[id].count = int(civilian.get("remaining_count", maxi(0, int(known[id].count) - newly_released)))
			known[id].released_count = int(civilian.released_total)
			known[id].wounded_count = int(civilian.get("remaining_wounded", maxi(0, int(known[id].wounded_count) - int(civilian.wounded_count))))
			for person: String in civilian.get("named_ids", []):
				known[id].named = known[id].named.filter(func(row: Dictionary) -> bool: return row.id != person)
	for row: Dictionary in custody_observations(repo, state, realm):
		var observing := String(row.holder_code) if String(row.holder_code) != "" else String(row.captor_code)
		if not local_unit(repo, state, observing): continue
		row.current_verified = true
		known[row.id] = row
	var batches: Array = []
	var current := 0
	var historical := 0
	var ids := known.keys()
	ids.sort()
	for id: String in ids:
		var row: Dictionary = known[id]
		current += int(row.count)
		historical += int(row.historical_count)
		if int(row.count) > 0: batches.append(row)
	var proposals: Array = []
	for id: String in state.prisoner_proposals:
		var row: Dictionary = state.prisoner_proposals[id]
		if not realm in row.get("frozen", {}).get("required_parties", []): continue
		var visible := PrisonerCommunications.projection(state, id)
		for payment: Dictionary in visible.result.get("payments", []):
			payment["holder_label"] = String(ArmySystem.regiment(repo, String(payment.get("holder_code", "")), state).get("label", "The holding regiment"))
		proposals.append({"id": id, "kind": row.request.kind, "status": visible.status, "reason": visible.reason, "request": row.request.duplicate(true),
			"required_parties": row.frozen.required_parties.duplicate(), "consents": visible.consents,
			"result": visible.result, "valuation": row.get("proposal_result", {}).get("valuation", {}).duplicate(true)})
	var next := state.prisoner_proposals.size() + 1
	while state.prisoner_proposals.has("prisoner-ui:%d" % next): next += 1
	var realm_labels := {}
	for code: String in repo.kingdoms: realm_labels[code] = repo.realm_label(code)
	return {"batches": batches, "proposals": proposals, "current_count": current, "historical_captured": historical, "realm_labels": realm_labels,
		"player_realm": realm, "next_proposal_id": "prisoner-ui:%d" % next}

## Shared by the old army card and the new panel: remote live losses are private.
static func awaits_report(repo: DataRepository, state: GameState, code: String) -> bool:
	if state == null or local_unit(repo, state, code): return false
	for battle: Dictionary in state.battles:
		for side: String in BattleSystem.SIDES:
			if code in battle.get(side, []): return true
	for record: Dictionary in state.battle_records.values():
		var involved := false
		for row: Dictionary in record.get("participants", []):
			if row.code == code: involved = true
		if not involved: continue
		var received := false
		for report: Dictionary in state.king_state.get("battle_reports", []):
			if int(report.get("details", {}).get("battle_id", -1)) == int(record.battle_id): received = true
		if not received: return true
	return false

static func known_unit(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var entry := ArmySystem.state_of(repo, state, code)
	if not awaits_report(repo, state, code):
		return {"fit": MilitaryRoster.fit(state, code), "wounded": MilitaryRoster.living(state, code) - MilitaryRoster.fit(state, code),
			"morale": int(entry.get("morale", 0)), "supplies": int(entry.get("supplies", 0)), "day": state.absolute_day()}
	var known := {}
	for report: Dictionary in state.king_state.get("battle_reports", []):
		var reading: Dictionary = report.get("unit_readings", {}).get(code, {})
		if not reading.is_empty() and int(reading.day) > int(known.get("day", -1)): known = reading.duplicate(true)
	return known
