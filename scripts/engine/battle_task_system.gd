class_name BattleTaskSystem
extends RefCounted

## Internal warrants: ActionSystem/couriers own dispatch, costs and actual arrival.
## A receipt never moves a unit or starts a second simulation clock.
static func current(state: GameState, unit: String) -> Dictionary:
	var ledger: Dictionary = state.unit_tasks.get(unit, {})
	return ledger.get("orders", {}).get(String(ledger.get("current_id", "")), {}).duplicate(true)


## Resolve received tasks through existing combat and withdrawal effects.
static func combat_action(repo: DataRepository, state: GameState, battle: Dictionary, unit: String) -> Dictionary:
	var side := BattleRules.side_of(battle, unit)
	var fallback := BattleOrders.kind(battle, side)
	var result := {"kind": fallback, "reason": "Existing delivered side action: " + fallback, "task_id": ""}
	if side == "":
		return result
	if fallback == "retreat" or String(battle.get("routed_side", "")) == side \
			or bool(BattleSystem._stored(state, unit).get("battle_retreat", false)):
		result["kind"] = "retreat"
		result["reason"] = "Actual withdrawal or rout takes precedence over a unit task"
		return result
	var record := current(state, unit)
	if record.is_empty():
		return result
	var request: Dictionary = record["request"]
	if request["task"] == "flank" and request["target_unit"] != "" and record["status"] in ["received", "search_failed", "completed"]:
		var paused: bool = record["status"] != "received" or not _interceptors(repo, state, battle, unit, record).is_empty() \
			or BattleSystem.canonical(state, int(request["battle_id"])) != int(battle["id"])
		if paused:
			return {"kind": "hold", "task_id": String(request["id"]),
				"reason": "Flank holds in temporary self-defence; original target retained" if record["status"] == "received" else String(record["reason"])}
	if not record.get("status") in ["received", "bounded"]:
		return result
	if BattleSystem.canonical(state, int(request["battle_id"])) != int(battle["id"]):
		return result
	if record["status"] == "bounded":
		return {"kind": "hold", "task_id": String(request["id"]), "reason": "Pursuit bound reached: " + String(record["reason"])}
	var action := String(repo.battle_behaviors.get(request["task"], {}).get("legal_action", ""))
	if not action in ["attack", "charge", "hold", "retreat", "pursue"]:
		return result
	result = {"kind": "hold", "task_id": String(request["id"]), "reason": "Received unit task: " + String(request["task"])}
	var target := String(request["target_unit"])
	var legal := BattleRules.legal_actions(repo, state, int(battle["id"]), side, unit, target)
	if not action in legal or not BattleSystem._can_fight(repo, state, unit) \
			or bool(BattleSystem._stored(state, unit).get("captured", false)):
		result["reason"] = "Unit task holds: current law, agreement or incapacity bars execution"
		return result
	if request["source"] == "player" and (ArmySystem.is_foe(state, unit) \
			or ArmySystem.realm_of(repo, unit, state) != repo.resolve_realm("player_realm")):
		result["reason"] = "Unit task holds: the recipient is no longer under crown control"
		return result
	if target != "" and (BattleRules.side_of(battle, target) != ("def" if side == "att" else "att") \
			or not BattleSystem._can_fight(repo, state, target) \
			or bool(BattleSystem._stored(state, target).get("captured", false))):
		result["reason"] = "Unit task holds: its designated enemy is no longer available"
		return result
	if action == "pursue":
		var opponents: Array = battle["def" if side == "att" else "att"] if target == "" else [target]
		var withdrawing := false
		for enemy: String in opponents:
			if BattleSystem._can_fight(repo, state, enemy) \
					and not bool(BattleSystem._stored(state, enemy).get("captured", false)) \
					and (BattleOrders.kind(battle, "def" if side == "att" else "att") == "retreat" \
					or bool(BattleSystem._stored(state, enemy).get("battle_retreat", false))):
				withdrawing = true
		if not withdrawing:
			result["reason"] = "Unit task holds: no available designated enemy is withdrawing"
			return result
		result["pursuit_target"] = target
		result["pursuit_region"] = String(request.get("region", ""))
	result["kind"] = action if action in ["hold", "retreat"] else "attack"
	if result["kind"] == "attack" and not "attack" in legal:
		result["kind"] = "hold"
		result["reason"] = "Unit task holds: attack is barred by current law or agreement"
	return result


## Only live opposing contacts obstruct a flank. Battle membership from a new
## encounter pauses field travel; within its original battle use actual fronts.
static func _interceptors(repo: DataRepository, state: GameState, battle: Dictionary, unit: String, record: Dictionary) -> Array:
	var side := BattleRules.side_of(battle, unit)
	if side == "":
		return []
	var elsewhere := BattleSystem.canonical(state, int(record["request"]["battle_id"])) != int(battle["id"])
	var out: Array = []
	for enemy: String in battle["def" if side == "att" else "att"]:
		var entry := BattleSystem._stored(state, enemy)
		if enemy == record["request"]["target_unit"] or not BattleSystem._can_fight(repo, state, enemy) \
				or bool(entry.get("captured", false)) or bool(entry.get("battle_retreat", false)) \
				or BattleOrders.kind(battle, "def" if side == "att" else "att") == "retreat":
			continue
		if (elsewhere and BattleSystem._within(BattleSystem._at_m(repo, state, unit), BattleSystem._at_m(repo, state, enemy),
				int(repo.bal("battle_contact_km") * 1000))) \
				or BattleCharge._approach(repo, battle, unit, enemy, Vector2.ZERO) == 0.0:
			out.append(enemy)
	out.sort()
	return out


## Save obstruction transitions once, outside read-only action/strength queries.
## A pending round keeps both its action and this receipt frozen through retries.
static func note_interception(repo: DataRepository, state: GameState, battle: Dictionary, unit: String) -> void:
	var ledger: Dictionary = state.unit_tasks.get(unit, {})
	var record: Dictionary = ledger.get("orders", {}).get(String(ledger.get("current_id", "")), {})
	if record.is_empty() or record["status"] != "received" or record["request"]["task"] != "flank" \
			or String(record["request"]["target_unit"]) == "":
		return
	var enemies := _interceptors(repo, state, battle, unit, record) if not battle.is_empty() else []
	var old: Dictionary = record.get("obstruction", {})
	if enemies.is_empty() and not bool(old.get("active", false)):
		return
	if old.get("units", []) == enemies and bool(old.get("active", false)) == not enemies.is_empty():
		return
	var reason := "Flank obstructed; temporary self-defence against " + ", ".join(enemies) if not enemies.is_empty() else "Interception cleared; original flank remains subject to its received task"
	record["obstruction"] = {"active": not enemies.is_empty(), "units": enemies,
		"battle_id": int(battle.get("id", -1)), "day": state.absolute_day(), "reason": reason}
	_transition(state, record, "received", reason)


static func _find(state: GameState, id: String) -> Dictionary:
	for ledger: Dictionary in state.unit_tasks.values():
		if ledger["orders"].has(id):
			return ledger["orders"][id]
	return {}


static func _canonical(order: Dictionary) -> Dictionary:
	return {"id": String(order.get("id", "")), "unit": String(order.get("unit", "")),
		"battle_id": int(order.get("battle_id", -1)), "task": String(order.get("task", "")),
		"formation": String(order.get("formation", "")), "target_unit": String(order.get("target_unit", "")),
		"source": String(order.get("source", "player")), "issuer": String(order.get("issuer", "")),
		"max_route_m": int(order.get("max_route_m", 0)), "region": "|".join(_region_codes(String(order.get("region", ""))))}


static func _region_codes(region: String) -> Array:
	var codes: Array = []
	for code: String in region.split("|", false):
		if not code in codes:
			codes.append(code)
	codes.sort()
	return codes


static func _format_error(order: Dictionary) -> String:
	var fields := ["id", "unit", "battle_id", "task", "formation", "target_unit", "source", "issuer", "max_route_m", "region"]
	for field: Variant in order:
		if not field is String:
			return "A unit task field name must be text."
		if not field in fields:
			return "Unknown unit task field: " + field
		if field == "battle_id":
			if not order[field] is int or int(order[field]) < 0:
				return "A unit task needs a whole battlefield id."
		elif field == "max_route_m":
			if not order[field] is int or int(order[field]) < 0:
				return "A pursuit route bound is whole metres, zero or more."
		elif not order[field] is String:
			return "A unit task field must be text: " + field
	return ""


static func _refusal(repo: DataRepository, state: GameState, order: Dictionary, target_observed := true) -> String:
	var unit := String(order["unit"])
	var battle := BattleSystem.battle_by_id(state, int(order["battle_id"]))
	var side := BattleRules.side_of(battle, unit)
	if order["id"] == "":
		return "A unit task needs a stable request id."
	if battle.is_empty() or side == "":
		return "The unit is no longer on this battlefield."
	var entry := BattleSystem._stored(state, unit)
	if not BattleSystem._can_fight(repo, state, unit) or bool(entry.get("captured", false)):
		return "The unit can no longer receive a fighting task."
	if order["task"] == "cancel":
		if order["source"] != "player" or not state.regiments.has(unit) or ArmySystem.is_foe(state, unit) \
				or ArmySystem.realm_of(repo, unit, state) != repo.resolve_realm("player_realm"):
			return "Only the crown can cancel this unit task."
		if order["formation"] != "" or order["target_unit"] != "" or order["issuer"] != "" \
				or int(order["max_route_m"]) != 0 or order["region"] != "":
			return "A cancellation has no formation, enemy target or delegated issuer."
		return ""
	if not repo.battle_behaviors.has(order["task"]):
		return "Unknown unit task."
	if order["formation"] != "":
		var why := BattleFormation.refusal(repo, state, int(order["battle_id"]), side, String(order["formation"]), unit)
		if why != "":
			return why
	var action := String(repo.battle_behaviors[order["task"]]["legal_action"])
	if (int(order["max_route_m"]) != 0 or order["region"] != "") and action != "pursue":
		return "Only a pursuit carries pursuit bounds."
	for code: String in _region_codes(String(order["region"])):
		if not repo.provinces.has(code):
			return "Unknown province in the pursuit region: " + code
	var source := String(order["source"])
	if source == "player":
		if not state.regiments.has(unit) or ArmySystem.is_foe(state, unit) \
				or ArmySystem.realm_of(repo, unit, state) != repo.resolve_realm("player_realm"):
			return "The crown cannot command this unit."
	elif source == "general":
		var issuer := String(order["issuer"])
		if issuer == "" or issuer != String(battle.get("commanders", {}).get(side, "")):
			return "The warrant is not from this side's commanding general."
		var eligible := false
		for member: String in battle[side]:
			if BattleSystem._can_fight(repo, state, member) \
					and not bool(BattleSystem._stored(state, member).get("captured", false)) \
					and MilitaryCommanders.eligible_for_unit(repo, state, member, issuer) \
					and String(state.military_rosters.get(member, {}).get("commander_id", "")) == issuer:
				eligible = true
		if not eligible:
			return "The commanding general is no longer available on this battlefield."
		var active := current(state, unit)
		if not active.is_empty() and active["request"]["source"] == "player":
			return "A general cannot replace a delivered player unit task."
		# shortcut: accept only royal pursuit until contact-plan authority has a validated delivery path.
		if action == "pursue":
			return "Pursuit needs an explicit royal task or a received contact plan."
	else:
		return "A local commander cannot replace a unit's primary task."
	var target := String(order["target_unit"])
	if target != "":
		var target_side := BattleRules.side_of(battle, target)
		if target_side == "" or target_side == side:
			return "The designated enemy can no longer be tasked against."
		if target_observed and (not BattleSystem._can_fight(repo, state, target) \
				or bool(BattleSystem._stored(state, target).get("captured", false))):
			return "The designated enemy can no longer be tasked against."
	if not action in BattleRules.legal_actions(repo, state, int(battle["id"]), side, unit, target):
		return "Received military law or an agreed battlefield term forbids this unit task."
	if String(battle.get("routed_side", "")) == side and action != "retreat":
		return "A routed unit cannot resume its battle line."
	return ""


static func _transition(state: GameState, record: Dictionary, status: String, reason: String) -> void:
	record["status"] = status
	record["reason"] = reason
	record["history"].append({"status": status, "reason": reason, "day": state.absolute_day(),
		"source": String(record["request"]["source"])})


static func refusal_of(repo: DataRepository, state: GameState, raw: Dictionary, target_observed := true) -> String:
	var why := _format_error(raw)
	if why != "":
		return why
	return _refusal(repo, state, _canonical(raw), target_observed)


static func invalidate_task(state: GameState, id: String, reason: String) -> void:
	var record := _find(state, id)
	if not record.is_empty() and record["status"] == "pending":
		_transition(state, record, "invalid", reason)


static func issue_task(repo: DataRepository, state: GameState, raw: Dictionary) -> Dictionary:
	var why := _format_error(raw)
	if why != "":
		return {"status": "invalid", "reason": why}
	var order := _canonical(raw)
	var old := _find(state, String(order["id"]))
	if not old.is_empty():
		return old.duplicate(true) if _canonical(old["request"]) == order else \
			{"status": "invalid", "reason": "This request id already names another unit task."}
	why = _refusal(repo, state, order)
	if why != "":
		return {"status": "invalid", "reason": why}
	var unit := String(order["unit"])
	if not state.unit_tasks.has(unit):
		state.unit_tasks[unit] = {"current_id": "", "issued_sequence": 0, "received_sequence": 0,
			"player_received_sequence": 0, "orders": {}}
	var ledger: Dictionary = state.unit_tasks[unit]
	ledger["issued_sequence"] += 1
	var record := {"request": order, "sequence": int(ledger["issued_sequence"]), "history": []}
	_transition(state, record, "pending", "The unit task awaits actual delivery.")
	ledger["orders"][order["id"]] = record
	return record.duplicate(true)


static func deliver_task(repo: DataRepository, state: GameState, order_id: String) -> Dictionary:
	var record := _find(state, order_id)
	if record.is_empty():
		return {"status": "invalid", "reason": "Unknown unit task warrant."}
	if record["status"] != "pending":
		return record.duplicate(true)
	var order: Dictionary = record["request"]
	var ledger: Dictionary = state.unit_tasks[order["unit"]]
	var received := int(ledger["player_received_sequence"] if order["source"] == "player" else ledger["received_sequence"])
	if int(record["sequence"]) <= received:
		_transition(state, record, "superseded", "A newer unit task has already arrived.")
		return record.duplicate(true)
	var why := _refusal(repo, state, order)
	if why != "":
		_transition(state, record, "invalid", why)
		return record.duplicate(true)
	if order["formation"] != "":
		var battle := BattleSystem.battle_by_id(state, int(order["battle_id"]))
		BattleFormation.request(repo, state, int(order["battle_id"]), BattleRules.side_of(battle, String(order["unit"])),
			String(order["formation"]), String(order["unit"]))
	var previous: Dictionary = ledger["orders"].get(String(ledger["current_id"]), {})
	var kept: Dictionary = {}
	var kept_bound := ""
	if not previous.is_empty() and previous["status"] in ["received", "bounded"] and previous.has("pursuit"):
		var was: Dictionary = previous["request"]
		var same := BattleSystem.canonical(state, int(was["battle_id"])) == BattleSystem.canonical(state, int(order["battle_id"]))
		for key: String in ["task", "target_unit", "max_route_m", "region"]:
			same = same and was.get(key, 0 if key in ["max_route_m"] else "") == order[key]
		if same:
			kept = (previous["pursuit"] as Dictionary).duplicate()
			if previous["status"] == "bounded":
				kept_bound = String(previous["reason"])
	if not previous.is_empty() and previous.get("status", "") == "received" \
			and BattleSystem.canonical(state, int(previous["request"]["battle_id"])) == BattleSystem.canonical(state, int(order["battle_id"])) \
			and previous.get("request", {}).get("task", "") == "flank" and order["task"] == "flank" and previous["request"]["target_unit"] == order["target_unit"] \
			and previous.get("flank", {}).get("phase", "") == "contact":
		record["flank"] = (previous["flank"] as Dictionary).duplicate(true)
	var cancelling: bool = order["task"] == "cancel"
	if not previous.is_empty():
		_transition(state, previous, "cancelled" if cancelling else "replaced",
			"The crown cancels the unit task: " + order_id if cancelling else \
			"A newer lawful unit task arrived: " + order_id)
	ledger["current_id"] = "" if cancelling else order_id
	ledger["received_sequence"] = maxi(int(ledger["received_sequence"]), int(record["sequence"]))
	if order["source"] == "player":
		ledger["player_received_sequence"] = int(record["sequence"])
	_transition(state, record, "received", "The unit receives the crown’s task cancellation." if cancelling else \
		"The unit receives its lawful primary task.")
	if not cancelling and String(repo.battle_behaviors.get(order["task"], {}).get("legal_action", "")) == "pursue":
		var here := BattleSystem._stored(state, String(order["unit"]))
		record["pursuit"] = kept if not kept.is_empty() else {"start_x_m": int(here.get("x_m", 0)),
			"start_y_m": int(here.get("y_m", 0)), "route_m": 0}
		if kept_bound != "":
			_transition(state, record, "bounded", kept_bound)
	return record.duplicate(true)


## Pure movement preview, shared by ordinary travel and clearance halts. Limit
## the actual detoured polyline before publishing a stop, never move a receipt.
static func pursuit_walk(repo: DataRepository, state: GameState, unit: String,
		entry: Dictionary, here: Vector2i, path: Array, step: int) -> Dictionary:
	var record := current(state, unit)
	var active: bool = not record.is_empty() and record["status"] == "received" and record.has("pursuit") \
		and not bool(entry.get("battle_retreat", false)) and int(entry.get("disengaging", 0)) != 1
	active = active and (int(record.get("request", {}).get("max_route_m", 0)) > 0 \
		or String(record.get("request", {}).get("region", "")) != "")
	var walked := MarchRoute.walk(here, path, step)
	walked["pursuit_reason"] = ""
	walked["limited"] = active
	if not active:
		return walked
	var request: Dictionary = record["request"]
	var remaining := int(request.get("max_route_m", 0)) - int(record["pursuit"]["route_m"])
	var limit := mini(step, ceili(MarchRoute.length_from(here, path)))
	var reason := ""
	if int(request.get("max_route_m", 0)) > 0 and remaining <= limit:
		limit = maxi(remaining, 0)
		reason = "Pursuit reached its farthest route distance: %d m" % int(request["max_route_m"])
	var region := String(request.get("region", ""))
	if region != "":
		var exit_m := MarchPath.region_exit(repo, state, here, path, region)
		if exit_m >= 0.0 and exit_m <= float(limit):
			limit = mini(limit, ceili(exit_m))
			reason = "Pursuit reached its region's edge"
	# Rounding a diagonal stop can add a metre or cross a slanting boundary.
	# Retreat toward the previous whole-metre route position until both fit.
	var allowance := limit
	while true:
		walked = MarchRoute.walk(here, path, limit)
		var traversed: Array = walked["passed"].duplicate()
		traversed.append(walked["at"])
		var actual := ceili(MarchRoute.length_from(here, traversed))
		var exit_m := MarchPath.region_exit(repo, state, here, traversed, region) if region != "" else -1.0
		if limit == 0 or (actual <= allowance and exit_m < 0.0):
			break
		limit -= 1
	walked["pursuit_reason"] = reason
	walked["limited"] = true
	return walked


## Credit metres a unit really walked to its received pursuit and check the
## bounds (route metres, region). True when the task became `bounded` now: a
## marching unit then halts where it stands (BattleSystem._halt).
static func credit_pursuit(repo: DataRepository, state: GameState, unit: String, metres: int, boundary_reason := "") -> bool:
	var ledger: Dictionary = state.unit_tasks.get(unit, {})
	var record: Dictionary = ledger.get("orders", {}).get(String(ledger.get("current_id", "")), {})
	if record.is_empty() or record["status"] != "received" or not record.has("pursuit"):
		return false
	var progress: Dictionary = record["pursuit"]
	progress["route_m"] = int(progress["route_m"]) + maxi(metres, 0)
	var request: Dictionary = record["request"]
	var why := boundary_reason
	var limit := int(request.get("max_route_m", 0))
	if why == "" and limit > 0 and int(progress["route_m"]) >= limit:
		why = "Pursuit reached its farthest route distance: %d m" % int(progress["route_m"])
	var region := String(request.get("region", ""))
	if why == "" and region != "":
		var here := ArmySystem.province_of(repo, state, BattleSystem._stored(state, unit))
		if not here in region.split("|"):
			why = "Pursuit reached its region's edge: " + here
	if why == "":
		return false
	_transition(state, record, "bounded", why)
	var entry := BattleSystem._stored(state, unit)
	if String(entry.get("order", "")) == ArmySystem.ORDER_MARCH:
		BattleSystem._halt(state, unit)
	ArmySystem._clear_route(entry)
	ArmySystem.drop_hold(entry)
	entry.erase("departure")
	return true


## Whether the record is a flank or a pursuit with a designated enemy that is
## still received: the kinds that follow the known target (P4.4c4).
static func _tracks(repo: DataRepository, record: Dictionary) -> bool:
	if record.is_empty() or record["status"] != "received" or String(record["request"]["target_unit"]) == "":
		return false
	var task := String(record["request"]["task"])
	return task == "flank" or String(repo.battle_behaviors.get(task, {}).get("legal_action", "")) == "pursue"


## A received pursuit following a target it knows: the gait's `pursuit` reason.
static func pursuing(repo: DataRepository, state: GameState, unit: String) -> bool:
	var record := current(state, unit)
	if record.is_empty() or not _tracks(repo, record):
		return false
	var action := String(repo.battle_behaviors.get(String(record["request"]["task"]), {}).get("legal_action", ""))
	return action == "pursue" and String(record.get("track", {}).get("phase", "")) == "follow"


## Once a day, before the march freezes: each crown unit with a received flank
## or pursuit task, in no battle, marches at its target as the unit's OWN sight
## knows it (the target within player_sight_km of the recipient, men under
## arms), else at the last point it saw; on that point it searches for
## battle_search_days, a sighting within battle_search_range_m of the point
## resuming the follow; a search past its days ends the task (search_failed)
## and the unit halts. Never reads GameState.sightings or a hidden position.
static func track_day(repo: DataRepository, state: GameState) -> void:
	var today := state.absolute_day()
	var sight := Sighting.sight_m(repo)
	var codes: Array = state.unit_tasks.keys()
	codes.sort()
	for code_value: Variant in codes:
		var unit := String(code_value)
		var ledger: Dictionary = state.unit_tasks[unit]
		var record: Dictionary = ledger["orders"].get(String(ledger.get("current_id", "")), {})
		if not _tracks(repo, record) or not state.regiments.has(unit) or ArmySystem.is_foe(state, unit) \
				or ArmySystem.realm_of(repo, unit, state) != repo.resolve_realm("player_realm") \
				or not BattleSystem.battle_of(state, unit).is_empty():
			continue
		note_interception(repo, state, {}, unit)
		var entry := BattleSystem._stored(state, unit)
		if bool(entry.get("captured", false)) or not BattleSystem._can_fight(repo, state, unit):
			continue
		var track: Dictionary = record.get("track", {})
		if int(track.get("done_day", -1)) == today:
			continue
		var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
		var target_code := String(record["request"]["target_unit"])
		var target := BattleSystem._stored(state, target_code)
		var there := Vector2i(int(target.get("x_m", 0)), int(target.get("y_m", 0)))
		var seen := not target.is_empty() and Sighting.men_of(repo, state, target_code) > 0 \
			and (there - here).length_squared() <= sight * sight
		var phase := String(track.get("phase", ""))
		var point := Vector2i(int(track.get("x_m", 0)), int(track.get("y_m", 0)))
		if seen and phase == "search":
			var range_m := int(repo.bal("battle_search_range_m"))
			seen = (there - point).length_squared() <= range_m * range_m
		if seen:
			if record["request"]["task"] == "flank" and (not BattleSystem._can_fight(repo, state, target_code) \
					or bool(target.get("captured", false))):
				_transition(state, record, "completed", "The visible designated enemy can no longer fight")
				BattleSystem._halt(state, unit)
				continue
			record["track"] = {"x_m": there.x, "y_m": there.y, "day": today, "phase": "follow",
				"search_until_day": 0, "done_day": today}
			if record["request"]["task"] == "flank":
				_snapshot_flank(repo, state, unit, record)
				_aim_flank(repo, state, unit, record)
			else:
				_aim(repo, state, unit, entry, there)
		elif phase == "follow":
			track["done_day"] = today
			var arrived := here == point
			if record["request"]["task"] == "flank":
				arrived = _aim_flank(repo, state, unit, record)
			if arrived and String(entry.get("order", "")) != ArmySystem.ORDER_MARCH:
				track["phase"] = "search"
				track["search_until_day"] = today + int(repo.bal("battle_search_days"))
			elif record["request"]["task"] != "flank":
				_aim(repo, state, unit, entry, point)
		elif phase == "search" and today > int(track["search_until_day"]):
			_transition(state, record, "search_failed", "Lost the target and the search found nothing")
			BattleSystem._halt(state, unit)


## March the unit at `to`. A unit already marching is re-aimed in place (its
## packing, if any, is not restarted); a standing one is ordered as any local
## march is.
static func _aim(repo: DataRepository, state: GameState, unit: String, entry: Dictionary, to: Vector2i) -> void:
	if String(entry.get("order", "")) == ArmySystem.ORDER_MARCH:
		ArmySystem.aim_entry(repo, entry, to, ArmySystem.is_naval(repo, state, unit))
	elif Vector2i(int(entry["x_m"]), int(entry["y_m"])) != to:
		ArmySystem.set_march_m(repo, state, unit, to)


## Only the recipient's own sight publishes target geometry into its saved task.
static func _snapshot_flank(repo: DataRepository, state: GameState, unit: String, record: Dictionary) -> void:
	var target := String(record["request"]["target_unit"])
	var entry := BattleSystem._stored(state, target)
	if entry.is_empty() or Sighting.men_of(repo, state, target) <= 0:
		return
	var here := BattleSystem._at_m(repo, state, unit)
	var there := BattleSystem._at_m(repo, state, target)
	var sight := Sighting.sight_m(repo)
	if here.distance_squared_to(there) > sight * sight:
		return
	var battle := BattleSystem.battle_of(state, target)
	var flank: Dictionary = record.get("flank", {})
	var previous: Dictionary = flank.get("known", {})
	var facing := int(entry.get("facing_deg", battle.get("group_facing", {}).get(target, previous.get("facing_deg", 0))))
	if not entry.has("facing_deg") and battle.is_empty() and not previous.is_empty():
		var observed := there - Vector2i(int(previous["x_m"]), int(previous["y_m"]))
		if observed != Vector2i.ZERO:
			facing = WarFront.facing_deg(Vector2(observed))
	var shape := BattleFormation.of_unit(state, target)
	var n := BattleGroups.counts(ArmySystem.fit_count(repo, state, target), int(repo.bal("battle_group_size"))).size()
	var radius := 0
	for offset: Vector2i in BattleGroups.layout(repo, shape if shape != "" else BattleFormation.DEFAULT, n, Vector2i.ZERO, 0):
		radius = maxi(radius, ceili(Vector2(offset).length()))
	var positions := BattleGroups.layout(repo, shape if shape != "" else BattleFormation.DEFAULT, n, there, facing)
	var geometry := {"x_m": there.x, "y_m": there.y, "facing_deg": facing, "radius_m": radius,
		"points_m": MarchRoute.to_pairs(positions)}
	if flank.get("known", {}) != geometry:
		flank["known"] = geometry
		flank.erase("path_m")
	record["flank"] = flank


## Two outboard approaches. Every leg uses the terrain router, then rejects its
## unreachable straight-line fallback and shortcuts through the known enemy.
static func flank_route(repo: DataRepository, here: Vector2i, known: Dictionary) -> Array:
	var centre := Vector2i(int(known["x_m"]), int(known["y_m"]))
	var face := WarFront.facing_vector(int(known["facing_deg"]))
	var across := Vector2(-face.y, face.x)
	var radius := int(known["radius_m"]) + int(repo.bal("battle_group_contact_m"))
	var forward := Vector2(here - centre).dot(face)
	var bypass := maxf(absf(forward), float(radius)) * (-1.0 if forward < 0.0 else 1.0)
	var grid := MarchPath.of_pack(repo)
	var points := MarchRoute.from_pairs(known.get("points_m", [[centre.x, centre.y]]))
	if points.is_empty():
		return []
	var reach := float(repo.bal("battle_group_contact_m"))
	var best: Array = []
	var length := INF
	for sign_: int in [1, -1]:
		var edge: Vector2i = points[0]
		for point: Vector2i in points:
			if Vector2(point - centre).dot(across) * float(sign_) > Vector2(edge - centre).dot(across) * float(sign_):
				edge = point
		var to := edge + Vector2i((across * reach * float(sign_)).round())
		var outside := centre + Vector2i((across * float(radius * sign_)).round())
		var stage := outside + Vector2i((face * bypass).round())
		var align := outside + Vector2i((face * Vector2(edge - centre).dot(face)).round())
		var outward := centre + Vector2i((face * bypass + across * Vector2(here - centre).dot(across)).round())
		var path: Array = []
		var previous := here
		var valid := true
		var corners: Array = [outward, stage, align, to]
		# Already outboard: stay on that side instead of walking back to staging.
		if Vector2(here - centre).dot(across) * float(sign_) >= float(radius):
			corners = [to]
		for corner: Vector2i in corners:
			if corner == previous:
				continue
			if grid != null and (corner.x < 0 or corner.y < 0 or corner.x >= grid.cols * grid.cell_m \
					or corner.y >= grid.rows * grid.cell_m or not grid.joins(previous, corner)):
				valid = false
				break
			var leg: Array = [corner] if grid == null else grid.road(previous, corner)
			for point: Vector2i in leg:
				if grid != null and not grid.clear(previous, point, [grid.cell_of(here)]):
					valid = false
				for enemy: Vector2i in points:
					if Geometry2D.get_closest_point_to_segment(Vector2(enemy), Vector2(previous), Vector2(point)).distance_to(Vector2(enemy)) < reach - 1.0:
						valid = false
						break
				if not valid:
					break
				path.append(point)
				previous = point
			if not valid:
				break
		if valid and MarchRoute.length_from(here, path) < length:
			best = path
			length = MarchRoute.length_from(here, path)
	return best


static func _flank_path(repo: DataRepository, state: GameState, unit: String, record: Dictionary) -> Array:
	var flank: Dictionary = record.get("flank", {})
	if flank.get("known", {}).is_empty():
		return []
	var here := BattleSystem._at_m(repo, state, unit)
	var path: Array = MarchRoute.from_pairs(flank["path_m"]) if flank.has("path_m") else flank_route(repo, here, flank["known"])
	while not path.is_empty() and path[0] == here:
		path.pop_front()
	flank["path_m"] = MarchRoute.to_pairs(path)
	return path


## Field travel keeps camp packing and the ordinary saved march/substep budget.
## Return true on the last reachable side point for the existing finite search.
static func _aim_flank(repo: DataRepository, state: GameState, unit: String, record: Dictionary) -> bool:
	if record.get("flank", {}).get("phase", "") == "contact":
		BattleSystem._halt(state, unit)
		return true
	var path := _flank_path(repo, state, unit, record)
	if path.is_empty():
		BattleSystem._halt(state, unit)
		return true
	_aim(repo, state, unit, BattleSystem._stored(state, unit), path[0])
	return false


## Called instead of generic deployment. Once contact commits this approach,
## the task never automatically circles again, including synonymous receipts.
static func deploy_flank(repo: DataRepository, state: GameState, battle: Dictionary, unit: String) -> bool:
	note_interception(repo, state, battle, unit)
	var action := BattleSystem.unit_action(repo, state, battle, unit)
	var record := _find(state, String(action.get("task_id", "")))
	if record.is_empty() or record["request"]["task"] != "flank" or record["request"]["target_unit"] == "":
		return false
	if action["kind"] != "attack":
		return true
	_snapshot_flank(repo, state, unit, record)
	BattleGroups.refresh(repo, state, battle)
	var flank: Dictionary = record.get("flank", {})
	if flank.get("phase", "") == "contact":
		return true
	if BattleGroups.engaged_counts(repo, state, battle, unit, String(record["request"]["target_unit"])).x > 0:
		flank["phase"] = "contact"
		record["flank"] = flank
		return true
	var path := _flank_path(repo, state, unit, record)
	if path.is_empty():
		return true
	var here := BattleSystem._at_m(repo, state, unit)
	var budget := int(repo.bal("battle_deploy_step_m"))
	var axis := Vector2(Vector2i(path[0]) - here).normalized()
	var contact := BattleCharge._approach(repo, battle, unit, String(record["request"]["target_unit"]), axis)
	var distance := mini(budget, ceili(contact)) if not is_inf(contact) else budget
	var walked := MarchRoute.walk(here, [path[0]], distance)
	var to: Vector2i = walked["at"]
	while here.distance_squared_to(to) > budget * budget:
		distance -= 1
		walked = MarchRoute.walk(here, [path[0]], distance)
		to = walked["at"]
	if not BattleCharge._clear(repo, battle, unit, to - here):
		return true
	var entry := BattleSystem._stored(state, unit)
	entry["x_m"] = to.x
	entry["y_m"] = to.y
	flank["path_m"] = MarchRoute.to_pairs((walked["path"] as Array) + path.slice(1))
	BattleGroups.refresh(repo, state, battle)
	if BattleGroups.engaged_counts(repo, state, battle, unit, String(record["request"]["target_unit"])).x > 0:
		flank["phase"] = "contact"
	return true
