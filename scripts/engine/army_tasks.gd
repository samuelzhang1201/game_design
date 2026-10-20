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
	var courier := false
	var limits: Array = []
	for c: Variant in codes:
		var code := String(c)
		units.append({"code": code,
			"commander_id": String(state.military_rosters.get(code, {}).get("commander_id", "")),
			"eta_days": CourierSystem.arrival_days(repo, state, code, dest)})
		courier = courier or not KingSystem.can_command(repo, state, code)
		for lim: Array in repo.task_kinds[kind].get("law_limits", []):
			var words := String(repo.task_words.get(lim[2], lim[2]))
			if String(LawSystem.received(repo, state, lim[0], code)["value"]) == lim[1] and not words in limits:
				limits.append(words)
	var gold := int(OrderCosts.gold_of(repo, "ARMY_TASK"))
	if courier:
		gold += CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)
	return {"ok": true, "kind": kind, "units": units, "towns": towns, "target": target,
		"cells": TaskCoverage.cells_in_circle(repo, center, radius).size(),
		"cost": {"gold": gold, "courier": courier}, "encounter_policy": policy,
		"law_limits": limits}
