class_name ArmyGroups
extends RefCounted
## Armies as SELECTION GROUPS (spec 2026-11-27-army-groups-design, owner
## 2026-11-27): a named set of the crown's land regiments selected together.
## Not a merged force — every regiment keeps its own march, supply and battle;
## no rule reads a group. A regiment is in at most one group, and a group of
## fewer than `army_group_min_members` live members dissolves.


## Whether `code` may stand in a group: a live land regiment of the player's realm.
static func eligible(repo: DataRepository, state: GameState, code: String) -> bool:
	var r := ArmySystem.regiment(repo, code, state)
	return not r.is_empty() and state.regiments.has(code) \
		and String(r.get("is_naval", "0")) != "1" \
		and String(r.get("kingdom_code", "")) == repo.resolve_realm("player_realm") \
		and ArmySystem.living_count(repo, state, code) > 0


## The group `code` stands in, "" for none.
static func group_of(state: GameState, code: String) -> String:
	for id: String in state.army_groups:
		if (state.army_groups[id]["members"] as Array).has(code):
			return id
	return ""


## A new group of `codes` (the eligible ones, in the order given). Each leaves
## its old group first. {ok, id} or {ok: false, error}.
static func form(repo: DataRepository, state: GameState, codes: Array, reason: String) -> Dictionary:
	var members: Array = []
	for c: Variant in codes:
		if eligible(repo, state, String(c)) and not members.has(String(c)):
			members.append(String(c))
	if members.size() < int(repo.bal("army_group_min_members")):
		return {"ok": false, "error": "An army needs at least %d of your land regiments." % int(repo.bal("army_group_min_members"))}
	var used: Array = []
	for id: String in state.army_groups:
		used.append(String(state.army_groups[id]["name"]))
	var name := ""
	for n: String in repo.army_group_names:
		if not used.has(n):
			name = n
			break
	if name == "":
		return {"ok": false, "error": "Every army name is in use: disband one first."}
	for c: String in members:
		leave(repo, state, c, "joined %s" % name)
	state.army_group_next_id += 1
	var id := str(state.army_group_next_id)
	state.army_groups[id] = {"name": name, "members": members, "formed_tick": state.tick, "formed_day": state.day}
	_log(repo, state, id, "formed", ",".join(members), reason)
	return {"ok": true, "id": id}


## Remove group `id` (its regiments stand alone again).
static func disband(repo: DataRepository, state: GameState, id: String, reason: String) -> bool:
	if not state.army_groups.has(id):
		return false
	state.army_groups.erase(id)
	_log(repo, state, id, "disbanded", "", reason)
	return true


## `code` leaves its group, which dissolves when too few remain.
static func leave(repo: DataRepository, state: GameState, code: String, reason: String) -> void:
	var id := group_of(state, code)
	if id == "":
		return
	(state.army_groups[id]["members"] as Array).erase(code)
	_log(repo, state, id, "left", code, reason)
	_dissolve_if_small(repo, state, id)


## Drop every member no longer eligible (destroyed, lost, gone to sea), in id
## and member order; dissolve the groups left too small.
static func reconcile(repo: DataRepository, state: GameState) -> void:
	var ids := state.army_groups.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id: String in ids:
		for c: String in (state.army_groups[id]["members"] as Array).duplicate():
			if not eligible(repo, state, c):
				(state.army_groups[id]["members"] as Array).erase(c)
				_log(repo, state, id, "left", c, "no longer under arms")
		_dissolve_if_small(repo, state, id)


## What a card shows of group `id`: {id, name, codes, labels, men, slowest_km}; {} for none.
static func summary(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	if not state.army_groups.has(id):
		return {}
	var g: Dictionary = state.army_groups[id]
	var labels: Array = []
	var men := 0
	var slowest := -1.0
	for c: String in g["members"]:
		labels.append(String(ArmySystem.regiment(repo, c, state).get("label", c)))
		men += ArmySystem.living_count(repo, state, c)
		var km := ArmySystem.speed_km_per_day(repo, state, c)
		slowest = km if slowest < 0.0 else minf(slowest, km)
	return {"id": id, "name": String(g["name"]), "codes": (g["members"] as Array).duplicate(),
		"labels": labels, "men": men, "slowest_km": maxf(slowest, 0.0)}


static func _dissolve_if_small(repo: DataRepository, state: GameState, id: String) -> void:
	if (state.army_groups[id]["members"] as Array).size() < int(repo.bal("army_group_min_members")):
		state.army_groups.erase(id)
		_log(repo, state, id, "dissolved", "", "too few regiments left")


static func _log(repo: DataRepository, state: GameState, id: String, change: String, codes: String, reason: String) -> void:
	state.army_group_log.append({"tick": state.tick, "day": state.day, "group": id, "change": change,
		"codes": codes, "reason": reason})
	var keep := int(repo.bal("army_group_log_keep"))
	if state.army_group_log.size() > keep:
		state.army_group_log = state.army_group_log.slice(state.army_group_log.size() - keep)
