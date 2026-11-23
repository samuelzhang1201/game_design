class_name SiegeRecord
extends RefCounted
## One saved record per besieged town (spec docs/superpowers/specs/
## 2026-11-18-player-siege-design.md §3): GameState.sieges[id], id "s<n>" from
## GameState.siege_next_id. Fields, whole numbers and strings: town, attacker,
## defender (kingdom codes; the defender is the town's holder when it opened,
## SiegeSystem.holder_of: the occupier for an occupied town), hosts (the AI
## hosts in it, code order), units (a crown besieger's unit codes, code order;
## [] for the AI), task_id ("" for the AI), opened_day,
## days, integrity (0..1000, set at open: 1000 for walls or a citadel, else 0),
## progress (0..1000, transitional: step 10 removes it), assault (1: the next
## day's battles may storm), assault_due (an assault owed), starved (1: the
## hunger was told), militia (the militia unit codes it raised, TownMilitia),
## woken (the standing units it woke, TownMilitia.wake). A host's mind keeps only `siege_id`, set until the
## siege's end has been told.

## The figures an old save kept on the host minds (migrate erases them).
const LEGACY := ["siege_progress", "siege_days", "siege_town", "assault", "assault_due", "starved"]
## The figures a record resets when its last host leaves.
const FIGURES := ["progress", "days", "assault", "assault_due", "starved"]


## True when the town's burg features hold walls or a citadel.
static func walled(repo: DataRepository, town: String) -> bool:
	var feats := String((repo.burgs.get(town, {}) as Dictionary).get("features", "")).split("|")
	return "walls" in feats or "citadel" in feats


## The id of `town`'s record, "" for none.
static func of_town(state: GameState, town: String) -> String:
	for id: String in state.sieges:
		if String(state.sieges[id]["town"]) == town:
			return id
	return ""


## The record the host's mind names (live, by reference), {} for none.
static func of_host(state: GameState, host: String) -> Dictionary:
	var mind: Dictionary = state.ai_hosts.get(host, {})
	return state.sieges.get(String(mind.get("siege_id", "")), {})


## The live record of the town a host in DEPLOYING or SIEGE besieges, opened
## if the town has none; the host joins its `hosts` and its mind names it.
## {} for any other host. `levy` false opens it with no militia (an old
## save's siege, already running: migrate).
static func ensure_for(repo: DataRepository, state: GameState, host: String, levy := true) -> Dictionary:
	var mind: Dictionary = state.ai_hosts.get(host, {})
	if String(mind.get("mode", "")) not in [EnemyAi.MODE_DEPLOYING, EnemyAi.MODE_SIEGE] \
			or String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN:
		return {}
	var town := String(mind.get("target_id", ""))
	var old := of_host(state, host)
	if not old.is_empty() and String(old["town"]) != town:
		leave(state, host)
		drop(state, host)
	var id := of_town(state, town)
	if id == "":
		id = _open(repo, state, town, SiegeSystem._kingdom_of(repo, state, host), levy)
	var rec: Dictionary = state.sieges[id]
	var hosts: Array = rec["hosts"]
	if not host in hosts:
		hosts.append(host)
		hosts.sort()
	mind["siege_id"] = id
	return rec


## The host leaves its town's record; the figures reset once no host is left.
## The mind keeps `siege_id` until the end is told (drop).
static func leave(state: GameState, host: String) -> void:
	for id: String in state.sieges.keys():
		var rec: Dictionary = state.sieges[id]
		var hosts: Array = rec["hosts"]
		if not host in hosts:
			continue
		hosts.erase(host)
		if hosts.is_empty():
			for f: String in FIGURES:
				rec[f] = 0
			_forget(state, id)


## The mind forgets its record; the record goes once no host is in it and no
## mind names it.
static func drop(state: GameState, host: String) -> void:
	var mind: Dictionary = state.ai_hosts.get(host, {})
	var id := String(mind.get("siege_id", ""))
	mind.erase("siege_id")
	_forget(state, id)


## Erases record `id` when no host is in it and no mind names it.
static func _forget(state: GameState, id: String) -> void:
	if not state.sieges.has(id) or not (state.sieges[id]["hosts"] as Array).is_empty():
		return
	for h: String in state.ai_hosts:
		if String(state.ai_hosts[h].get("siege_id", "")) == id:
			return
	state.sieges.erase(id)


## A besieger with no host (the crown's, player siege spec §5): the record of
## `town` with `units` (sorted) besieging for `attacker` and task `task_id`,
## opened if the town has none, joined (its units added) when its attacker is
## the same. Returns the id; "" when the town's record is another attacker's.
static func open_units(repo: DataRepository, state: GameState, town: String, attacker: String, units: Array,
		task_id: String) -> String:
	var id := of_town(state, town)
	if id == "":
		id = _open(repo, state, town, attacker)
		state.sieges[id]["task_id"] = task_id
	var rec: Dictionary = state.sieges[id]
	if String(rec["attacker"]) != attacker:
		return ""
	var mine: Array = rec["units"]
	for c: String in units:
		if not c in mine:
			mine.append(c)
	mine.sort()
	return id


## An old save's minds, converted once (spec §3): a mind in DEPLOYING or SIEGE
## before a town joins its record, which takes the larger of its own and the
## mind's progress, days, assault_due and starved (an armed `assault` is owed:
## assault_due 1, assault 0; a walled town's integrity is 1000 − progress); a
## mind in any other mode with a `siege_town` names a record of that town with
## no host, so its lift is still told once. Every mind loses the six old keys.
## A mind's occupation (`occupied`: cell string -> house before, and
## `occupied_house`) becomes GameState.occupations[its target town], `host`
## that host, `day` the day it converts (the capture's day was not saved), and
## the two keys go. Logged in military_migration["siege_record"]
## (and ["occupation"]); a second run changes nothing.
static func migrate(repo: DataRepository, state: GameState) -> void:
	var minds := 0
	var occupied := 0
	for h: String in EnemyAi.host_codes(state):
		var mind: Dictionary = state.ai_hosts[h]
		if mind.has("occupied") or mind.has("occupied_house"):
			var cells: Dictionary = mind.get("occupied", {})
			var town := String(mind.get("target_id", ""))
			if not cells.is_empty() and town != "" and not state.occupations.has(town):
				var by := SiegeSystem.host_label(repo, h)
				state.occupations[town] = {"town": town, "occupier": SiegeSystem._kingdom_of(repo, state, h),
					"from": repo.resolve_realm("player_realm"), "house": String(mind.get("occupied_house", "")),
					"host": h, "by": by, "day": state.absolute_day(), "cells": cells.duplicate()}
				occupied += 1
			mind.erase("occupied")
			mind.erase("occupied_house")
		if not LEGACY.any(func(k: String) -> bool: return mind.has(k)):
			continue
		var rec := ensure_for(repo, state, h, false)
		var town := String(mind.get("siege_town", ""))
		if not rec.is_empty():
			for pair: Array in [["progress", "siege_progress"], ["days", "siege_days"],
					["assault_due", "assault_due"], ["starved", "starved"]]:
				rec[pair[0]] = maxi(int(rec[pair[0]]), int(mind.get(pair[1], 0)))
			if int(mind.get("assault", 0)) == 1:
				rec["assault_due"] = 1
			rec["assault"] = 0
			if walled(repo, String(rec["town"])):
				rec["integrity"] = 1000 - int(rec["progress"])
			minds += 1
		elif town != "":
			var id := of_town(state, town)
			if id == "":
				id = _open(repo, state, town, SiegeSystem._kingdom_of(repo, state, h), false)
			mind["siege_id"] = id
			minds += 1
		for k: String in LEGACY:
			mind.erase(k)
	if occupied > 0:
		state.military_migration["occupation"] = {"day": state.absolute_day(), "towns": occupied,
			"reason": "occupations moved from ai_hosts to GameState.occupations (player siege spec §7)"}
	if minds > 0:
		state.military_migration["siege_record"] = {"day": state.absolute_day(), "minds": minds,
			"reason": "siege figures moved from ai_hosts to GameState.sieges (player siege spec §3)"}


## Opens `town`'s record for `attacker`; with `levy`, a foreign town's standing
## garrison wakes (TownMilitia.wake, the record's `woken`), then a town with no
## defenders raises its militia (TownMilitia.raise, the record's `militia`).
static func _open(repo: DataRepository, state: GameState, town: String, attacker: String, levy := true) -> String:
	state.siege_next_id += 1
	var id := "s%d" % state.siege_next_id
	state.sieges[id] = {"town": town, "attacker": attacker, "defender": SiegeSystem.holder_of(repo, state, town),
		"hosts": [], "units": [], "task_id": "", "opened_day": state.absolute_day(), "days": 0,
		"integrity": 1000 if walled(repo, town) else 0, "progress": 0, "assault": 0, "assault_due": 0,
		"starved": 0, "militia": [], "woken": []}
	if levy:
		TownMilitia.wake(repo, state, id)
		TownMilitia.raise(repo, state, id)
	return id
