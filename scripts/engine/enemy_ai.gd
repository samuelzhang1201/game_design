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
const MODE_DEPLOYING := "DEPLOYING"
const MODE_SIEGE := "SIEGE"
const MODE_RAID := "RAID"
const MODE_HOLD := "HOLD"
const MODE_RETREAT := "RETREAT"
const MODE_WITHDRAW := "WITHDRAW"
## The modes in which a host's target is its own: another host counts it as
## taken (the overlap), and a host in one of them can be turned to RETREAT.
const TARGETING := [MODE_ADVANCE, MODE_DEPLOYING, MODE_SIEGE, MODE_RAID, MODE_HOLD]
## The modes of a host going home: it chooses nothing more.
const HOMEWARD := [MODE_RETREAT, MODE_WITHDRAW]

## arrival_mode's answer for a host reaching a town another host besieges.
const ARRIVAL_RETHINK := "RETHINK"
## arrival_mode's answer for a target the crown no longer holds: drop it and
## choose again the same day (think_day 0), never home for good on that alone.
const ARRIVAL_LOST := "LOST"

const KIND_TOWN := "town"
const KIND_MANOR := "manor"
const ROLE_MAIN := "main"
const ROLE_RESERVE := "reserve"

## "repo instance id|map id" -> {burg code -> its manor cell}, built once per
## repository and map.
static var _town_cells: Dictionary = {}

## Drop the per-repo town cells (DataRepository.forget_derived).
static func forget() -> void:
	_town_cells.clear()



## Puts `host` (a DataRepository.raid_hosts row) in the field: a foe for each of
## its UNITS (host_units), in the same shape as a player unit's state and keyed
## by the unit's code, standing at the host's assembly point (whole metres of
## the pack's measure) with no order — the first unit ON it, the rest spread
## round it on the camp lattice in code order (ArmyGround.free_slot: no two
## within army_clearance_m; stacked on it when that is 0) — and a mind in ASSEMBLE. A unit leaves its
## camp: a seat it held is emptied and refilled from the camp it left
## (ArmyGround.refill), so no foe holds a town. Run it after the split (the
## roster in `state`).
static func spawn(repo: DataRepository, state: GameState, host: Dictionary) -> void:
	var code := String(host["host_code"])
	var start := ArmySystem.pack_to_metres(repo,
		Vector2(float(host.get("start_x", 0)), float(host.get("start_y", 0))))
	var taken := ArmyGround.new_taken(repo)
	var first := true
	for unit: String in host_units(repo, state, host):
		var reg := ArmySystem.regiment(repo, unit, state)
		var at := start
		if ArmyGround.clearance_on(repo):
			if not first:
				var arm := MapObjects.regiment_arm(repo, reg)
				at = ArmyGround.free_slot(repo, start, arm, taken, "")
				if at == ArmyGround.NONE:
					at = ArmyGround.free_slot(repo, start, arm, taken, "", true)
				if at == ArmyGround.NONE:
					at = start
			ArmyGround.take(taken, at, ArmyGround.unit_radius(repo, reg))
			first = false
		# Initial rations use the live personnel and actual assembly terrain.
		var opening_reg := reg.duplicate()
		var opening_px := ArmySystem.metres_to_pack(repo, at)
		opening_reg["x"] = opening_px.x
		opening_reg["y"] = opening_px.y
		var st := ArmySystem.starting_state(repo, opening_reg, state)
		st["x_m"] = at.x
		st["y_m"] = at.y
		st["dest_x_m"] = at.x
		st["dest_y_m"] = at.y
		st["order"] = ArmySystem.ORDER_STANDBY
		st["camp_town"] = ""
		st["host"] = code
		state.foes[unit] = st
	var towns := state.town_seat.keys()
	towns.sort()
	for town: String in towns:
		if ArmySystem.is_foe(state, String(state.town_seat[town])):
			state.town_seat.erase(town)
			ArmyGround.refill(repo, state, town)
	state.ai_hosts[code] = {"mode": MODE_ASSEMBLE, "target_kind": "", "target_id": "",
		"think_day": 0, "plunder": 0, "siege_progress": 0}


## The roster units a raid_hosts row raises, in code order: each entry of its
## `regiments` (the pack's regiment codes of the raider realm) is that unit
## when the roster has one by the code, else every LAND unit split from it
## (`parent_code`, ArmySplit: its foot, archers and horse; its guns are in its
## kingdom's royal train, which no host takes). An entry the roster does not
## know is left out; no unit is raised twice.
static func host_units(repo: DataRepository, state: GameState, host: Dictionary) -> Array:
	var all := ArmySystem.roster(repo, state)
	var codes := all.keys()
	codes.sort()
	var out: Array = []
	for rc: Variant in host["regiments"]:
		var entry := String(rc)
		var found: Array = []
		if all.has(entry):
			found.append(entry)
		else:
			for c: String in codes:
				var r: Dictionary = all[c]
				if String(r.get("parent_code", "")) == entry and String(r.get("is_naval", "0")) != "1":
					found.append(c)
		for c: String in found:
			if not c in out:
				out.append(c)
	out.sort()
	return out


## One day of the hosts' minds, in host-code order (spec §3.1, §3.4, §3.5).
## A host assembled until its appear_day (the campaign's absolute day, the
## pack's row) sets out on that day's end: ASSEMBLE becomes ADVANCE. A host in
## the field then
##  1. reserves its day-end meal (assembling and town-holding hosts are fed locally);
##  2. in a TARGETING mode, turns to RETREAT when should_retreat gives a reason;
##  3. in ADVANCE, once its FIRST column reaches the target (arrival_mode),
##     starts DEPLOYING, RAIDs, or WITHDRAWs — or, at a town another host
##     already besieges, drops the target to choose again;
##  4. sends every idle column of its own on: an advancing, besieging or
##     raiding host's for the target, a homeward host's for its start point (a
##     battle halts a column; the host, not a courier, moves it on).
## Returns the day's events: {type: "host_advance", host, day} and
## {type: "host_mode", host, mode, why, day} for every change of mode.
## Run it once a day, AFTER ArmySystem.march_day and BEFORE
## BattleSystem.settle_day: the column that marched into a garrisoned town's
## contact today deploys its arrived columns before the day's contacts are read.
static func step_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	ensure_deployments(repo, state, events)
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
		if mode != MODE_HOLD:
			mind["meal_due_day"] = today
		if mode in TARGETING:
			var why := should_retreat(repo, state, code, true)
			if why != "":
				set_mode(state, code, MODE_RETREAT, why, events)
				_march_host(repo, state, code)
				continue
		if mode == MODE_ADVANCE and String(mind["target_id"]) != "":
			var next := arrival_mode(repo, state, code)
			if next == ARRIVAL_RETHINK:
				# another host already besieges it: drop it, choose again, and
				# stand aside today so no column of it fights the town alone
				mind["target_kind"] = ""
				mind["target_id"] = ""
				mind["think_day"] = 0
				_stand_aside(repo, state, code)
			elif next == ARRIVAL_LOST:
				# the crown no longer holds it: choose again today (think_day
				# runs after step_day); home only if nothing else is worth it
				mind["target_kind"] = ""
				mind["target_id"] = ""
				mind["think_day"] = 0
			elif next != "":
				set_mode(state, code, next, _arrival_why(next), events)
				if next == MODE_DEPLOYING:
					_start_deployment(repo, state, code)
		_march_host(repo, state, code)
		if String(mind["mode"]) == MODE_DEPLOYING:
			_update_deployment(repo, state, code, events)
	# a reserve besieging or holding beside a main host that turned home today
	# follows it now, before the day's battles
	SiegeSystem.follow_main(repo, state, events)
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
		var reg := ArmySystem.regiment(repo, c, state)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		if ArmySystem.fit_count(repo, state, c) > 0:
			out.append(c)
	return out


## The host's role (raid_hosts.csv: main / raider / reserve), "" for none.
static func role_of(repo: DataRepository, host_code: String) -> String:
	return String(_row_of(repo, host_code).get("role", ""))


## The host's doctrine: its role's row of data/battle/ai_doctrines.csv.
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
		var reg := ArmySystem.regiment(repo, code, state)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		if ArmySystem.fit_count(repo, state, code) <= 0:
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
## data/army/army_town_defence.csv, in it) of the player's regiments the host SEES
## (seen_by) that stand at the target. A target more march days away than the
## host's supply_reach_days is none, and so is a manor a raid has stripped
## bare (RaidSystem.stripped). [] for a host with no live column.
static func candidates(repo: DataRepository, state: GameState, host_code: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var anchor := anchor_of(repo, state, host_code)
	var horizon := supply_reach_days(repo, state, host_code)
	for c: Dictionary in _gather(repo, state, host_code):
		c["distance_days"] = _days(repo, state, anchor, c, horizon + 1)
		if int(c["distance_days"]) <= horizon:
			out.append(c)
	return out


## The most march days a host can go for a target: its hungriest live column's
## days in hand (ArmySystem.days_in_hand where it stands) less
## ai_retreat_supply_days — further, it would turn home hungry on the road
## (should_retreat) before it arrived — less ai_supply_margin_days (the whole-
## unit meals can run a unit ahead of the even share). No live column: -1.
static func supply_reach_days(repo: DataRepository, state: GameState, host_code: String) -> int:
	var least := _least_days(repo, state, host_code)
	return -1 if least < 0 else least - int(repo.bal("ai_retreat_supply_days")) \
		- int(repo.bal("ai_supply_margin_days"))


## The hungriest live column's whole days in hand; -1 with none.
static func _least_days(repo: DataRepository, state: GameState, host_code: String, after_meal := false) -> int:
	var least := -1
	for c: String in live_regiments(repo, state, host_code):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c, state), state)
		var supplies := int(state.foes[c]["supplies"])
		if after_meal:
			supplies = maxi(0, supplies - ArmySystem.day_bite(use, state.day))
		var days := ArmySystem.days_in_hand(supplies, use)
		least = days if least < 0 else mini(least, days)
	return least


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
	var key := "%d|%s" % [repo.get_instance_id(), repo.map_id]
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
## (MapOwnership), a manor's province as it stands now (MapManors.province_of)
## — and no host OCCUPIES its manor (SiegeSystem.occupier_of: a town taken by
## a siege and its manors around it are no target while the host holds them).
static func target_held(repo: DataRepository, state: GameState, kind: String, id: String) -> bool:
	var player := repo.resolve_realm("player_realm")
	if kind == KIND_TOWN:
		var b: Dictionary = repo.burgs.get(id, {})
		return not b.is_empty() and MapOwnership.owner_of(repo, state, String(b.get("province_code", ""))) == player \
			and SiegeSystem.occupier_of(state, target_cell(repo, state, kind, id)) == ""
	var cell := int(id)
	if not repo.manors.has(cell):
		return false
	return MapOwnership.owner_of(repo, state, MapManors.province_of(repo, cell, state)) == player \
		and SiegeSystem.occupier_of(state, cell) == ""


## Of `codes` (player regiments), those standing at the target: within
## battle_contact_km of its point, or — a town — in its reach (ArmySystem.town_of).
static func defenders_of(repo: DataRepository, state: GameState, kind: String, id: String, codes: Array) -> Array:
	var at := target_point_m(repo, kind, id)
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	var out: Array = []
	for c: Variant in codes:
		var code := String(c)
		if _within(_at_m(repo, state, code), at, reach) \
				or (kind == KIND_TOWN and ArmySystem.town_of(repo, ArmySystem.regiment(repo, code, state), state) == id):
			out.append(code)
	return out


## --- choosing (spec §3.2-3.3) -------------------------------------------------------

## A host's decision; returns its events ({type: "host_mode", host, mode,
## why, day} when it turns to WITHDRAW, else none). Only a host in ADVANCE
## thinks. A reserve follows the first main host EVERY call: it takes the main
## host's target (WITHDRAWs when the main host goes home, waits while it has
## none). Any other host chooses only when it has no target or ai_think_days
## have passed since its last decision (think_day); between, it keeps its
## target, so the player can read its intent. It takes rank's best of its
## candidates, a target another host holds paying the overlap
## (ai_target_overlap_permille, 1000: a ban); with none worth more than 0 it
## WITHDRAWs. A chosen target sends every column of the host marching for it at
## once (no courier); a withdrawal sends it home.
static func think(repo: DataRepository, state: GameState, host_code: String) -> Array:
	var events: Array = []
	if not state.ai_hosts.has(host_code):
		return events
	var mind: Dictionary = state.ai_hosts[host_code]
	if String(mind["mode"]) != MODE_ADVANCE:
		return events
	var today := state.absolute_day()
	var pick: Dictionary = {}
	var why := "nothing within reach is worth taking"
	if role_of(repo, host_code) == ROLE_RESERVE:
		var lead := _main_mind(repo, state)
		if lead.is_empty():
			return events                # no main host out yet: the reserve waits
		if String(lead["mode"]) in HOMEWARD:
			why = "the main host is going home"
		elif String(lead["target_id"]) == "":
			return events
		else:
			pick = {"kind": String(lead["target_kind"]), "id": String(lead["target_id"])}
		mind["think_day"] = today
	else:
		if String(mind["target_id"]) != "" and today - int(mind["think_day"]) < int(repo.bal("ai_think_days")):
			return events
		mind["think_day"] = today
		pick = _choose(repo, state, host_code)
	if pick.is_empty():
		mind["target_kind"] = ""
		mind["target_id"] = ""
		set_mode(state, host_code, MODE_WITHDRAW, why, events)
	else:
		mind["target_kind"] = String(pick["kind"])
		mind["target_id"] = String(pick["id"])
	_march_host(repo, state, host_code)
	return events


## Every host's decision of the day: the hosts with targets of their own in
## code order, then the reserves, so a reserve follows today's main target.
## Returns the decisions' events.
static func think_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	var reserves: Array = []
	for h: String in host_codes(state):
		if role_of(repo, h) == ROLE_RESERVE:
			reserves.append(h)
		else:
			events.append_array(think(repo, state, h))
	for h: String in reserves:
		events.append_array(think(repo, state, h))
	return events


## --- the warnings (spec §2 timeline) -----------------------------------------------

## The letters the crown hears of the hosts TODAY, for TickEngine to file: the
## border rumour (MissiveWriter.raid_rumour) on the absolute day
## raid_rumour_lead_days before the earliest appear_day of the hosts this
## campaign has (state.ai_hosts; a save without hosts hears nothing), about the
## host that crosses first (ties to the earlier code). Today only, so it comes
## once. The spy's count of a column near his point is SpySystem's (foe facts).
static func warnings(repo: DataRepository, state: GameState) -> Array:
	var first := rumoured_host(repo, state)
	if first == "":
		return []
	return [MissiveWriter.raid_rumour(repo, state, home_m(repo, first))]


## The host the border rumour is about TODAY — the first to cross (earliest
## appear_day, ties to the earlier code) on the absolute day
## raid_rumour_lead_days before its crossing — else "". The rumour's letter
## (warnings) and its ghost (Sighting.update) both ask this.
static func rumoured_host(repo: DataRepository, state: GameState) -> String:
	var first := ""
	var first_day := 0
	for h: String in host_codes(state):
		var row := _row_of(repo, h)
		if row.is_empty():
			continue
		if first == "" or int(row["appear_day"]) < first_day:
			first = h
			first_day = int(row["appear_day"])
	if first == "" or state.absolute_day() != first_day - int(repo.bal("raid_rumour_lead_days")):
		return ""
	return first


## --- engage and retreat (spec §3.4) ---------------------------------------------------

## Whether the host takes a fight with the player regiments it sees: its odds
## (BattleSystem.odds_permille of its side_power attacking against theirs
## defending, each against the other's height) at least the doctrine's
## engage_odds_permille. Nothing seen is a fight it takes; a host with no live
## column takes none.
## Contact calls this gate against the host's visible opposition.
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
## days in hand (ArmySystem.days_in_hand) below ai_retreat_supply_days — but a
## host that HOLDs a town it took lives off the town and never goes home hungry.
static func should_retreat(repo: DataRepository, state: GameState, host_code: String, after_meal := false) -> String:
	for c: String in regiments_of(state, host_code):
		if int((state.foes[c] as Dictionary).get("disengaging", 0)) == 1:
			return "beaten: %s fell back from the battle" % c
	var live := live_regiments(repo, state, host_code)
	if live.is_empty():
		return ""
	var morale := 0
	for c: String in live:
		morale += int((state.foes[c] as Dictionary)["morale"])
	var least := _least_days(repo, state, host_code, after_meal)
	@warning_ignore("integer_division")  # whole points
	morale /= live.size()
	var floor_morale := int(doctrine_of(repo, host_code).get("retreat_morale", 0))
	if morale < floor_morale:
		return "morale %d below %d" % [morale, floor_morale]
	var floor_days := int(repo.bal("ai_retreat_supply_days"))
	if least < floor_days and String((state.ai_hosts.get(host_code, {}) as Dictionary).get("mode", "")) != MODE_HOLD:
		return "supplies for %d days, below %d" % [least, floor_days]
	return ""


## --- arrival (Ruling 5) --------------------------------------------------------------

## What an ADVANCING host does now, "" for nothing new. Nothing while any of
## its live columns is in a battle (the battle decides first). At a town a
## player regiment GARRISONS (ArmyGround.garrison_town): once its FIRST live
## column touches the town as a battle would (within battle_contact_km of a
## garrisoning regiment or of the town's point, or within the town's reach) →
## DEPLOYING, so BattleSystem holds off an isolated assault while the
## other columns come up (a reserve deploys beside its main host so) — or, for a
## NON-reserve host, ARRIVAL_RETHINK when another non-reserve host already
## besieges that town (no second siege). Else, once its first live
## column stands within battle_contact_km of the target's point: the player no
## longer holds the target → ARRIVAL_LOST (choose again); a player regiment it sees stands at the
## target → nothing (contact fights it); else → RAID (an open manor, or a town
## with no garrison).
static func arrival_mode(repo: DataRepository, state: GameState, host_code: String) -> String:
	var mind: Dictionary = state.ai_hosts[host_code]
	var kind := String(mind["target_kind"])
	var id := String(mind["target_id"])
	var live := live_regiments(repo, state, host_code)
	if id == "" or live.is_empty():
		return ""
	for c: String in live:
		if not BattleSystem.battle_of(state, c).is_empty():
			return ""
	var at := target_point_m(repo, kind, id)
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	if kind == KIND_TOWN:
		var garrison := garrison_of(repo, state, id)
		if not garrison.is_empty():
			var town_m := int(round(float(repo.army_town_reach.get(
				String((repo.burgs[id] as Dictionary).get("group", "")), 0.0)) * 1000.0))
			for c: String in live:
				var here := _at_m(repo, state, c)
				var touches := _within(here, at, maxi(reach, town_m))
				for p: String in garrison:
					touches = touches or _within(here, _at_m(repo, state, p), reach)
				if touches:
					if role_of(repo, host_code) != ROLE_RESERVE and _besieged_by_another(repo, state, host_code, id):
						return ARRIVAL_RETHINK
					return MODE_DEPLOYING
			return ""
	var come := false
	for c: String in live:
		come = come or _within(_at_m(repo, state, c), at, reach)
	if not come:
		return ""
	if not target_held(repo, state, kind, id):
		return ARRIVAL_LOST
	if not defenders_of(repo, state, kind, id, seen_by(repo, state, host_code)).is_empty():
		return ""
	return MODE_RAID


## The player's regiments that GARRISON a town (ArmyGround.garrison_town), in
## code order.
static func garrison_of(repo: DataRepository, state: GameState, town: String) -> Array:
	var out: Array = []
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c: Variant in codes:
		if ArmyGround.garrison_town(repo, state, String(c)) == town:
			out.append(String(c))
	return out


## --- inside ------------------------------------------------------------------------

static func _row_of(repo: DataRepository, host_code: String) -> Dictionary:
	for row: Dictionary in repo.raid_hosts:
		if String(row["host_code"]) == host_code:
			return row
	return {}


## The first main host's mind (code order), {} when none is out of ASSEMBLE.
static func _main_mind(repo: DataRepository, state: GameState) -> Dictionary:
	var h := main_host(repo, state)
	return {} if h == "" else state.ai_hosts[h]


## The first main host (code order) out of ASSEMBLE, the one a reserve
## follows; "" when none.
static func main_host(repo: DataRepository, state: GameState) -> String:
	for h: String in host_codes(state):
		if role_of(repo, h) == ROLE_MAIN and String(state.ai_hosts[h]["mode"]) != MODE_ASSEMBLE:
			return h
	return ""


## Halts every live column of the host that is in no battle where it stands
## (order garrison, destination its own place) and keeps it out of contact for
## the rest of today (`disengaged_until` = today, the pause's last day, never shortening a longer
## pause): a host that found its town besieged by another stands aside while it
## chooses again.
static func _stand_aside(repo: DataRepository, state: GameState, host_code: String) -> void:
	var today := state.absolute_day()
	for c: String in live_regiments(repo, state, host_code):
		if not BattleSystem.battle_of(state, c).is_empty():
			continue
		var e: Dictionary = state.foes[c]
		e["order"] = ArmySystem.ORDER_GARRISON
		e["dest_x_m"] = int(e["x_m"])
		e["dest_y_m"] = int(e["y_m"])
		e["disengaged_until"] = maxi(int(e.get("disengaged_until", 0)), today)


## True when a non-reserve host other than `host_code` sits in SIEGE at `town`.
static func _besieged_by_another(repo: DataRepository, state: GameState, host_code: String, town: String) -> bool:
	for h: String in host_codes(state):
		if h == host_code or role_of(repo, h) == ROLE_RESERVE:
			continue
		var m: Dictionary = state.ai_hosts[h]
		if String(m["mode"]) in [MODE_DEPLOYING, MODE_SIEGE] and String(m["target_kind"]) == KIND_TOWN and String(m["target_id"]) == town:
			return true
	return false


## A change of mode, told as a host_mode event {type, host, mode, why, day}
## in `events` — EnemyAi's own and SiegeSystem's (every mode change goes
## through here). Leaving a SIEGE clears the siege's figures and its assault
## flag (SiegeSystem.clear; SiegeSystem tells the siege lifted).
static func set_mode(state: GameState, host_code: String, mode: String, why: String, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[host_code]
	if String(mind["mode"]) in [MODE_DEPLOYING, MODE_SIEGE] and mode not in [MODE_DEPLOYING, MODE_SIEGE]:
		SiegeSystem.clear(mind)
		mind.erase("deployment")
	mind["mode"] = mode
	events.append({"type": "host_mode", "host": host_code, "mode": mode, "why": why,
		"day": state.absolute_day()})


static func _arrival_why(mode: String) -> String:
	match mode:
		MODE_DEPLOYING:
			return "first column arrived; remaining columns are deploying"
		MODE_SIEGE:
			return "leading columns deployed at the town"
		MODE_RAID:
			return "reached an undefended target"
	return "the target is no longer the enemy's"


## Deduct after all battles, from the current custody holders, once per day.
static func eat_day(repo: DataRepository, state: GameState) -> void:
	for code: String in host_codes(state):
		var mind: Dictionary = state.ai_hosts[code]
		if int(mind.get("meal_due_day", -1)) != state.absolute_day() \
				or int(mind.get("meal_eaten_day", -1)) == state.absolute_day():
			continue
		_eat(repo, state, code)
		mind["meal_eaten_day"] = state.absolute_day()

## A day's meal for every foe of the host (ArmySystem.eat_one).
static func _eat(repo: DataRepository, state: GameState, host_code: String) -> void:
	for c: String in regiments_of(state, host_code):
		var reg := ArmySystem.regiment(repo, c, state)
		if not reg.is_empty():
			ArmySystem.eat_one(repo, state, reg, state.foes[c])


## Sends the host's columns where its mode wants them (_march_host), for
## SiegeSystem: a host it sends home marches at once.
static func march_host(repo: DataRepository, state: GameState, host_code: String) -> void:
	_march_host(repo, state, host_code)


## Sends the host's columns where its mode wants them: ADVANCE, DEPLOYING, SIEGE and RAID
## for its target (the columns behind the first come up), RETREAT / WITHDRAW
## for its start point (a column falling back from a battle
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
	elif mode in [MODE_ADVANCE, MODE_DEPLOYING, MODE_SIEGE, MODE_RAID] and String(mind["target_id"]) != "":
		to = target_point_m(repo, String(mind["target_kind"]), String(mind["target_id"]))
	else:
		return
	var occupation := ""
	if mode == MODE_SIEGE and SiegeSystem.garrison_fit(repo, state, String(mind["target_id"])) == 0:
		occupation = _occupation_column(repo, state, host_code, to)
	for c: String in live_regiments(repo, state, host_code):
		var e: Dictionary = state.foes[c]
		if not BattleSystem.battle_of(state, c).is_empty():
			continue
		if not homeward and int(e.get("disengaging", 0)) == 1:
			continue
		if c == occupation and BattleSystem.town_contact(repo, state, String(mind["target_id"]), c) == "":
			_aim_with_camp_gate(repo, state, c, e, to)
			continue
		if mode in [MODE_DEPLOYING, MODE_SIEGE] and SiegeSystem.at_town(repo, state, c, String(mind["target_id"])):
			e["order"] = ArmySystem.ORDER_GARRISON
			e["dest_x_m"] = int(e["x_m"])
			e["dest_y_m"] = int(e["y_m"])
			e.erase("route_m")
			e.erase("waypoints_m")
			continue
		if int(e["x_m"]) == to.x and int(e["y_m"]) == to.y:
			continue
		if _stands_halted(repo, state, c, e, to):
			continue      # a standoff before the crown (or a slot round the target) holds while its aim does
		# round ground it cannot climb, as the crown's columns go (MarchPath)
		_aim_with_camp_gate(repo, state, c, e, to)

static func _aim_with_camp_gate(repo: DataRepository, state: GameState, code: String,
		entry: Dictionary, to: Vector2i) -> void:
	CampSystem.ensure_legacy(repo, state, code)
	CampSystem.request_departure(state, code, state.absolute_day(), true)
	ArmySystem.aim_entry(repo, entry, to, ArmySystem.is_naval(repo, state, code))


## One nearest available column takes possession of an abandoned siege target.
## Other camps hold; equal distances use stable code order.
static func _occupation_column(repo: DataRepository, state: GameState, host: String, to: Vector2i) -> String:
	var chosen := ""
	var best := 0
	for c: String in live_regiments(repo, state, host):
		var e: Dictionary = state.foes[c]
		if int(e.get("disengaging", 0)) != 0 or not BattleSystem.battle_of(state, c).is_empty():
			continue
		var dx := int(e["x_m"]) - to.x
		var dy := int(e["y_m"]) - to.y
		var distance := dx * dx + dy * dy
		if chosen == "" or distance < best or (distance == best and c < chosen):
			chosen = c
			best = distance
	return chosen


## Whether a column halted before a unit (ArmySystem._halt_before) is still in
## its standoff: bound for the same `to` it was, its enemy still obstructing
## the onward road, or its friendly blocker beside the target camp.
## Such a column is not re-aimed (a new aim_entry would wipe
## its halt and facing); a changed target, or a blocker gone, releases it.
static func _stands_halted(repo: DataRepository, state: GameState, code: String, e: Dictionary, to: Vector2i) -> bool:
	if not e.has("halted_by") or not e.has("halt_aim_m"):
		return false
	var aim: Array = e["halt_aim_m"]
	if int(aim[0]) != to.x or int(aim[1]) != to.y:
		return false
	var b := String(e["halted_by"])
	var be: Dictionary = state.foes.get(b, state.regiments.get(b, {}))
	if be.is_empty() or ArmySystem.living_count(repo, state, b) <= 0:
		return false
	var reach := int(repo.bal("army_spread_reach_m"))
	var here := Vector2i(int(e["x_m"]), int(e["y_m"]))
	if not _within(here, Vector2i(int(be["x_m"]), int(be["y_m"])), reach):
		return false
	# A displaced enemy releases the march; friendly camps hold their target slot.
	var theirs := String(ArmySystem.regiment(repo, b, state).get("kingdom_code", ""))
	if theirs != repo.resolve_realm("raider_realm"):
		var radius := ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, code, state)) \
			+ ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, b, state))
		return not MarchClearance.first_entry(here, [to],
			[Vector2i(int(be["x_m"]), int(be["y_m"]))], [radius]).is_empty()
	return _within(here, Vector2i(aim[0], aim[1]), reach)


## A regiment's place in whole metres: its stored state's, else the pack's.
static func _at_m(repo: DataRepository, state: GameState, code: String) -> Vector2i:
	var e: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
	if e.has("x_m"):
		return Vector2i(int(e["x_m"]), int(e["y_m"]))
	return ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code, state)))


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
			if not _within(from, at, reach) or not target_held(repo, state, kind, id) \
					or RaidSystem.stripped(repo, state, cell):
				continue
			var base := int(round(MapManors.value_of_line(repo, state, cell, RealmEconomy.line_of(repo, state, cell))))
			var defence := 0
			for p: String in defenders_of(repo, state, kind, id, seen):
				defence += ArmySystem.power(repo, state, p, "defend")
			out.append({"kind": kind, "id": id, "cell": cell, "value": target_value(base, kind, doctrine),
				"distance_days": -1, "defence": defence})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _key(a) < _key(b))
	return out


## Whole days for the anchor to march to a candidate's point, walked at most
## `max_days` (the supply reach + 1: further is no candidate, however far).
static func _days(repo: DataRepository, state: GameState, anchor: String, c: Dictionary, max_days: int = -1) -> int:
	if anchor == "":
		return 0
	var to := target_point_m(repo, String(c["kind"]), String(c["id"]))
	return ArmySystem.march_days_between(repo, state, anchor,
		ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, anchor, state)), ArmySystem.metres_to_pack(repo, to),
		-1, [], -1, max_days)


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
	var horizon := supply_reach_days(repo, state, host_code)
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
		c["distance_days"] = _days(repo, state, anchor, c, horizon + 1)
		if int(c["distance_days"]) > horizon:
			continue                     # beyond its supplies: no candidate
		var sc := _final(c, int(c["distance_days"]), doctrine, taken, permille)
		if best.is_empty() or _better(sc, c, best_score, best):
			best = c
			best_score = sc
	if best.is_empty() or best_score <= 0:
		return {}
	return best


## Normalize legacy siege minds without advancing time or touching a day cursor.
## Called after a repository-backed load and before the day's battles.
static func ensure_deployments(repo: DataRepository, state: GameState, events: Array = []) -> void:
	for h: String in host_codes(state):
		var mind: Dictionary = state.ai_hosts[h]
		if String(mind.get("mode", "")) not in [MODE_DEPLOYING, MODE_SIEGE]:
			continue
		if not mind.has("deployment"):
			_start_deployment(repo, state, h)
			if int(mind.get("assault", 0)) == 1:
				mind["assault_due"] = 1
			mind["assault"] = 0
			if String(mind["mode"]) == MODE_SIEGE:
				set_mode(state, h, MODE_DEPLOYING, "restoring deployment from actual column positions", events)
			_update_deployment(repo, state, h, events)


static func _start_deployment(repo: DataRepository, state: GameState, host: String) -> void:
	var mind: Dictionary = state.ai_hosts[host]
	mind["deployment"] = {"town": String(mind["target_id"]), "started_day": state.absolute_day(),
		"complete": false}


## Establishing a siege is a physical deployment, not a roll call of every
## original column. Late columns keep marching and contribute only on arrival.
static func _update_deployment(repo: DataRepository, state: GameState, host: String, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[host]
	var deployment: Dictionary = mind["deployment"]
	var town := String(deployment["town"])
	for c: String in live_regiments(repo, state, host):
		if not SiegeSystem.deployed_at(repo, state, c, town):
			continue
		deployment["complete"] = true
		deployment["completed_day"] = state.absolute_day()
		mind["assault"] = 0
		set_mode(state, host, MODE_SIEGE, "leading columns deployed at the town", events)
		return
