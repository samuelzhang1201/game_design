class_name ArmyTasks
extends RefCounted
## The area-task PREVIEW (P6.1b, spec 2026-10-16 battle-system §13.1/.3-.5): what
## a circle order would do, shown before anything is paid or sent. Pure and free:
## it never writes state and reads only what the crown knows - its own units, the
## towns it holds or has a filed report on (Intel), the order ETA and the laws
## received. A hidden foe or an unknown town never reaches it. Whole metres and days.

## The laws a kind's actions are limited by: kind -> [law, forbidding value, words key].


static func _refuse(repo: DataRepository, key: String) -> Dictionary:
	return {"ok": false, "reason": String(repo.task_words.get(key, key))}


## A town the crown knows: a realm town, or one a filed report covers (the same
## gate as the town card: Intel.level above `basic`, else a `town_people` report).
static func known_town(repo: DataRepository, state: GameState, burg: String) -> bool:
	var b: Dictionary = repo.burgs.get(burg, {})
	if b.is_empty():
		return false
	var subj := {"kind": "burg", "code": burg, "x": float(b["x"]), "y": float(b["y"])}
	return Intel.level(repo, state, subj) != "basic" \
		or not Intel.estimate(repo, state, subj, "town_people").is_empty()


## The crown's own land unit with men under arms and not captured.
static func _own_land_unit(repo: DataRepository, state: GameState, realm: String, code: String) -> bool:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or ArmySystem.is_foe(state, code) or not state.regiments.has(code):
		return false
	return String(reg.get("kingdom_code", "")) == realm and String(reg.get("is_naval", "0")) != "1" \
		and not bool((state.regiments[code] as Dictionary).get("captured", false)) \
		and ArmySystem.fit_count(repo, state, code) > 0


static func known_towns_in(repo: DataRepository, state: GameState, center_m: Vector2i, radius_m: int) -> Array:
	var out: Array = []
	var codes: Array = repo.burgs.keys()
	codes.sort()
	var r2 := radius_m * radius_m
	for c: String in codes:
		var d := ArmyGround.town_point_m(repo, c) - center_m
		if d.x * d.x + d.y * d.y <= r2 and known_town(repo, state, c):
			out.append(c)
	return out


## task = {kind, unit_codes, center_x_m, center_y_m, radius_m, known_target_id,
## encounter_policy}. Returns {ok: false, reason} or the preview (see the plan).
static func preview(repo: DataRepository, state: GameState, realm: String, task: Dictionary) -> Dictionary:
	var kind := String(task.get("kind", ""))
	var codes: Array = task.get("unit_codes", [])
	if codes.is_empty():
		return _refuse(repo, "no_units")
	for c: Variant in codes:
		if not _own_land_unit(repo, state, realm, String(c)):
			return _refuse(repo, "bad_unit")
	if not repo.task_kinds.has(kind):
		return _refuse(repo, "bad_kind")
	var spec: Dictionary = repo.task_kinds[kind]
	var radius := int(task.get("radius_m", 0))
	if radius <= 0 or radius > int(repo.bal("task_max_radius_m")):
		return _refuse(repo, "bad_radius")
	var center := Vector2i(int(task.get("center_x_m", 0)), int(task.get("center_y_m", 0)))
	var k := ArmySystem.metres_per_pack_px(repo)
	if center.x < 0 or center.y < 0 or center.x > int(float(repo.map_info.get("width", "0"))) * k \
			or center.y > int(float(repo.map_info.get("height", "0"))) * k:
		return _refuse(repo, "off_map")
	var policy := String(task.get("encounter_policy", ""))
	if policy == "":
		policy = String(spec["default_encounter"])
	elif not policy in (spec["allowed_encounters"] as Array):
		return _refuse(repo, "bad_policy")
	var target := String(task.get("known_target_id", ""))
	var towns := known_towns_in(repo, state, center, radius)
	if kind == "destroy" and target == "":
		return _refuse(repo, "destroy_no_kind")
	if kind == "siege":
		if towns.is_empty():
			return _refuse(repo, "siege_no_town")
		if target == "" and towns.size() > 1:
			return _refuse(repo, "siege_choose")
		if target == "":
			target = String(towns[0])
		elif not target in towns:
			return _refuse(repo, "siege_bad_target")
	var dest := ArmySystem.metres_to_pack(repo, center)
	var units: Array = []
	var limits: Array = []
	for c: Variant in codes:
		var code := String(c)
		units.append({"code": code,
			"commander_id": String(state.military_rosters.get(code, {}).get("commander_id", "")),
			"eta_days": CourierSystem.arrival_days(repo, state, code, dest)})
		for lim: Array in repo.task_kinds[kind].get("law_limits", []):
			var words := String(repo.task_words.get(lim[2], lim[2]))
			if String(LawSystem.received(repo, state, lim[0], code)["value"]) == lim[1] and not words in limits:
				limits.append(words)
	var fees := courier_fees(repo, state, codes)
	var gold := int(OrderCosts.gold_of(repo, "ARMY_TASK")) + fees
	var courier := fees > 0
	return {"ok": true, "kind": kind, "units": units, "towns": towns, "target": target,
		"cells": TaskCoverage.cells_in_circle(repo, center, radius).size(),
		"cost": {"gold": gold, "courier": courier}, "encounter_policy": policy,
		"law_limits": limits}


## The courier fees `codes` would pay now: one per unit beyond the king's command
## range that no waiting courier already serves (a courier carries to ONE unit).
static func courier_fees(repo: DataRepository, state: GameState, codes: Array) -> int:
	var n := 0
	for c: Variant in codes:
		var code := String(c)
		if not KingSystem.can_command(repo, state, code) \
				and CourierSystem.joinable(state, CourierSystem.ORDINARY, code, {}).is_empty():
			n += 1
	return n * CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)


## ---- the saved order (P6.1c): GameState.army_tasks ----

static func _note(state: GameState, task: Dictionary, revision: int, status: String, unit: String, reason: String) -> void:
	(task["history"] as Array).append({"day": state.absolute_day(), "revision": revision,
		"status": status, "unit": unit, "reason": reason})


## The next revision `snap`, pending on every unit it still has to reach.
static func _revise(state: GameState, task: Dictionary, snap: Dictionary, why: String) -> void:
	var revision := int(task["revision"]) + 1
	task["revision"] = revision
	(task["revisions"] as Dictionary)[str(revision)] = snap
	for code: String in task["unit_codes"]:
		var u: Dictionary = task["units"][code]
		if String(u["status"]) == "cancelled" and bool(snap["cancel"]):
			continue
		u["status"] = "pending"
		_note(state, task, revision, "pending", code, why)


static func task_of(state: GameState, id: String) -> Dictionary:
	return state.army_tasks.get(id, {})


## The units a task still holds (not yet recalled), sorted.
static func live_units(task: Dictionary) -> Array:
	var out: Array = []
	for code: String in task.get("unit_codes", []):
		if String(task["units"][code]["status"]) != "cancelled":
			out.append(code)
	return out


## The saved record of request `rid` ({} for none): {task_id, params, outcome}.
static func request_of(state: GameState, rid: String) -> Dictionary:
	var ids: Array = state.army_tasks.keys()
	ids.sort()
	for id: String in ids:
		var r: Dictionary = (state.army_tasks[id]["requests"] as Dictionary).get(rid, {})
		if not r.is_empty():
			return r
	return {}


## A new task (no `id`) or the next revision of task `task.id` (same units).
## Runs the free preview first; a refusal changes nothing. Returns {ok, id,
## revision, units (sorted codes now pending)} or {ok: false, reason}.
static func issue(repo: DataRepository, state: GameState, task: Dictionary, request_id := "") -> Dictionary:
	var shown := preview(repo, state, repo.resolve_realm("player_realm"), task)
	if not bool(shown["ok"]):
		return shown
	var id := String(task.get("id", ""))
	var codes: Array = (task["unit_codes"] as Array).duplicate()
	codes.sort()
	var snap := {"kind": String(task["kind"]), "center_x_m": int(task["center_x_m"]),
		"center_y_m": int(task["center_y_m"]), "radius_m": int(task["radius_m"]),
		"known_target_id": String(shown["target"]), "encounter_policy": String(shown["encounter_policy"]),
		"supply_floor": 0, "cancel": false, "issued_day": state.absolute_day()}
	var rec: Dictionary
	if id != "":
		rec = task_of(state, id)
		if rec.is_empty():
			return {"ok": false, "reason": String(repo.task_words["no_task"])}
		if (rec["unit_codes"] as Array) != codes:
			return {"ok": false, "reason": String(repo.task_words["task_units"])}
		if live_units(rec).is_empty():
			return {"ok": false, "reason": String(repo.task_words["task_over"])}
		for key: String in snap:
			if key != "cancel":
				rec[key] = snap[key]
		_revise(state, rec, snap, "a changed %s task awaits delivery" % snap["kind"])
	else:
		state.army_task_next_id += 1
		id = "AT%d" % state.army_task_next_id
		rec = {"id": id, "kind": snap["kind"], "unit_codes": codes, "center_x_m": snap["center_x_m"],
			"center_y_m": snap["center_y_m"], "radius_m": snap["radius_m"],
			"known_target_id": snap["known_target_id"], "encounter_policy": snap["encounter_policy"],
			"supply_floor": 0, "return_target": {}, "revision": 0, "issued_day": state.absolute_day(),
			"units": {}, "history": [], "revisions": {}, "requests": {}}
		for code: String in codes:
			var home := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state,
				ArmySystem.regiment(repo, code, state)))
			rec["return_target"][code] = {"x_m": home.x, "y_m": home.y}
			rec["units"][code] = {"status": "pending", "received_revision": 0, "received_day": 0}
		state.army_tasks[id] = rec
		_revise(state, rec, snap, "a %s task awaits delivery" % snap["kind"])
	if request_id != "":
		rec["requests"][request_id] = {"task_id": id, "params": {}, "outcome": {}}
	return {"ok": true, "id": id, "revision": int(rec["revision"]), "units": codes}


## A recall as the next revision. {ok, id, revision, units} or {ok: false, reason}.
static func cancel(repo: DataRepository, state: GameState, id: String, request_id := "") -> Dictionary:
	var task := task_of(state, id)
	if task.is_empty():
		return {"ok": false, "reason": String(repo.task_words["no_task"])}
	var live := live_units(task)
	if live.is_empty():
		return {"ok": false, "reason": String(repo.task_words["task_over"])}
	_revise(state, task, {"kind": task["kind"], "center_x_m": task["center_x_m"],
		"center_y_m": task["center_y_m"], "radius_m": task["radius_m"], "known_target_id": task["known_target_id"],
		"encounter_policy": task["encounter_policy"], "supply_floor": 0, "cancel": true,
		"issued_day": state.absolute_day()}, "a recall awaits delivery")
	if request_id != "":
		task["requests"][request_id] = {"task_id": id, "params": {}, "outcome": {}}
	return {"ok": true, "id": id, "revision": int(task["revision"]), "units": live}


## A delivery of `revision` to `unit`: {status: received|cancelled|superseded|invalid, reason}.
## Only a revision newer than the unit's own is taken; a recall sets it cancelled.
static func receive(repo: DataRepository, state: GameState, id: String, revision: int, unit: String) -> Dictionary:
	var task := task_of(state, id)
	if task.is_empty() or not (task["units"] as Dictionary).has(unit) \
			or not (task["revisions"] as Dictionary).has(str(revision)):
		return {"status": "invalid", "reason": String(repo.task_words["no_task"])}
	var u: Dictionary = task["units"][unit]
	if revision <= int(u["received_revision"]):
		var why := "revision %d came after revision %d and is set aside" % [revision, int(u["received_revision"])]
		_note(state, task, revision, "superseded", unit, why)
		return {"status": "superseded", "reason": why}
	var snap: Dictionary = task["revisions"][str(revision)]
	u["received_revision"] = revision
	u["received_day"] = state.absolute_day()
	var recall := bool(snap["cancel"])
	var status := "cancelled" if recall else "received"
	u["status"] = status if revision == int(task["revision"]) else "pending"
	var said := ("the recall reached the unit" if recall else "the %s task reached the unit" % snap["kind"]) \
		+ " (revision %d)" % revision
	_note(state, task, revision, status, unit, said)
	return {"status": status, "reason": said}


## The task revision `unit` is acting on ({} when none received, or recalled).
static func acting(state: GameState, id: String, unit: String) -> Dictionary:
	var task := task_of(state, id)
	if task.is_empty() or not (task["units"] as Dictionary).has(unit):
		return {}
	var snap: Dictionary = (task["revisions"] as Dictionary).get(str(int(task["units"][unit]["received_revision"])), {})
	return {} if snap.is_empty() or bool(snap["cancel"]) else snap


## A courier that will never arrive: the unit stays as it was, with the reason.
static func lapse(state: GameState, id: String, revision: int, unit: String, reason: String) -> void:
	var task := task_of(state, id)
	if not task.is_empty() and (task["units"] as Dictionary).has(unit) \
			and revision > int(task["units"][unit]["received_revision"]):
		_note(state, task, revision, "lapsed", unit, reason)
