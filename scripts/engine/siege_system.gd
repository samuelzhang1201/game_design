class_name SiegeSystem
extends RefCounted
## The siege (spec docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md
## §5.1-5.2). A host in mode SIEGE (EnemyAi sets it on arrival) sits before a
## town the player's regiments GARRISON (SupplySystem.garrisoned_in) and wears
## it down a day at a time:
##
##   step  = siege_rate x A / (A + D)        (0 when A + D == 0)
##   gain  = step, + step x siege_starve_bonus_permille / 1000 while the town's
##           own stores are spent (starving)
##   siege_progress (of 1000, on the leading host's mind) += gain
##
## A = the besiegers' columns at the town, ArmySystem.power "attack"; D = the
## garrison's ArmySystem.power "defend" (the town's works are inside it). Every
## siege_assault_days days of siege the host STORMS the town: the assault is the
## ordinary town battle (Ruling 3), let through BattleSystem by the mind's
## `assault` flag. The garrison broken (the assault won) or slain to the last
## man, or the progress at 1000: the town falls (capture). Whole numbers, host
## code order, no random number.
##
## Mind fields (GameState.ai_hosts[h], saved, all whole): siege_progress,
## siege_days (days sat), siege_town (the town besieged, kept until the siege's
## end is told), assault (1: tomorrow's battles may storm), assault_due (an
## assault owed and not yet fought), starved (1: the town's hunger was told).

const SIEGE := "SIEGE"
const HOLD := "HOLD"
const RETREAT := "RETREAT"
const WITHDRAW := "WITHDRAW"
const RAID := "RAID"

## The events SiegeSystem.settle_day returns that are not a letter's line.
const QUIET := ["siege_day"]


## A day's wearing down: rate x attack / (attack + defend), rounded down.
static func step(attack_power: int, defend_power: int, rate: int) -> int:
	if attack_power + defend_power <= 0:
		return 0
	@warning_ignore("integer_division")  # whole per-mille of the town
	return rate * maxi(0, attack_power) / (attack_power + defend_power)


## The day's gain: the step, and while the town starves the step's
## `bonus_permille` more (rounded down).
static func day_gain(attack_power: int, defend_power: int, rate: int, starving: bool, bonus_permille: int) -> int:
	var g := step(attack_power, defend_power, rate)
	if starving:
		@warning_ignore("integer_division")  # whole per-mille
		g += g * bonus_permille / 1000
	return g


## Clears a mind's siege figures (progress, days, the assault); `siege_town`
## stays for settle_day to tell the siege's end. EnemyAi calls it whenever a
## host's mode changes from SIEGE.
static func clear(mind: Dictionary) -> void:
	mind["siege_progress"] = 0
	mind["siege_days"] = 0
	mind["assault"] = 0
	mind["assault_due"] = 0
	mind["starved"] = 0


## True while any host sits in SIEGE before `town`.
static func besieged(state: GameState, town: String) -> bool:
	for h: Variant in state.ai_hosts:
		if _sits_before(state.ai_hosts[h], town):
			return true
	return false


## The hosts in SIEGE before `town`, in code order.
static func besiegers(state: GameState, town: String) -> Array:
	var out: Array = []
	for h: String in EnemyAi.host_codes(state):
		if _sits_before(state.ai_hosts[h], town):
			out.append(h)
	return out


## The host that keeps a town's siege: the first non-reserve host before it
## (code order), else the first; "" when none sits there.
static func lead_of(repo: DataRepository, state: GameState, town: String) -> String:
	var hosts := besiegers(state, town)
	for h: String in hosts:
		if EnemyAi.role_of(repo, h) != EnemyAi.ROLE_RESERVE:
			return h
	return "" if hosts.is_empty() else String(hosts[0])


## True when a foe stands at the town: within battle_contact_km of its point
## or within its reach (data/army_town_reach.csv) — the ring arrival uses.
static func at_town(repo: DataRepository, state: GameState, code: String, town: String) -> bool:
	var e: Dictionary = state.foes.get(code, {})
	if e.is_empty():
		return false
	var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	var reach := maxi(int(round(repo.bal("battle_contact_km") * 1000.0)),
		int(round(float(repo.army_town_reach.get(String((repo.burgs.get(town, {}) as Dictionary).get("group", "")), 0.0)) * 1000.0)))
	var dx := int(e["x_m"]) - at.x
	var dy := int(e["y_m"]) - at.y
	return dx * dx + dy * dy <= reach * reach


## The besiegers' power: every live column of every host in SIEGE before the
## town that stands at it (at_town), ArmySystem.power "attack".
static func attack_power(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for h: String in besiegers(state, town):
		for c: String in EnemyAi.live_regiments(repo, state, h):
			if at_town(repo, state, c, town):
				total += ArmySystem.power(repo, state, c, "attack")
	return total


## The garrison's power: each regiment that garrisons the town
## (EnemyAi.garrison_of), ArmySystem.power "defend" — the town's works in it.
static func defend_power(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for p: String in EnemyAi.garrison_of(repo, state, town):
		total += ArmySystem.power(repo, state, p, "defend")
	return total


## True when the town's own stores (TownStores: crown, lord and house) are spent.
static func starving(state: GameState, town: String) -> bool:
	var st := TownStores.stock_of(state, town)
	return int(st["crown"]) + int(st["lord"]) + int(st["house"]) <= 0


## The events settle_day returns that make a letter's line (all but the
## quiet day's wearing down).
static func news(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return not String(e["kind"]) in QUIET)


## The sieges' day, run once a day right AFTER BattleSystem.settle_day (an
## assault's outcome is in that day's `battle_events`). In order:
##  1. a reserve in SIEGE whose main host left the siege (WITHDRAW, RETREAT,
##     HOLD) follows it;
##  2. each town's siege, by its leading host (lead_of; a reserve beside its
##     main host adds its columns, keeps no siege of its own): the town no
##     longer the crown's → the besiegers WITHDRAW (no progress, no capture);
##     today's assault, if one ended (won: progress 1000; repulsed: less
##     siege_assault_fail_permille, never below 0; drawn: nothing); the town
##     falls at 1000 or with its garrison slain to the last fit man; a town
##     with no garrison left is RAIDed (no progress); else the day's gain, and
##     every siege_assault_days days an assault is owed, armed for tomorrow's
##     battles (the flag stands while the assault's battle lasts, and an owed
##     assault that found no battle is tried again the next day);
##  3. a HOLD host whose town is the crown's again RETREATs;
##  4. a host that left its siege any other way (beaten, hungry: EnemyAi) has
##     it told once as lifted.
## Returns the events: {kind, host, town, day, progress, ...}: siege_begin and
## siege_day {attack, defend, gain, starving}, siege_starving, siege_repulsed
## {lost}, siege_fallen {days, reason}, siege_undefended, siege_lifted {why},
## siege_retaken.
static func settle_day(repo: DataRepository, state: GameState, battle_events: Array = []) -> Array:
	var events: Array = []
	if state.ai_hosts.is_empty():
		return events
	_follow_main(repo, state)
	for h: String in EnemyAi.host_codes(state):
		var mind: Dictionary = state.ai_hosts[h]
		var mode := String(mind["mode"])
		if mode == SIEGE:
			var town := String(mind.get("target_id", ""))
			if lead_of(repo, state, town) == h or String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN:
				_siege_day(repo, state, h, battle_events, events)
		elif mode == HOLD:
			_hold_day(repo, state, h, events)
		elif String(mind.get("siege_town", "")) != "":
			_lifted(repo, state, h, String(mind["mode"]).to_lower(), events)
	return events


## Takes the besieged town of `host_code` (a host in SIEGE before a town the
## crown still holds; anything else is refused with {}): the town's province
## to the host's kingdom (MapOwnership.set_owner) and the town's own manor to
## that kingdom's ruling house (MapManors.set_owner), both with the reason
## "taken by <host>: siege of <town>"; the garrison still standing marches out
## for the nearest town of its own (as a column falling back from a battle);
## every host before the town HOLDs it. Returns the siege_fallen event.
static func capture(repo: DataRepository, state: GameState, host_code: String) -> Dictionary:
	if not state.ai_hosts.has(host_code):
		return {}
	var mind: Dictionary = state.ai_hosts[host_code]
	var town := String(mind.get("target_id", ""))
	if String(mind["mode"]) != SIEGE or String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN \
			or not EnemyAi.target_held(repo, state, EnemyAi.KIND_TOWN, town):
		return {}
	var b: Dictionary = repo.burgs[town]
	var kingdom := _kingdom_of(repo, state, host_code)
	var reason := "taken by %s: siege of %s" % [host_label(repo, host_code), String(b.get("label", town))]
	var garrison := EnemyAi.garrison_of(repo, state, town)
	var days := int(mind.get("siege_days", 0))
	var progress := int(mind.get("siege_progress", 0))
	MapOwnership.set_owner(repo, state, String(b.get("province_code", "")), kingdom, reason)
	var cell := EnemyAi.target_cell(repo, state, EnemyAi.KIND_TOWN, town)
	var house := _house_of(repo, kingdom)
	if cell >= 0 and house != "":
		MapManors.set_owner(repo, state, cell, house, reason)
	var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	for p: String in garrison:
		if ArmySystem.fit_heads(ArmySystem.headcount(repo, ArmySystem.regiment(repo, p)), state.regiments[p]) > 0:
			BattleSystem.march_out(repo, state, p, at)
	for h: String in besiegers(state, town):
		var m: Dictionary = state.ai_hosts[h]
		m["mode"] = HOLD
		clear(m)
		m["siege_town"] = ""
	return {"kind": "siege_fallen", "host": host_code, "town": town, "day": state.absolute_day(),
		"progress": maxi(progress, 1000), "days": days, "reason": reason}


## A host in words for a reason: "<raider realm>'s <role> host".
static func host_label(repo: DataRepository, host_code: String) -> String:
	var role := EnemyAi.role_of(repo, host_code)
	return "%s's %s host" % [repo.realm_label("raider_realm"), role if role != "" else host_code]


## --- inside ------------------------------------------------------------------

static func _sits_before(mind: Dictionary, town: String) -> bool:
	return String(mind.get("mode", "")) == SIEGE and String(mind.get("target_kind", "")) == EnemyAi.KIND_TOWN \
		and String(mind.get("target_id", "")) == town


## A reserve in SIEGE follows its main host out of the siege: WITHDRAW and
## RETREAT home, HOLD (the town taken) with it.
static func _follow_main(repo: DataRepository, state: GameState) -> void:
	var lead := EnemyAi.main_host(repo, state)
	if lead == "":
		return
	var main_mode := String(state.ai_hosts[lead]["mode"])
	if not main_mode in [WITHDRAW, RETREAT, HOLD]:
		return
	for h: String in EnemyAi.host_codes(state):
		var mind: Dictionary = state.ai_hosts[h]
		if EnemyAi.role_of(repo, h) != EnemyAi.ROLE_RESERVE or String(mind["mode"]) != SIEGE:
			continue
		if main_mode == HOLD:
			mind["mode"] = HOLD
			clear(mind)
			mind["siege_town"] = ""
		else:
			_go_home(repo, state, h, main_mode)


## A host leaves its siege for home (RETREAT or WITHDRAW): its figures
## cleared, its columns sent home (EnemyAi).
static func _go_home(repo: DataRepository, state: GameState, host_code: String, mode: String) -> void:
	var mind: Dictionary = state.ai_hosts[host_code]
	mind["mode"] = mode
	clear(mind)
	EnemyAi.march_host(repo, state, host_code)


## One town's siege day, kept by its leading host `h`.
static func _siege_day(repo: DataRepository, state: GameState, h: String, battle_events: Array, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[h]
	var town := String(mind.get("target_id", ""))
	var hosts := besiegers(state, town)
	if hosts.is_empty():
		hosts = [h]
	var today := state.absolute_day()
	if String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN \
			or not EnemyAi.target_held(repo, state, EnemyAi.KIND_TOWN, town):
		# the town is no longer the crown's: nothing to besiege, nothing to take
		for x: String in hosts:
			_go_home(repo, state, x, WITHDRAW)
		_lifted(repo, state, h, "lost", events)
		for x: String in hosts:
			state.ai_hosts[x]["siege_town"] = ""
		return
	mind["siege_town"] = town
	var progress := int(mind.get("siege_progress", 0))
	# today's assault, if one was fought out
	var outcome := _assault_outcome(state, town, hosts, battle_events)
	if outcome != "":
		mind["assault_due"] = 0
	if outcome == "won":
		progress = 1000
	elif outcome == "repulsed":
		var lost := mini(progress, int(repo.bal("siege_assault_fail_permille")))
		progress -= lost
		events.append({"kind": "siege_repulsed", "host": h, "town": town, "day": today, "progress": progress,
			"lost": lost})
	mind["siege_progress"] = progress
	var garrison := EnemyAi.garrison_of(repo, state, town)
	var fit := 0
	for p: String in garrison:
		fit += ArmySystem.fit_heads(ArmySystem.headcount(repo, ArmySystem.regiment(repo, p)), state.regiments[p])
	if progress >= 1000 or (not garrison.is_empty() and fit <= 0):
		_fall(repo, state, h, hosts, events)
		return
	if garrison.is_empty():
		# no one holds the walls: no siege, and nothing taken by one — the town
		# is raided as an open town is on arrival
		for x: String in hosts:
			var m: Dictionary = state.ai_hosts[x]
			m["mode"] = RAID
			clear(m)
			m["siege_town"] = ""
		events.append({"kind": "siege_undefended", "host": h, "town": town, "day": today, "progress": 0})
		return
	var att := attack_power(repo, state, town)
	var def := defend_power(repo, state, town)
	var hungry := starving(state, town)
	var gain := day_gain(att, def, int(repo.bal("siege_rate")), hungry, int(repo.bal("siege_starve_bonus_permille")))
	progress = mini(1000, progress + gain)
	mind["siege_progress"] = progress
	mind["siege_days"] = int(mind.get("siege_days", 0)) + 1
	var day := {"kind": "siege_day", "host": h, "town": town, "day": today, "progress": progress,
		"attack": att, "defend": def, "gain": gain, "starving": hungry}
	if int(mind["siege_days"]) == 1:
		var begin := day.duplicate()
		begin["kind"] = "siege_begin"
		events.append(begin)
	events.append(day)
	if hungry and int(mind.get("starved", 0)) == 0:
		mind["starved"] = 1
		events.append({"kind": "siege_starving", "host": h, "town": town, "day": today, "progress": progress})
	if progress >= 1000:
		_fall(repo, state, h, hosts, events)
		return
	if int(mind["siege_days"]) % maxi(1, int(repo.bal("siege_assault_days"))) == 0:
		mind["assault_due"] = 1
	# tomorrow's battles: an owed assault, or the assault still being fought
	var flag := 1 if int(mind.get("assault_due", 0)) == 1 or _assault_running(state, town, hosts) else 0
	for x: String in hosts:
		state.ai_hosts[x]["assault"] = flag


static func _fall(repo: DataRepository, state: GameState, h: String, hosts: Array, events: Array) -> void:
	# the capture reads its host in SIEGE: every host before the town still is
	var ev := capture(repo, state, h)
	if not ev.is_empty():
		events.append(ev)
	for x: String in hosts:
		state.ai_hosts[x]["siege_town"] = ""


## A HOLD host whose town is the crown's again goes home (RETREAT).
static func _hold_day(repo: DataRepository, state: GameState, h: String, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[h]
	var town := String(mind.get("target_id", ""))
	if String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN \
			or not EnemyAi.target_held(repo, state, EnemyAi.KIND_TOWN, town):
		return
	_go_home(repo, state, h, RETREAT)
	mind["siege_town"] = ""
	events.append({"kind": "siege_retaken", "host": h, "town": town, "day": state.absolute_day(), "progress": 0})


## A siege that ended otherwise (the host beaten, hungry, gone home) told once:
## siege_lifted {why}, one line a town a day.
static func _lifted(_repo: DataRepository, state: GameState, h: String, why: String, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[h]
	var town := String(mind.get("siege_town", ""))
	if town == "":
		town = String(mind.get("target_id", ""))
	mind["siege_town"] = ""
	clear(mind)
	if town == "" or besieged(state, town):
		return
	for e: Dictionary in events:
		if String(e["kind"]) == "siege_lifted" and String(e["town"]) == town:
			return
	events.append({"kind": "siege_lifted", "host": h, "town": town, "day": state.absolute_day(),
		"progress": 0, "why": why})


## How today's assault on `town` ended: "won" (the besiegers kept the field),
## "repulsed" (the garrison did), "drawn" (neither), "" when no assault battle
## ended today. An assault is a battle at the town (its `town`) that a column
## of the besieging hosts fought in.
static func _assault_outcome(state: GameState, town: String, hosts: Array, battle_events: Array) -> String:
	var sides: Dictionary = {}   # battle id -> the side the besiegers fought on
	for e: Dictionary in battle_events:
		if not e.has("battle_id"):
			continue
		var id := int(e["battle_id"])
		if e.has("town") and String(e["town"]) != town:
			continue
		for side: String in BattleSystem.SIDES:
			for c: Variant in e.get(side, []):
				if _of_hosts(state, String(c), hosts):
					sides[id] = side
		if e.has("code") and _of_hosts(state, String(e["code"]), hosts):
			sides[id] = String(e.get("side", sides.get(id, "att")))
	var out := ""
	for e: Dictionary in battle_events:
		if String(e.get("kind", "")) != "end" or String(e.get("town", "")) != town or not sides.has(int(e["battle_id"])):
			continue
		var winner := String(e["winner"])
		if winner == "":
			out = "drawn" if out == "" else out
		elif winner == String(sides[int(e["battle_id"])]):
			out = "won"
		elif out != "won":
			out = "repulsed"
	return out


## True while a battle at the town holds a column of the besieging hosts.
static func _assault_running(state: GameState, town: String, hosts: Array) -> bool:
	for b: Dictionary in state.battles:
		if String(b["town"]) != town:
			continue
		for side: String in BattleSystem.SIDES:
			for c: Variant in b[side]:
				if _of_hosts(state, String(c), hosts):
					return true
	return false


static func _of_hosts(state: GameState, code: String, hosts: Array) -> bool:
	return String((state.foes.get(code, {}) as Dictionary).get("host", "")) in hosts


## The kingdom a host fights for: its first foe's pack kingdom_code, else the
## raider realm's.
static func _kingdom_of(repo: DataRepository, state: GameState, host_code: String) -> String:
	for c: String in EnemyAi.regiments_of(state, host_code):
		var k := String(ArmySystem.regiment(repo, c).get("kingdom_code", ""))
		if k != "" and repo.kingdoms.has(k):
			return k
	return repo.resolve_realm("raider_realm")


## A kingdom's ruling house: the house of the province its capital stands in
## (MapObjects.house_name_of); "" with none.
static func _house_of(repo: DataRepository, kingdom: String) -> String:
	var cap := String((repo.kingdoms.get(kingdom, {}) as Dictionary).get("capital_burg", ""))
	var prov := String((repo.burgs.get(cap, {}) as Dictionary).get("province_code", ""))
	return MapObjects.house_name_of(repo, prov) if prov != "" else ""
