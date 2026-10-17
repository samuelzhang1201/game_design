class_name BattlePresentation
extends RefCounted
## The view receives copied facts and delivered estimates, never battle truth.

static func snapshot(repo: DataRepository, state: GameState, realm: String) -> Dictionary:
	var out := {"battles": [], "decision": {}, "enemies": [], "reports": []}
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
				var entry: Dictionary = state.regiments[code]
				var commander := String(state.military_rosters.get(code, {}).get("commander_id", ""))
				units.append({"code": code, "label": String(ArmySystem.regiment(repo, code, state).get("label", code)),
					"fit": MilitaryRoster.fit(state, code), "wounded": MilitaryRoster.living(state, code) - MilitaryRoster.fit(state, code),
					"morale": int(entry.get("morale", 0)), "supplies": int(entry.get("supplies", 0)),
					"commander": state.characters[commander].display_name if state.characters.has(commander) else "The field officers"})
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
	for token: String in state.battle_events:
		var record: Dictionary = state.battle_events[token]
		if int(record.get("received_day", -1)) < 0 or String(record.get("selected", "")) == "": continue
		var receipt: Dictionary = record.get("receipt", {})
		out["reports"].append({"token": token, "battle_id": int(record.get("battle_id", -1)),
			"day": int(record.get("day", 0)), "received_day": int(record["received_day"]),
			"text": "%s — %s. %s" % [repo.event_titles.get(String(record.get("event_id", "")), "Battlefield report"), record["selected"], receipt.get("reason", "")]})
	return out

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
