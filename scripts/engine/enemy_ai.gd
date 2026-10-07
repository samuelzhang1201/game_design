class_name EnemyAi
extends RefCounted
## The raider realm's hosts (spec 2026-10-07-enemy-ai-and-battle-design §2-3).
## A host is a row of the pack's raid_hosts.csv: its regiments stand in
## GameState.foes (never in `regiments`) at the assembly point, and its mind is
## a row of GameState.ai_hosts. Pure and deterministic: no random number, no
## wall-clock; the commander is in the column, so a host's orders take effect
## at once, with no courier.

const MODE_ASSEMBLE := "ASSEMBLE"
const MODE_ADVANCE := "ADVANCE"
const MODE_SIEGE := "SIEGE"
const MODE_RAID := "RAID"
const MODE_HOLD := "HOLD"
const MODE_RETREAT := "RETREAT"
const MODE_WITHDRAW := "WITHDRAW"
## The modes in which a host's target is its own: another host counts it as
## taken (the overlap), and a host in one of them can be turned to RETREAT.
const TARGETING := [MODE_ADVANCE, MODE_SIEGE, MODE_RAID, MODE_HOLD]
## The modes of a host going home: it chooses nothing more.
const HOMEWARD := [MODE_RETREAT, MODE_WITHDRAW]

const KIND_TOWN := "town"
const KIND_MANOR := "manor"
const ROLE_MAIN := "main"
const ROLE_RESERVE := "reserve"

## repo instance id -> {burg code -> its manor cell}, built once per repository.
static var _town_cells: Dictionary = {}


## Puts `host` (a DataRepository.raid_hosts row) in the field: a foe for each of
## its regiments, in the same shape as a player regiment's state, standing at
## the host's assembly point (whole metres of the pack's measure) with no order,
## and a mind in ASSEMBLE. A regiment the pack does not have is left out.
static func spawn(repo: DataRepository, state: GameState, host: Dictionary) -> void:
	var code := String(host["host_code"])
	var start := ArmySystem.pack_to_metres(repo,
		Vector2(float(host.get("start_x", 0)), float(host.get("start_y", 0))))
	for rc: Variant in host["regiments"]:
		var reg := ArmySystem.regiment(repo, String(rc))
		if reg.is_empty():
			continue
		var st := ArmySystem.starting_state(repo, reg)
		st["x_m"] = start.x
		st["y_m"] = start.y
		st["dest_x_m"] = start.x
		st["dest_y_m"] = start.y
		st["order"] = ArmySystem.ORDER_STANDBY
		st["host"] = code
		state.foes[String(rc)] = st
	state.ai_hosts[code] = {"mode": MODE_ASSEMBLE, "target_kind": "", "target_id": "",
		"think_day": 0, "plunder": 0, "siege_progress": 0}


## One day of the hosts' minds, in host-code order (spec §3.1, §3.4, §3.5).
## A host assembled until its appear_day (the campaign's absolute day, the
## pack's row) sets out on that day's end: ASSEMBLE becomes ADVANCE. A host in
## the field then
##  1. eats a day (ArmySystem.eat_one on each of its foes; an assembling host is
##     fed at home);
##  2. in a TARGETING mode, turns to RETREAT when should_retreat gives a reason;
##  3. in ADVANCE, on reaching its target (arrival_mode), sits down to a SIEGE,
##     RAIDs, or WITHDRAWs;
##  4. sends every idle column of its own on: an advancing host's for the
##     target, a homeward host's for its start point (a battle halts a column;
##     the host, not a courier, moves it on).
## Returns the day's events: {type: "host_advance", host, day} and
## {type: "host_mode", host, mode, why, day} for every change of mode.
static func step_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	var today := state.absolute_day()
	for code: String in host_codes(state):
		var mind: Dictionary = state.ai_hosts[code]
		var mode := String(mind["mode"])
		if mode == MODE_ASSEMBLE:
			var row := _row_of(repo, code)
			if row.is_empty() or today < int(row["appear_day"]):
				continue
			mind["mode"] = MODE_ADVANCE
			events.append({"type": "host_advance", "host": code, "day": today})
			continue
		_eat(repo, state, code)
		if mode in TARGETING:
			var why := should_retreat(repo, state, code)
			if why != "":
				_set_mode(state, code, MODE_RETREAT, why, events)
				_march_host(repo, state, code)
				continue
		if mode == MODE_ADVANCE and String(mind["target_id"]) != "":
			var next := arrival_mode(repo, state, code)
			if next != "":
				_set_mode(state, code, next, _arrival_why(next), events)
		_march_host(repo, state, code)
	return events


## Every host's code, in dictionary order.
static func host_codes(state: GameState) -> Array:
	var codes: Array = state.ai_hosts.keys()
	codes.sort()
	return codes


## The regiment codes of a host's foes, in code order; [] for an unknown host.
static func regiments_of(state: GameState, host_code: String) -> Array:
	var out: Array = []
	for c: Variant in state.foes:
		if String((state.foes[c] as Dictionary).get("host", "")) == host_code:
			out.append(String(c))
	out.sort()
	return out


## The host's foes that can still fight: land regiments with fit men
## (ArmySystem.fit_heads > 0), in code order.
static func live_regiments(repo: DataRepository, state: GameState, host_code: String) -> Array:
	var out: Array = []
	for c: String in regiments_of(state, host_code):
		var reg := ArmySystem.regiment(repo, c)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		if ArmySystem.fit_heads(ArmySystem.headcount(repo, reg), state.foes[c]) > 0:
			out.append(c)
	return out


## The host's role (raid_hosts.csv: main / raider / reserve), "" for none.
static func role_of(repo: DataRepository, host_code: String) -> String:
	return String(_row_of(repo, host_code).get("role", ""))


## The host's doctrine: its role's row of data/ai_doctrines.csv.
static func doctrine_of(repo: DataRepository, host_code: String) -> Dictionary:
	return repo.ai_doctrines.get(role_of(repo, host_code), {})


## Where the host goes home to: its start point (raid_hosts.csv start_x /
## start_y, PACK px), in whole metres.
static func home_m(repo: DataRepository, host_code: String) -> Vector2i:
	var row := _row_of(repo, host_code)
	return ArmySystem.pack_to_metres(repo,
		Vector2(float(row.get("start_x", 0)), float(row.get("start_y", 0))))


## --- the score (spec §3.3) ---------------------------------------------------------

## A target's worth to a host, in whole gold:
## value x greed_permille / 1000 - distance_days x dist_cost
## - defence x caution_permille / 1000 - overlap.
static func score(value: int, distance_days: int, defence: int, overlap: int, doctrine: Dictionary) -> int:
	@warning_ignore("integer_division")  # whole gold, per-mille doctrine
	return value * int(doctrine.get("greed_permille", 0)) / 1000 \
		- distance_days * int(doctrine.get("dist_cost", 0)) \
		- defence * int(doctrine.get("caution_permille", 0)) / 1000 - overlap


## The overlap a target already another host's costs: `permille`
## (ai_target_overlap_permille) of its score before it; never negative, so a
## losing target is never made better by sharing.
static func overlap_of(score_base: int, permille: int) -> int:
	@warning_ignore("integer_division")  # whole gold
	return maxi(0, score_base) * permille / 1000


## A target's value to a doctrine: a manor's value, a town's plus the
## doctrine's town_bonus.
static func target_value(base_value: int, kind: String, doctrine: Dictionary) -> int:
	return base_value + (int(doctrine.get("town_bonus", 0)) if kind == KIND_TOWN else 0)


## The best of `cands` (candidates() rows, each with its distance_days) under
## `doctrine`: the highest score, ties to the earlier id (string order, then
## kind); a candidate whose "kind|id" is in `taken` pays the overlap. The row
## comes back with its "score"; {} when there is none or the best is not above 0.
static func rank(cands: Array, doctrine: Dictionary, taken: Dictionary, overlap_permille: int) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0
	for c: Dictionary in cands:
		var sc := _final(c, int(c["distance_days"]), doctrine, taken, overlap_permille)
		if best.is_empty() or _better(sc, c, best_score, best):
			best = c
			best_score = sc
	if best.is_empty() or best_score <= 0:
		return {}
	var out := best.duplicate()
	out["score"] = best_score
	return out


## The targets the OTHER hosts hold ("kind|id" -> true): each one in a
## TARGETING mode with a target, but a reserve (it follows, it does not take).
static func taken_by_others(repo: DataRepository, state: GameState, host_code: String) -> Dictionary:
	var out: Dictionary = {}
	for h: String in host_codes(state):
		if h == host_code or role_of(repo, h) == ROLE_RESERVE:
			continue
		var m: Dictionary = state.ai_hosts[h]
		if String(m["mode"]) in TARGETING and String(m["target_id"]) != "":
			out["%s|%s" % [m["target_kind"], m["target_id"]]] = true
	return out


## --- what a host sees and could take ------------------------------------------------

## The player's land regiments with fit men that this host sees: within
## ai_sight_km of any of its live regiments, in code order (spec §2: the fog is
## symmetric).
static func seen_by(repo: DataRepository, state: GameState, host_code: String) -> Array:
	var eyes: Array = []
	for c: String in live_regiments(repo, state, host_code):
		eyes.append(_at_m(repo, state, c))
	var sight := int(round(repo.bal("ai_sight_km") * 1000.0))
	var out: Array = []
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c: Variant in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		if ArmySystem.fit_heads(ArmySystem.headcount(repo, reg), state.regiments[code]) <= 0:
			continue
		var at := _at_m(repo, state, code)
		for e: Vector2i in eyes:
			if _within(e, at, sight):
				out.append(code)
				break
	return out


## The targets a host could choose (spec §3.3): every manor of a province the
## player's realm holds whose point lies within ai_target_reach_km of the host
## (its anchor, the slowest live column), as {kind, id, cell, value,
## distance_days, defence}, in id order. A manor with a town is the TOWN (kind
## "town", id the burg code, its value plus the doctrine's town_bonus); any
## other is kind "manor", id its cell id. value = MapManors.value_of_line,
## whole; distance_days = ArmySystem.march_days_between for the anchor;
## defence = the summed ArmySystem.power in the defend stance (the town's works,
## data/army_town_defence.csv, in it) of the player's regiments the host SEES
## (seen_by) that stand at the target. [] for a host with no live column.
static func candidates(repo: DataRepository, state: GameState, host_code: String) -> Array[Dictionary]:
	var out := _gather(repo, state, host_code)
	var anchor := anchor_of(repo, state, host_code)
	for c: Dictionary in out:
		c["distance_days"] = _days(repo, state, anchor, c)
	return out


## The live column a host's distances are measured for: the slowest that can
## move (least ArmySystem.day_step_m above 0, ties to the earlier code); "" for
## none.
static func anchor_of(repo: DataRepository, state: GameState, host_code: String) -> String:
	var best := ""
	var best_step := 0
	for c: String in live_regiments(repo, state, host_code):
		var step := ArmySystem.day_step_m(repo, state, c)
		if step > 0 and (best == "" or step < best_step):
			best = c
			best_step = step
	return best


## A target's point in whole metres: a town's burg, a manor's cell centre.
static func target_point_m(repo: DataRepository, kind: String, id: String) -> Vector2i:
	if kind == KIND_TOWN:
		var b: Dictionary = repo.burgs.get(id, {})
		return ArmySystem.pack_to_metres(repo, Vector2(float(b.get("x", 0)), float(b.get("y", 0))))
	var cell := int(id)
	if not repo.cells.has(cell):
		return Vector2i.ZERO
	return ArmySystem.pack_to_metres(repo, MapTerrain.cell_center(repo, repo.cells[cell]))


## A target's manor cell: a manor's own, a town's the manor that carries its
## burg (political/manors.csv burg_code); -1 for none.
static func target_cell(repo: DataRepository, _state: GameState, kind: String, id: String) -> int:
	if kind != KIND_TOWN:
		return int(id) if repo.manors.has(int(id)) else -1
	var key := repo.get_instance_id()
	if not _town_cells.has(key):
		var map: Dictionary = {}
		var ids: Array = repo.manors.keys()
		ids.sort()
		for cell: int in ids:
			var b := MapManors.burg_of(repo, cell)
			if b != "" and not map.has(b):
				map[b] = cell
		_town_cells[key] = map
	return int((_town_cells[key] as Dictionary).get(id, -1))


## True while the player's realm holds the target: a town's province
## (MapOwnership), a manor's province as it stands now (MapManors.province_of).
static func target_held(repo: DataRepository, state: GameState, kind: String, id: String) -> bool:
	var player := repo.resolve_realm("player_realm")
	if kind == KIND_TOWN:
		var b: Dictionary = repo.burgs.get(id, {})
		return not b.is_empty() and MapOwnership.owner_of(repo, state, String(b.get("province_code", ""))) == player
	var cell := int(id)
	if not repo.manors.has(cell):
		return false
	return MapOwnership.owner_of(repo, state, MapManors.province_of(repo, cell, state)) == player


## Of `codes` (player regiments), those standing at the target: within
## battle_contact_km of its point, or — a town — in its reach (ArmySystem.town_of).
static func defenders_of(repo: DataRepository, state: GameState, kind: String, id: String, codes: Array) -> Array:
	var at := target_point_m(repo, kind, id)
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	var out: Array = []
	for c: Variant in codes:
		var code := String(c)
		if _within(_at_m(repo, state, code), at, reach) \
				or (kind == KIND_TOWN and ArmySystem.town_of(repo, ArmySystem.regiment(repo, code), state) == id):
			out.append(code)
	return out


## --- choosing (spec §3.2-3.3) -------------------------------------------------------

## A host's decision. Only a host in ADVANCE thinks, and only when it has no
## target or ai_think_days have passed since its last decision (think_day);
## between, it keeps its target, so the player can read its intent. A reserve
## takes the main host's target (WITHDRAWs when the main host goes home); any
## other host takes rank's best of its candidates, a target another host holds
## paying the overlap (ai_target_overlap_permille). With no target worth more
## than 0 it WITHDRAWs. A chosen target sends every column of the host marching
## for it at once (no courier); a withdrawal sends it home.
static func think(repo: DataRepository, state: GameState, host_code: String) -> void:
	if not state.ai_hosts.has(host_code):
		return
	var mind: Dictionary = state.ai_hosts[host_code]
	if String(mind["mode"]) != MODE_ADVANCE:
		return
	var today := state.absolute_day()
	if String(mind["target_id"]) != "" and today - int(mind["think_day"]) < int(repo.bal("ai_think_days")):
		return
	mind["think_day"] = today
	var pick: Dictionary = {}
	if role_of(repo, host_code) == ROLE_RESERVE:
		var lead := _main_mind(repo, state)
		if lead.is_empty():
			return                      # no main host out yet: the reserve waits
		if String(lead["mode"]) in HOMEWARD:
			pick = {}
		elif String(lead["target_id"]) == "":
			return
		else:
			pick = {"kind": String(lead["target_kind"]), "id": String(lead["target_id"])}
	else:
		pick = _choose(repo, state, host_code)
	if pick.is_empty():
		mind["target_kind"] = ""
		mind["target_id"] = ""
		mind["mode"] = MODE_WITHDRAW
	else:
		mind["target_kind"] = String(pick["kind"])
		mind["target_id"] = String(pick["id"])
	_march_host(repo, state, host_code)


## Every host's decision of the day: the hosts with targets of their own in
## code order, then the reserves, so a reserve follows today's main target.
static func think_day(repo: DataRepository, state: GameState) -> void:
	var reserves: Array = []
	for h: String in host_codes(state):
		if role_of(repo, h) == ROLE_RESERVE:
			reserves.append(h)
		else:
			think(repo, state, h)
	for h: String in reserves:
		think(repo, state, h)


## --- engage and retreat (spec §3.4) ---------------------------------------------------

## Whether the host takes a fight with the player regiments it sees: its odds
## (BattleSystem.odds_permille of its side_power attacking against theirs
## defending, each against the other's height) at least the doctrine's
## engage_odds_permille. Nothing seen is a fight it takes; a host with no live
## column takes none.
static func engages(repo: DataRepository, state: GameState, host_code: String, seen_player_codes: Array) -> bool:
	var live := live_regiments(repo, state, host_code)
	if live.is_empty():
		return false
	var stance := func(c: String) -> String: return BattleSystem.stance_of(state, c)
	var att := BattleSystem.side_power(repo, state, live, stance, true, seen_player_codes)
	var def := BattleSystem.side_power(repo, state, seen_player_codes, stance, false, live)
	return BattleSystem.odds_permille(att, def) >= int(doctrine_of(repo, host_code).get("engage_odds_permille", 0))


## Why the host turns for home, "" when it holds on: a column of it fell back
## beaten from a battle (`disengaging`, BattleSystem); its live columns' mean
## morale below the doctrine's retreat_morale; or its hungriest live column's
## days in hand (ArmySystem.days_in_hand) below ai_retreat_supply_days.
static func should_retreat(repo: DataRepository, state: GameState, host_code: String) -> String:
	for c: String in regiments_of(state, host_code):
		if int((state.foes[c] as Dictionary).get("disengaging", 0)) == 1:
			return "beaten: %s fell back from the battle" % c
	var live := live_regiments(repo, state, host_code)
	if live.is_empty():
		return ""
	var morale := 0
	var least := -1
	for c: String in live:
		var e: Dictionary = state.foes[c]
		morale += int(e["morale"])
		var days := ArmySystem.days_in_hand(int(e["supplies"]),
			ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), state))
		least = days if least < 0 else mini(least, days)
	@warning_ignore("integer_division")  # whole points
	morale /= live.size()
	var floor_morale := int(doctrine_of(repo, host_code).get("retreat_morale", 0))
	if morale < floor_morale:
		return "morale %d below %d" % [morale, floor_morale]
	var floor_days := int(repo.bal("ai_retreat_supply_days"))
	if least < floor_days:
		return "supplies for %d days, below %d" % [least, floor_days]
	return ""


## --- arrival (Ruling 5) --------------------------------------------------------------

## What an ADVANCING host does now, "" for nothing new: once every live column
## of it stands within battle_contact_km of the target's point, not marching and
## in no battle — WITHDRAW when the player no longer holds the target; SIEGE at
## a town a player regiment GARRISONS (SupplySystem.garrisoned_in); nothing
## while a player regiment it sees stands at the target (contact fights it,
## BattleSystem); else RAID (an open manor, or a town with no garrison).
static func arrival_mode(repo: DataRepository, state: GameState, host_code: String) -> String:
	var mind: Dictionary = state.ai_hosts[host_code]
	var kind := String(mind["target_kind"])
	var id := String(mind["target_id"])
	var live := live_regiments(repo, state, host_code)
	if id == "" or live.is_empty():
		return ""
	var at := target_point_m(repo, kind, id)
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	for c: String in live:
		if String(state.foes[c].get("order", "")) == ArmySystem.ORDER_MARCH \
				or not BattleSystem.battle_of(state, c).is_empty() or not _within(_at_m(repo, state, c), at, reach):
			return ""
	if not target_held(repo, state, kind, id):
		return MODE_WITHDRAW
	if kind == KIND_TOWN:
		var codes: Array = state.regiments.keys()
		codes.sort()
		for c: Variant in codes:
			if SupplySystem.garrisoned_in(repo, state, String(c)) == id:
				return MODE_SIEGE
	if not defenders_of(repo, state, kind, id, seen_by(repo, state, host_code)).is_empty():
		return ""
	return MODE_RAID


## --- inside ------------------------------------------------------------------------

static func _row_of(repo: DataRepository, host_code: String) -> Dictionary:
	for row: Dictionary in repo.raid_hosts:
		if String(row["host_code"]) == host_code:
			return row
	return {}


## The first main host's mind (code order), {} when none is out of ASSEMBLE.
static func _main_mind(repo: DataRepository, state: GameState) -> Dictionary:
	for h: String in host_codes(state):
		if role_of(repo, h) == ROLE_MAIN and String(state.ai_hosts[h]["mode"]) != MODE_ASSEMBLE:
			return state.ai_hosts[h]
	return {}


static func _set_mode(state: GameState, host_code: String, mode: String, why: String, events: Array) -> void:
	state.ai_hosts[host_code]["mode"] = mode
	events.append({"type": "host_mode", "host": host_code, "mode": mode, "why": why,
		"day": state.absolute_day()})


static func _arrival_why(mode: String) -> String:
	match mode:
		MODE_SIEGE:
			return "reached a garrisoned town"
		MODE_RAID:
			return "reached an undefended target"
	return "the target is no longer the enemy's"


## A day's meal for every foe of the host (ArmySystem.eat_one).
static func _eat(repo: DataRepository, state: GameState, host_code: String) -> void:
	for c: String in regiments_of(state, host_code):
		var reg := ArmySystem.regiment(repo, c)
		if not reg.is_empty():
			ArmySystem.eat_one(repo, state, reg, state.foes[c])


## Sends the host's columns where its mode wants them: ADVANCE for its target,
## RETREAT / WITHDRAW for its start point (a column falling back from a battle
## too: the host owns its retreat); any other mode, or ADVANCE with no target,
## leaves them. A column in a battle is never ordered (an order would take it
## out of the fight); one with no fit man cannot move; one already there stays.
static func _march_host(repo: DataRepository, state: GameState, host_code: String) -> void:
	var mind: Dictionary = state.ai_hosts[host_code]
	var mode := String(mind["mode"])
	var to := Vector2i.ZERO
	var homeward := mode in HOMEWARD
	if homeward:
		to = home_m(repo, host_code)
	elif mode == MODE_ADVANCE and String(mind["target_id"]) != "":
		to = target_point_m(repo, String(mind["target_kind"]), String(mind["target_id"]))
	else:
		return
	for c: String in live_regiments(repo, state, host_code):
		var e: Dictionary = state.foes[c]
		if not BattleSystem.battle_of(state, c).is_empty():
			continue
		if not homeward and int(e.get("disengaging", 0)) == 1:
			continue
		if int(e["x_m"]) == to.x and int(e["y_m"]) == to.y:
			continue
		e["dest_x_m"] = to.x
		e["dest_y_m"] = to.y
		e["order"] = ArmySystem.ORDER_MARCH


## A regiment's place in whole metres: its stored state's, else the pack's.
static func _at_m(repo: DataRepository, state: GameState, code: String) -> Vector2i:
	var e: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
	if e.has("x_m"):
		return Vector2i(int(e["x_m"]), int(e["y_m"]))
	return ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)))


## True when two points are no more than `metres` apart (whole numbers).
static func _within(a: Vector2i, b: Vector2i, metres: int) -> bool:
	var dx := int(b.x) - int(a.x)
	var dy := int(b.y) - int(a.y)
	return dx * dx + dy * dy <= metres * metres


## The candidates without their distances (distance_days -1), in id order.
static func _gather(repo: DataRepository, state: GameState, host_code: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var anchor := anchor_of(repo, state, host_code)
	if anchor == "":
		return out
	var from := _at_m(repo, state, anchor)
	var reach := int(round(repo.bal("ai_target_reach_km") * 1000.0))
	var doctrine := doctrine_of(repo, host_code)
	var seen := seen_by(repo, state, host_code)
	var player := repo.resolve_realm("player_realm")
	for prov: String in MapOwnership.provinces_of(repo, state, player):
		for cell: int in MapManors.manors_of_province(repo, prov, state):
			var town := MapManors.burg_of(repo, cell)
			var kind := KIND_TOWN if town != "" else KIND_MANOR
			var id := town if town != "" else str(cell)
			var at := target_point_m(repo, kind, id)
			if not _within(from, at, reach) or not target_held(repo, state, kind, id):
				continue
			var base := int(round(MapManors.value_of_line(repo, state, cell, RealmEconomy.line_of(repo, state, cell))))
			var defence := 0
			for p: String in defenders_of(repo, state, kind, id, seen):
				defence += ArmySystem.power(repo, state, p, "defend")
			out.append({"kind": kind, "id": id, "cell": cell, "value": target_value(base, kind, doctrine),
				"distance_days": -1, "defence": defence})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _key(a) < _key(b))
	return out


## Whole days for the anchor to march to a candidate's point.
static func _days(repo: DataRepository, state: GameState, anchor: String, c: Dictionary) -> int:
	if anchor == "":
		return 0
	var to := target_point_m(repo, String(c["kind"]), String(c["id"]))
	return ArmySystem.march_days_between(repo, state, anchor,
		ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, anchor)), ArmySystem.metres_to_pack(repo, to))


## A candidate's score with the overlap when another host holds it.
static func _final(c: Dictionary, days: int, doctrine: Dictionary, taken: Dictionary, permille: int) -> int:
	var base := score(int(c["value"]), days, int(c["defence"]), 0, doctrine)
	if not taken.has("%s|%s" % [c["kind"], c["id"]]):
		return base
	return score(int(c["value"]), days, int(c["defence"]), overlap_of(base, permille), doctrine)


static func _key(c: Dictionary) -> String:
	return "%s|%s" % [c["id"], c["kind"]]


static func _better(sc: int, c: Dictionary, best_score: int, best: Dictionary) -> bool:
	return sc > best_score or (sc == best_score and _key(c) < _key(best))


## rank over the host's candidates, the march days walked only where they can
## matter: the candidates in order of their score at no distance (an upper
## bound, as distance only costs and the overlap only grows with the score),
## stopping at the first that cannot reach the best found. The same pick as
## rank(candidates(...)), for a fraction of the walks.
static func _choose(repo: DataRepository, state: GameState, host_code: String) -> Dictionary:
	var cands := _gather(repo, state, host_code)
	var doctrine := doctrine_of(repo, host_code)
	var taken := taken_by_others(repo, state, host_code)
	var permille := int(repo.bal("ai_target_overlap_permille"))
	var anchor := anchor_of(repo, state, host_code)
	var bound: Dictionary = {}
	for c: Dictionary in cands:
		bound[_key(c)] = _final(c, 0, doctrine, taken, permille)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _better(int(bound[_key(a)]), a, int(bound[_key(b)]), b))
	var best: Dictionary = {}
	var best_score := 0
	for c: Dictionary in cands:
		if not best.is_empty() and int(bound[_key(c)]) < best_score:
			break
		c["distance_days"] = _days(repo, state, anchor, c)
		var sc := _final(c, int(c["distance_days"]), doctrine, taken, permille)
		if best.is_empty() or _better(sc, c, best_score, best):
			best = c
			best_score = sc
	if best.is_empty() or best_score <= 0:
		return {}
	return best
