class_name SiegeRecord
extends RefCounted
## One saved record per besieged town (spec docs/superpowers/specs/
## 2026-11-18-player-siege-design.md §3): GameState.sieges[id], id "s<n>" from
## GameState.siege_next_id. Fields, whole numbers and strings: town, attacker,
## defender (kingdom codes; the defender is the town's holder when it opened),
## hosts (the AI hosts in it, code order), task_id ("" for the AI), opened_day,
## days, integrity (0..1000, set at open: 1000 for walls or a citadel, else 0),
## progress (0..1000, transitional: step 10 removes it), assault (1: the next
## day's battles may storm), assault_due (an assault owed), starved (1: the
## hunger was told). A host's mind keeps only `siege_id`, set until the
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
## {} for any other host.
static func ensure_for(repo: DataRepository, state: GameState, host: String) -> Dictionary:
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
		id = _open(repo, state, town, SiegeSystem._kingdom_of(repo, state, host))
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
	var rec := of_host(state, host)
	if rec.is_empty():
		return
	(rec["hosts"] as Array).erase(host)
	if (rec["hosts"] as Array).is_empty():
		for f: String in FIGURES:
			rec[f] = 0


## The mind forgets its record; the record goes once no host is in it and no
## mind names it.
static func drop(state: GameState, host: String) -> void:
	var mind: Dictionary = state.ai_hosts.get(host, {})
	var id := String(mind.get("siege_id", ""))
	mind.erase("siege_id")
	if id == "" or not state.sieges.has(id) or not (state.sieges[id]["hosts"] as Array).is_empty():
		return
	for h: String in state.ai_hosts:
		if String(state.ai_hosts[h].get("siege_id", "")) == id:
			return
	state.sieges.erase(id)


static func _open(repo: DataRepository, state: GameState, town: String, attacker: String) -> String:
	state.siege_next_id += 1
	var id := "s%d" % state.siege_next_id
	var prov := String((repo.burgs.get(town, {}) as Dictionary).get("province_code", ""))
	state.sieges[id] = {"town": town, "attacker": attacker, "defender": MapOwnership.owner_of(repo, state, prov),
		"hosts": [], "task_id": "", "opened_day": state.absolute_day(), "days": 0,
		"integrity": 1000 if walled(repo, town) else 0, "progress": 0, "assault": 0, "assault_due": 0,
		"starved": 0}
	return id
