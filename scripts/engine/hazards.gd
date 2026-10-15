class_name Hazards
extends RefCounted
## Hazards as STATE (spec 2026-10-07-war-room-p2-tactical-layer §2): the pack's
## zones seeded at a new reign, each ending by its kind's months
## (data/army/hazard_kinds.csv); what is known of one abroad (ruling 6); their
## endings as news. Pure; ids and cells in sorted order.

static var _index_key: Array = []
static var _index: Dictionary = {}   # cell -> [hazard id] (active or not)


static func kind_of(repo: DataRepository, kind: String) -> Dictionary:
	return repo.hazard_kinds.get(kind, {})


## One hazard per pack zone whose kind data/army/hazard_kinds.csv lists, from
## `start_tick` for its kind's months (0: no end of itself).
static func seed_pack(repo: DataRepository, state: GameState, start_tick: int) -> void:
	var rows: Dictionary = repo.world_table("society", "zones")
	var codes: Array = rows.keys()
	codes.sort()
	for code: String in codes:
		var row: Dictionary = rows[code]
		var k := kind_of(repo, String(row.get("type", "")))
		if k.is_empty():
			continue
		var cells: Array = []
		for c: String in String(row.get("cells", "")).split("|", false):
			if c.is_valid_int() and repo.cells.has(int(c)) and not cells.has(int(c)):
				cells.append(int(c))
		cells.sort()
		if cells.is_empty():
			continue
		var months := int(k["months"])
		add(state, code, String(row["type"]), String(row.get("label", code)), cells, start_tick,
			start_tick + months if months > 0 else -1, "pack")
	state.hazards_seeded = true


## A save written before the hazards were state: seeded once, at its own tick.
static func ensure(repo: DataRepository, state: GameState) -> void:
	if state != null and not state.hazards_seeded:
		seed_pack(repo, state, state.tick)


static func add(state: GameState, id: String, kind: String, label: String, cells: Array, start: int, end: int,
		source: String) -> void:
	state.hazards[id] = {"kind": kind, "label": label, "cells": cells.duplicate(), "start": start, "end": end,
		"source": source}
	state.hazards_rev += 1


## Ends a hazard now (an event's hook); its record stays.
static func end_now(state: GameState, id: String) -> void:
	if state.hazards.has(id):
		state.hazards[id]["end"] = state.tick
		state.hazards_rev += 1


static func is_active(state: GameState, id: String) -> bool:
	var h: Dictionary = state.hazards.get(id, {})
	if h.is_empty():
		return false
	var e := int(h["end"])
	return int(h["start"]) <= state.tick and (e < 0 or state.tick < e)


static func active_ids(state: GameState) -> Array:
	var out: Array = state.hazards.keys().filter(func(id: String) -> bool: return is_active(state, id))
	out.sort()
	return out


static func months_left(state: GameState, id: String) -> int:
	var e := int(state.hazards[id]["end"])
	return -1 if e < 0 else maxi(e - state.tick, 0)


## The active hazards holding a cell, id order.
static func at_cell(state: GameState, cell: int) -> Array:
	var key := [state.get_instance_id(), state.hazards_rev]
	if key != _index_key:
		_index = {}
		var ids: Array = state.hazards.keys()
		ids.sort()
		for id: String in ids:
			for c in state.hazards[id]["cells"]:
				if not _index.has(int(c)):
					_index[int(c)] = []
				(_index[int(c)] as Array).append(id)
		_index_key = key
	return (_index.get(cell, []) as Array).filter(func(id: String) -> bool: return is_active(state, id))


static func at_point(repo: DataRepository, state: GameState, at: Vector2) -> Array:
	var cell := MapEconomy.cell_at(repo, at)
	return [] if cell < 0 else at_cell(state, cell)


## Ruling 6: in the crown's realm every hazard is known; abroad only a public kind.
static func known(repo: DataRepository, state: GameState, id: String) -> bool:
	if Intel.dev_all:
		return true
	var h: Dictionary = state.hazards[id]
	if bool(kind_of(repo, String(h["kind"])).get("public", false)):
		return true
	var realm := repo.resolve_realm("player_realm")
	for c in h["cells"]:
		if MapOwnership.owner_of(repo, state, MapManors.province_of(repo, int(c), state)) == realm:
			return true
	return false


static func touches_province(repo: DataRepository, state: GameState, id: String, province: String) -> bool:
	for c in state.hazards[id]["cells"]:
		if MapManors.province_of(repo, int(c), state) == province:
			return true
	return false


## After the tick turns: the hazards ending this tick, as news, id order.
static func settle_month(repo: DataRepository, state: GameState) -> Array[String]:
	var news: Array[String] = []
	var ids: Array = state.hazards.keys()
	ids.sort()
	for id: String in ids:
		var h: Dictionary = state.hazards[id]
		if int(h["end"]) == state.tick and known(repo, state, id):
			news.append("The %s is over." % String(h["label"]))
	return news


## The month's toll on the crown's land regiments standing in an active hazard
## (spec §2.3): its kind's wounds_permille of the fit heads (whole, never past
## the headcount) and its morale, each reported with its reason. Code order.
static func settle_regiments(repo: DataRepository, state: GameState) -> Array[String]:
	var news: Array[String] = []
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code, state)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1" or not state.military_rosters.has(code):
			continue
		var entry: Dictionary = state.regiments[code]
		var name := String(reg.get("label", code))
		for id: String in at_point(repo, state, ArmySystem.position_of(repo, state, reg)):
			var marker := "hazard:" + code + ":" + id
			if int(state.conduct_marks.get(marker, -1)) == state.tick:
				continue
			var h: Dictionary = state.hazards[id]
			var k := kind_of(repo, String(h["kind"]))
			var fit := ArmySystem.fit_count(repo, state, code)
			@warning_ignore("integer_division")  # whole heads
			var lost := fit * int(k.get("wounds_permille", 0)) / 1000
			if lost > 0:
				var result := MilitaryRoster.transfer_units(repo, state, "hazard:%d:%s:%s" % [state.tick, code, id],
					[{"unit_code": code, "from": "fit", "to": "wounded", "count": lost}], "Hazard wounds: " + String(h["label"]))
				if result.has("error"):
					continue
				# ruling 6: a hazard we do not know is felt, never named
				var what := "the " + String(h["label"]) if known(repo, state, id) else "trouble in the country"
				news.append("The %s loses %d to %s." % [name, lost, what])
			state.conduct_marks[marker] = state.tick
			# the month's drift toward the supply mark gives back more than this
			# takes, so the regiment is HELD lower while it stands here: no news
			entry["morale"] = clampi(int(entry["morale"]) + int(k.get("morale", 0)), 0, 100)
	return news


## A march's pace through the active hazards at a point, per mille (1000 none).
static func pace_permille(repo: DataRepository, state: GameState, at: Vector2) -> int:
	var p := 1000
	for id: String in at_point(repo, state, at):
		var f := int(kind_of(repo, String(state.hazards[id]["kind"])).get("pace_permille", 1000))
		@warning_ignore("integer_division")  # whole per mille
		p = p * f / 1000
	return p
