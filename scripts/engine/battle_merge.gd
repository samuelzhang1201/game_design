class_name BattleMerge
extends RefCounted
## Compatible live battles join on actual close group contact or lawful
## ranged fire across their fronts. The
## lower id survives (the other stays an alias in `GameState.battle_aliases`),
## unless only the other holds a town: an assault stays linked to its town.
## Units are unioned by allegiance; every per-unit and accumulated record is
## carried over without re-running anything. The absorbed battle's side-level
## state is kept verbatim in `survivor.sources[<id>]` until the unified
## commander and source-scoped terms land (P4.4e2/e3).

## Side-level keys of the absorbed battle that are NOT folded into the survivor:
## they stay under `sources` (the survivor's own stay as they are).
const SOURCE_KEYS: Array[String] = ["parley", "commanders", "commander_nominees", "commander_nominee_seq", "actions", "formations",
	"routed_side", "inspire_cooldown", "inspire_until", "start_day", "place_x_m", "place_y_m"]


## The day's merges, in id order, repeated until none is left (a survivor is
## checked again against later battles). Returns one `merge` event per merge.
static func day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	var again := true
	while again:
		again = false
		var ids: Array = state.battles.map(func(b: Dictionary) -> int: return int(b["id"]))
		ids.sort()
		for i: int in ids.size():
			for j: int in range(i + 1, ids.size()):
				var a := BattleSystem.battle_by_id(state, int(ids[i]))
				var b := BattleSystem.battle_by_id(state, int(ids[j]))
				if mergeable(repo, state, a, b):
					events.append(_merge(repo, state, a, b))
					again = true
					break
			if again:
				break
	return events


## True when `a` and `b` (a.id < b.id) may merge: neither mid-round, not two
## towns, every side occupied, and an actual contact between compatible allegiances.
static func mergeable(repo: DataRepository, state: GameState, a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or int(a["id"]) == int(b["id"]):
		return false
	if String(a.get("town", "")) != "" and String(b.get("town", "")) != "":
		return false
	for battle: Dictionary in [a, b]:
		if not (battle.get("pending_round", {}) as Dictionary).is_empty():
			return false
		for side: String in BattleSystem.SIDES:
			if (battle[side] as Array).is_empty():
				return false
	if not _compatible(repo, state, a, b):
		return false
	for ua: String in _units(a):
		for ub: String in _units(b):
			if ArmySystem.is_foe(state, ua) == ArmySystem.is_foe(state, ub):
				continue
			var reach := BattleGroups.contact_reach(repo, state, a, ua, ub, b)
			for ga: Dictionary in a.get("groups", {}).get(ua, []):
				for gb: Dictionary in b.get("groups", {}).get(ub, []):
					var dx := int(ga["x_m"]) - int(gb["x_m"])
					var dy := int(ga["y_m"]) - int(gb["y_m"])
					if int(ga["count"]) > 0 and int(gb["count"]) > 0 and dx * dx + dy * dy <= reach * reach:
						return true
	return _ranged_contact(repo, state, a, b) or _ranged_contact(repo, state, b, a)


## The allegiance union must preserve every pair's existing realm hostility.
static func _compatible(repo: DataRepository, state: GameState, a: Dictionary, b: Dictionary) -> bool:
	var relations := {"player": repo.resolve_realm("player_realm"), "raider": repo.resolve_realm("raider_realm"),
		"diplomacy": repo.world_table("political", "diplomacy"), "hostile": {}}
	for ua: String in _units(a):
		for ub: String in _units(b):
			var ra := ArmySystem.realm_of(repo, ua, state)
			var rb := ArmySystem.realm_of(repo, ub, state)
			if ra == "" or rb == "" or ArmySystem._hostile(relations, ra, rb) != (ArmySystem.is_foe(state, ua) != ArmySystem.is_foe(state, ub)):
				return false
	return true


static func _ranged_contact(repo: DataRepository, state: GameState, source: Dictionary, other: Dictionary) -> bool:
	for code: String in _units(source):
		if BattleRanged.share(repo, state, code) > 0 and BattleSystem.unit_action(repo, state, source, code)["kind"] == "attack" \
				and int(BattleRanged.counts(repo, state, source, code, "", other)["firing"]) > 0:
			return true
	return false


static func _units(battle: Dictionary) -> Array:
	var out: Array = []
	for side: String in BattleSystem.SIDES:
		out.append_array(battle[side])
	out.sort()
	return out


## Folds the later battle into the survivor (see the header) and returns the event.
static func _merge(repo: DataRepository, state: GameState, a: Dictionary, b: Dictionary) -> Dictionary:
	var survivor := b if String(b.get("town", "")) != "" and String(a.get("town", "")) == "" else a
	var gone := a if survivor == b else b
	var sid := int(survivor["id"])
	var gid := int(gone["id"])
	BattleRules.ensure_parties(survivor)   # P4.4e3: each agreement keeps its own parties
	BattleRules.ensure_parties(gone)
	# the absorbed side-level state, verbatim, plus whatever it had already absorbed
	if not survivor.has("sources"):
		survivor["sources"] = {}
	var source := {}
	for key: String in SOURCE_KEYS:
		if gone.has(key):
			source[key] = _copy(gone[key])
	survivor.sources[str(gid)] = source
	for key: String in gone.get("sources", {}):
		if not survivor.sources.has(key):
			survivor.sources[key] = _copy(gone.sources[key])
	var side_map := {}   # absorbed side -> the survivor side its units fall on, by allegiance
	for side: String in BattleSystem.SIDES:
		for code: String in gone[side]:
			var into := BattleSystem._side_for(state, survivor, code)
			if into != "":
				side_map[side] = into
				break
	# union by allegiance: survivor members first, then the absorbed in their old order
	var moved: Array = []
	for side: String in BattleSystem.SIDES:
		for code: String in gone[side]:
			var into := BattleSystem._side_for(state, survivor, code)
			if into != "" and not code in survivor[into]:
				survivor[into].append(code)
				moved.append(code)
	for code: String in moved:   # an absorbed unit keeps the formation it stood in
		var side_old := BattleRules.side_of(gone, code)
		if not (gone.get("unit_formations", {}) as Dictionary).has(code) and gone.get("formations", {}).has(side_old):
			if not survivor.has("unit_formations"):
				survivor["unit_formations"] = {}
			survivor.unit_formations[code] = _copy(gone.formations[side_old])
	for side: String in BattleSystem.SIDES:
		survivor[side] = _dedupe(survivor[side])
	_fold_dicts(survivor, gone, ["personnel_entries", "unit_entries", "unit_formations", "reserves",
		"abandoned_supplies", "event_checks", "groups", "group_facing", "group_anchor_m"])
	_fold_lists(survivor, gone, ["reinforcement_evidence", "withdrawal_costs", "event_modifiers", "event_reinforcements",
		"event_reinforcements_consumed", "report_events", "family_changes"])
	for key: String in ["personnel_entries", "unit_entries"]:   # the side an entry names is the merged battle's
		for id: String in survivor.get(key, {}):
			var entry: Dictionary = survivor[key][id]
			var side := BattleRules.side_of(survivor, String(entry.get("unit_code", entry.get("code", ""))))
			if side != "":
				entry["side"] = side
	for key: String in ["reinforcement_evidence"]:
		for entry: Dictionary in survivor.get(key, []):
			var side := BattleRules.side_of(survivor, String(entry.get("unit", "")))
			if side != "":
				entry["side"] = side
	for id: String in survivor.get("abandoned_supplies", {}):
		var cache: Dictionary = survivor.abandoned_supplies[id]
		var side := BattleRules.side_of(survivor, String(cache.get("unit", "")))
		if side != "":
			cache["side"] = side
	survivor["start_day"] = mini(int(survivor.get("start_day", 0)), int(gone.get("start_day", 0)))
	survivor["rounds"] = maxi(int(survivor.get("rounds", 0)), int(gone.get("rounds", 0)))
	if survivor.has("last_resolved_day") or gone.has("last_resolved_day"):
		survivor["last_resolved_day"] = maxi(int(survivor.get("last_resolved_day", -1)), int(gone.get("last_resolved_day", -1)))
	if survivor.has("deployed_day") or gone.has("deployed_day"):
		survivor["deployed_day"] = maxi(int(survivor.get("deployed_day", -1)), int(gone.get("deployed_day", -1)))
	_remap_warrants(state, gid, side_map)
	# aliases: the absorbed id, and everything that already pointed at it, resolve to the survivor
	for key: String in state.battle_aliases.keys():
		if int(state.battle_aliases[key]) == gid:
			state.battle_aliases[key] = sid
	state.battle_aliases[str(gid)] = sid
	state.battles = state.battles.filter(func(x: Dictionary) -> bool: return int(x["id"]) != gid)
	for token: String in state.battle_events:   # offers made for the absorbed battle belong to the survivor now
		var saved: Dictionary = state.battle_events[token]
		if int(saved.get("battle_id", -1)) == gid:
			saved["battle_id"] = sid
	BattleCommand.unify(repo, state, survivor, source, side_map)
	var facings: Dictionary = survivor.get("group_facing", {}).duplicate()
	BattleGroups.refresh(repo, state, survivor)
	survivor["group_facing"].merge(facings, true)
	var event := {"kind": "merge", "battle_id": sid, "absorbed": gid,
		"reason": "Fronts touched: battle %d joined battle %d on the same field." % [gid, sid]}
	BattleReport.note(survivor, [event])
	return event


## P4.4e4: a pending side warrant of the absorbed battle (or of one it had absorbed) now
## names the survivor side its units stand on; id, cost and courier are untouched. The
## first remap's `from_side` is kept, so a retry with the original request still matches.
static func _remap_warrants(state: GameState, gid: int, side_map: Dictionary) -> void:
	var ids: Array = state.battle_orders.keys()
	ids.sort()
	for id: String in ids:
		var record: Dictionary = state.battle_orders[id]
		var request: Dictionary = record.get("request", {})
		if record.get("status", "") != "pending" or BattleSystem.canonical(state, int(request.get("battle_id", -1))) != gid:
			continue
		var from := String(request.get("side", ""))
		var into := String(side_map.get(from, from))
		if into == from:
			continue
		request["side"] = into
		var note: Dictionary = record.get("merge_remap", {"from_battle": int(request["battle_id"]), "from_side": from})
		note["to_side"] = into
		note["reason"] = "Battle %d joined another field: the warrant's side %s is now side %s." % [gid, from, into]
		record["merge_remap"] = note


static func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


## `list` without repeats, first occurrence kept.
static func _dedupe(list: Array) -> Array:
	var out: Array = []
	for v: Variant in list:
		if not v in out:
			out.append(v)
	return out


## Dictionary keys of `gone` the survivor lacks are copied; the survivor's own stand.
static func _fold_dicts(survivor: Dictionary, gone: Dictionary, keys: Array) -> void:
	for key: String in keys:
		if not gone.has(key):
			continue
		if not survivor.has(key):
			survivor[key] = {}
		var ids: Array = (gone[key] as Dictionary).keys()
		ids.sort()
		for id: Variant in ids:
			if not (survivor[key] as Dictionary).has(id):
				survivor[key][id] = _copy(gone[key][id])


## List entries of `gone` the survivor lacks are appended in order.
static func _fold_lists(survivor: Dictionary, gone: Dictionary, keys: Array) -> void:
	for key: String in keys:
		if not gone.has(key):
			continue
		if not survivor.has(key):
			survivor[key] = []
		for v: Variant in gone[key]:
			if not v in survivor[key]:
				survivor[key].append(_copy(v))
