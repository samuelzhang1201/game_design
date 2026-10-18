class_name SiegeSystem
extends RefCounted
## The siege (spec docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md
## §5.1-5.2). A host in mode SIEGE (EnemyAi sets it on arrival) sits before a
## town the player's regiments GARRISON (ArmyGround.garrison_town) and wears
## it down a day at a time:
##
##   step  = siege_rate x A / (A + D)        (0 when A + D == 0)
##   gain  = step, + step x siege_starve_bonus_permille / 1000 while the town
##           starves (its own stores AND its garrison's carried ones spent)
##   siege_progress (of 1000, on the leading host's mind) += gain
##
## A = the besiegers' columns at the town, ArmySystem.power "attack"; D = the
## garrison's ArmySystem.power "defend" (the town's works are inside it). Every
## siege_assault_days days of siege the host STORMS the town: the assault is the
## ordinary town battle (Ruling 3), let through BattleSystem by the mind's
## `assault` flag; each of its rounds moves the siege by its tier's `siege`
## column (data/battle/battle_outcomes.csv). At 1000, or with the garrison slain to the
## last man, the town falls — at the MANOR level (capture): the province, its
## border and its capital never move. Whole numbers, host code order, no random
## number.
##
## Mind fields (GameState.ai_hosts[h], saved, whole numbers and strings):
## siege_progress, siege_days (days sat), siege_town (the town besieged, kept
## until the siege's end is told), assault (1: tomorrow's battles may storm),
## assault_due (an assault owed and not yet fought), starved (1: the town's
## hunger was told); on a host that took a town, occupied (manor cell as a
## string -> the house that held it before) and occupied_house (the house it
## gave them to).

const SIEGE := "SIEGE"
const HOLD := "HOLD"
const RETREAT := "RETREAT"
const WITHDRAW := "WITHDRAW"
const RAID := "RAID"

## An assault round's tier moves the siege by its `siege` column.
const TIER_REPULSED := "repulsed"
const TIER_BREACH := "breach"


## A day's wearing down: rate x attack / (attack + defend), rounded down.
static func step(atk: int, dfn: int, rate: int) -> int:
	if atk + dfn <= 0:
		return 0
	@warning_ignore("integer_division")  # whole per-mille of the town
	return rate * maxi(0, atk) / (atk + dfn)


## The day's gain: the step, and while the town starves the step's
## `bonus_permille` more (rounded down).
static func day_gain(atk: int, dfn: int, rate: int, hungry: bool, bonus_permille: int) -> int:
	var g := step(atk, dfn, rate)
	if hungry:
		@warning_ignore("integer_division")  # whole per-mille
		g += g * bonus_permille / 1000
	return g


## Clears a mind's siege figures (progress, days, the assault); `siege_town`
## stays for settle_day to tell the siege's end. EnemyAi.set_mode calls it
## whenever a host leaves SIEGE — the one place a siege's figures are cleared.
static func clear(mind: Dictionary) -> void:
	mind["siege_progress"] = 0
	mind["siege_days"] = 0
	mind["assault"] = 0
	mind["assault_due"] = 0
	mind["starved"] = 0


## True while any host sits in SIEGE before `town`.
static func besieged(repo: DataRepository, state: GameState, town: String) -> bool:
	for h: Variant in state.ai_hosts:
		if _sits_before(repo, state, String(h), town):
			return true
	return false


## The hosts in SIEGE before `town`, in code order.
static func besiegers(repo: DataRepository, state: GameState, town: String) -> Array:
	var out: Array = []
	for h: String in EnemyAi.host_codes(state):
		if _sits_before(repo, state, String(h), town):
			out.append(h)
	return out


## The host that keeps a town's siege: the first non-reserve host before it
## (code order), else the first; "" when none sits there.
static func lead_of(repo: DataRepository, state: GameState, town: String) -> String:
	var hosts := besiegers(repo, state, town)
	for h: String in hosts:
		if EnemyAi.role_of(repo, h) != EnemyAi.ROLE_RESERVE:
			return h
	return "" if hosts.is_empty() else String(hosts[0])


## The host that occupies manor `cell` (took it with a town and holds it), ""
## for none — such a manor is no target of the crown's (EnemyAi.target_held).
static func occupier_of(state: GameState, cell: int) -> String:
	var key := str(cell)
	for h: String in EnemyAi.host_codes(state):
		if (state.ai_hosts[h].get("occupied", {}) as Dictionary).has(key):
			return h
	return ""


## True when a foe stands at the town: within battle_contact_km of its point
## or within its reach (data/army/army_town_reach.csv) — the ring arrival uses —
## or, with the clearance on, within army_spread_reach_m: a host's columns are
## spread round their target on the camp lattice (ArmySystem._spread_foe), the
## outer rings further than the contact, and the whole host is at the town.
static func at_town(repo: DataRepository, state: GameState, code: String, town: String) -> bool:
	var e: Dictionary = state.foes.get(code, {})
	if e.is_empty():
		return false
	var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	var reach := maxi(int(round(repo.bal("battle_contact_km") * 1000.0)),
		int(round(float(repo.army_town_reach.get(String((repo.burgs.get(town, {}) as Dictionary).get("group", "")), 0.0)) * 1000.0)))
	if ArmyGround.clearance_on(repo):
		reach = maxi(reach, int(repo.bal("army_spread_reach_m")))
	var dx := int(e["x_m"]) - at.x
	var dy := int(e["y_m"]) - at.y
	return dx * dx + dy * dy <= reach * reach


## Only a column actually stationed here contributes to investment or assault.
static func deployed_at(repo: DataRepository, state: GameState, code: String, town: String) -> bool:
	var e: Dictionary = state.foes.get(code, {})
	return String(e.get("order", "")) == ArmySystem.ORDER_GARRISON and int(e.get("disengaging", 0)) == 0 \
		and at_town(repo, state, code, town)


## The besiegers' power: every live column of every host in SIEGE before the
## town that stands at it (at_town), ArmySystem.power "attack".
static func attack_power(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for h: String in besiegers(repo, state, town):
		for c: String in EnemyAi.live_regiments(repo, state, h):
			if deployed_at(repo, state, c, town):
				total += ArmySystem.power(repo, state, c, "attack")
	return total


## Occupation uses the same physical gate reach as a real town assault.
static func _at_gate(repo: DataRepository, state: GameState, town: String, hosts: Array) -> bool:
	for h: String in hosts:
		for c: String in EnemyAi.live_regiments(repo, state, h):
			if deployed_at(repo, state, c, town) and BattleSystem.town_contact(repo, state, town, c) == town:
				return true
	return false


## Fit defenders of the entire town, including its seat and outer camps.
static func garrison_fit(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for p: String in EnemyAi.garrison_of(repo, state, town):
		total += ArmySystem.fit_count(repo, state, p)
	return total


## The garrison's power: each regiment that garrisons the town
## (EnemyAi.garrison_of), ArmySystem.power "defend" — the town's works in it.
static func defend_power(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for p: String in EnemyAi.garrison_of(repo, state, town):
		total += ArmySystem.power(repo, state, p, "defend")
	return total


## True when the town STARVES: its own stores (TownStores: crown, lord and
## house) are spent AND its garrison's hungriest regiment has no day in hand
## (ArmySystem.days_in_hand) — the men eat what they carry first. A town with
## no garrison does not.
static func starving(repo: DataRepository, state: GameState, town: String) -> bool:
	var st := TownStores.stock_of(state, town)
	if int(st["crown"]) + int(st["lord"]) + int(st["house"]) > 0:
		return false
	var garrison := EnemyAi.garrison_of(repo, state, town)
	if garrison.is_empty():
		return false
	var least := -1
	for p: String in garrison:
		var days := ArmySystem.days_in_hand(int(state.regiments[p].get("supplies", 0)),
			ArmySystem.supply_use(repo, ArmySystem.regiment(repo, p, state), state))
		least = days if least < 0 else mini(least, days)
	return least <= 0


## The events settle_day returns that make a letter's line: the siege_* kinds
## but the quiet day's wearing down, and a fall's cost (defeat_*, DefeatSystem);
## host_mode events are EnemyAi's.
static func news(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		var k := String(e.get("kind", ""))
		return k == "end" or (k.begins_with("siege_") and k != "siege_day") or k.begins_with("defeat_"))


## The sieges' day, run once a day right AFTER BattleSystem.settle_day (an
## assault is in that day's `battle_events`). In order:
##  1. a reserve follows its main host: out of a SIEGE when it goes home
##     (WITHDRAW, RETREAT) or takes the town (HOLD), out of a HOLD when it goes
##     home;
##  2. each town's siege, by its leading host (lead_of; it takes over any
##     figures another besieger kept — a reserve that sat down first — and a
##     reserve beside its main host adds its columns): the town no longer the
##     crown's → the besiegers WITHDRAW (no progress, no capture); today's
##     assault rounds (a tier `repulsed`: less siege_assault_fail_permille,
##     never below 0; `breach`, or the besiegers keeping the field: 1000); the
##     a defended town falls at 1000; with no fit defenders left a real
##     column must reach its gate to occupy it (no progress); else the day's gain,
##     and every siege_assault_days days an assault is owed, armed for
##     tomorrow's battles (the flag stands while the assault's battle lasts,
##     and an owed assault that found no battle is tried again the next day);
##  3. a HOLD host whose town's manor another house holds again (taken back),
##     or with no live column left, RETREATs; a host that took a town and
##     holds it no more gives the manors back (liberated);
##  4. a host that left its siege any other way (beaten, hungry: EnemyAi) has
##     it told once as lifted.
## Every mode change is EnemyAi.set_mode's, its host_mode event ({type}) among
## the returned events. The siege's own events: {kind, host, town, day,
## progress, ...}: siege_begin and siege_day {attack, defend, gain, starving},
## siege_starving, siege_repulsed {lost}, siege_fallen {days, reason,
## garrison_out}, siege_undefended, siege_lifted {why}, siege_liberated {why};
## after a siege_fallen, its cost (DefeatSystem.on_town_lost: defeat_town_lost).
static func settle_day(repo: DataRepository, state: GameState, battle_events: Array = []) -> Array:
	var events: Array = []
	EnemyAi.ensure_deployments(repo, state, events)
	if state.ai_hosts.is_empty():
		return events
	follow_main(repo, state, events)
	for h: String in EnemyAi.host_codes(state):
		var mind: Dictionary = state.ai_hosts[h]
		var mode := String(mind["mode"])
		if mode == SIEGE:
			var town := String(mind.get("target_id", ""))
			if lead_of(repo, state, town) == h or String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN:
				_siege_day(repo, state, h, battle_events, events)
		elif mode == EnemyAi.MODE_DEPLOYING:
			continue
		elif mode == HOLD:
			_hold_day(repo, state, h, events)
		else:
			if not (mind.get("occupied", {}) as Dictionary).is_empty():
				_liberate(repo, state, h, mode.to_lower(), events)
			if String(mind.get("siege_town", "")) != "":
				_lifted(repo, state, h, mode.to_lower(), events)
	return events


## Takes the besieged town of `host_code` (a host in SIEGE before a town the
## crown still holds; anything else is refused with {}), at the MANOR level:
## the town's own manor and its province's manors within
## siege_capture_radius_km of the town go to the host's kingdom's ruling house
## (MapManors.set_owner, reason "taken by <host>: siege of <town>"), each
## one's house before kept on the host's mind (`occupied`) to give it back
## when the host leaves; no province, border or capital moves. An assault
## still being fought there is called off; the garrison still standing marches
## out for the nearest town of its own (as a column falling back from a
## battle); every host before the town turns HOLD. The loss then costs the
## crown (DefeatSystem.on_town_lost: treasury, contentment, the council, the
## beat; once per loss). Returns the siege_fallen event; `events` gets the
## host_mode events, then the defeat's (defeat_town_lost).
static func capture(repo: DataRepository, state: GameState, host_code: String, events: Array = []) -> Dictionary:
	if not state.ai_hosts.has(host_code):
		return {}
	var mind: Dictionary = state.ai_hosts[host_code]
	var town := String(mind.get("target_id", ""))
	if not active(repo, state, host_code) or String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN \
			or not EnemyAi.target_held(repo, state, EnemyAi.KIND_TOWN, town):
		return {}
	if garrison_fit(repo, state, town) == 0 and not _at_gate(repo, state, town, besiegers(repo, state, town)):
		return {}
	var b: Dictionary = repo.burgs[town]
	var label := String(b.get("label", town))
	var reason := "taken by %s: siege of %s" % [host_label(repo, host_code), label]
	var days := int(mind.get("siege_days", 0))
	var progress := int(mind.get("siege_progress", 0))
	var hosts := besiegers(repo, state, town)
	# the assault under way ends with the town
	for bt: Dictionary in state.battles.duplicate():
		if String(bt["town"]) == town and _holds_hosts(state, bt, hosts):
			var winner := ""
			for side: String in BattleSystem.SIDES:
				for unit: String in bt.get(side, []):
					if ArmySystem.realm_of(repo, unit, state) == _kingdom_of(repo, state, host_code): winner = side
			events.append(BattleSystem.call_off(state, int(bt["id"]), repo, winner))
	var garrison := EnemyAi.garrison_of(repo, state, town)
	var house := _house_of(repo, _kingdom_of(repo, state, host_code))
	var occupied: Dictionary = {}
	if house != "":
		for cell: int in taken_cells(repo, state, town):
			var was := MapManors.owner_of(repo, state, cell)
			if MapManors.set_owner(repo, state, cell, house, reason):
				occupied[str(cell)] = was
	mind["occupied"] = occupied
	mind["occupied_house"] = house
	var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	var out := 0
	for p: String in garrison:
		if ArmySystem.fit_count(repo, state, p) > 0:
			BattleSystem.march_out(repo, state, p, at)
			out += 1
	for h: String in hosts:
		EnemyAi.set_mode(state, h, HOLD, "took " + label, events)
		state.ai_hosts[h]["siege_town"] = ""
	# what the fall costs the crown, once the manors have moved (spec §6)
	events.append_array(DefeatSystem.on_town_lost(repo, state, town, host_code))
	return {"kind": "siege_fallen", "host": host_code, "town": town, "day": state.absolute_day(),
		"progress": maxi(progress, 1000), "days": days, "reason": reason, "garrison_out": out}


## The manors a capture of `town` takes: its own manor (EnemyAi.target_cell)
## and its province's manors whose centre lies within siege_capture_radius_km
## of the town's point, excluding other towns' own manors, in cell order.
static func taken_cells(repo: DataRepository, state: GameState, town: String) -> Array:
	var b: Dictionary = repo.burgs.get(town, {})
	var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	var r := int(round(repo.bal("siege_capture_radius_km") * 1000.0))
	var own := EnemyAi.target_cell(repo, state, EnemyAi.KIND_TOWN, town)
	var other_towns := {}
	for other: String in repo.burgs:
		if other != town:
			other_towns[EnemyAi.target_cell(repo, state, EnemyAi.KIND_TOWN, other)] = true
	var out: Array = []
	for cell: int in MapManors.manors_of_province(repo, String(b.get("province_code", "")), state):
		var m := ArmySystem.pack_to_metres(repo, MapTerrain.cell_center(repo, repo.cells[cell]))
		var dx := m.x - at.x
		var dy := m.y - at.y
		if cell == own or (not other_towns.has(cell) and dx * dx + dy * dy <= r * r):
			out.append(cell)
	if own >= 0 and not own in out:
		out.append(own)
	out.sort()
	return out


## A host in words for a reason: "<raider realm>'s <role> host".
static func host_label(repo: DataRepository, host_code: String) -> String:
	var role := EnemyAi.role_of(repo, host_code)
	return "%s's %s host" % [repo.realm_label("raider_realm"), role if role != "" else host_code]


## --- inside ------------------------------------------------------------------

static func active(repo: DataRepository, state: GameState, host: String) -> bool:
	var mind: Dictionary = state.ai_hosts.get(host, {})
	if String(mind.get("mode", "")) != SIEGE or not bool((mind.get("deployment", {}) as Dictionary).get("complete", false)):
		return false
	var town := String(mind.get("target_id", ""))
	if String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN or town.is_empty():
		return false
	for c: String in EnemyAi.live_regiments(repo, state, host):
		if deployed_at(repo, state, c, town):
			return true
	return false


static func _sits_before(repo: DataRepository, state: GameState, host: String, town: String) -> bool:
	return active(repo, state, host) and String(state.ai_hosts[host].get("target_id", "")) == town


## A reserve follows its main host: out of a SIEGE when the main host goes
## home (WITHDRAW, RETREAT) or holds the town it took (HOLD); out of a HOLD
## when the main host goes home. Run by settle_day and again at the end of
## EnemyAi.step_day, so a reserve follows its main host home the SAME day,
## before the day's battles (a host going home strikes no more blows).
static func follow_main(repo: DataRepository, state: GameState, events: Array) -> void:
	var lead := EnemyAi.main_host(repo, state)
	if lead == "":
		return
	var main_mode := String(state.ai_hosts[lead]["mode"])
	for h: String in EnemyAi.host_codes(state):
		if EnemyAi.role_of(repo, h) != EnemyAi.ROLE_RESERVE:
			continue
		var mode := String(state.ai_hosts[h]["mode"])
		if mode == SIEGE and main_mode == HOLD:
			EnemyAi.set_mode(state, h, HOLD, "holds the town with the main host", events)
			state.ai_hosts[h]["siege_town"] = ""
		elif mode in [EnemyAi.MODE_DEPLOYING, SIEGE, HOLD] and main_mode in [WITHDRAW, RETREAT]:
			_go_home(repo, state, h, main_mode, "the main host is going home", events)


## A host leaves for home (RETREAT or WITHDRAW, EnemyAi.set_mode) and its
## columns are sent there at once.
static func _go_home(repo: DataRepository, state: GameState, host_code: String, mode: String, why: String,
		events: Array) -> void:
	EnemyAi.set_mode(state, host_code, mode, why, events)
	EnemyAi.march_host(repo, state, host_code)


## The lead host takes over what another besieger of the town kept (the
## reserve that sat down first): the most progress and days, an owed assault,
## the hunger told; the other keeps none.
static func _adopt(state: GameState, lead: String, hosts: Array) -> void:
	var mind: Dictionary = state.ai_hosts[lead]
	for x: String in hosts:
		if x == lead:
			continue
		var m: Dictionary = state.ai_hosts[x]
		if int(m.get("siege_days", 0)) == 0 and int(m.get("siege_progress", 0)) == 0:
			continue
		mind["siege_progress"] = maxi(int(mind.get("siege_progress", 0)), int(m.get("siege_progress", 0)))
		mind["siege_days"] = maxi(int(mind.get("siege_days", 0)), int(m.get("siege_days", 0)))
		mind["assault_due"] = maxi(int(mind.get("assault_due", 0)), int(m.get("assault_due", 0)))
		mind["starved"] = maxi(int(mind.get("starved", 0)), int(m.get("starved", 0)))
		m["siege_progress"] = 0
		m["siege_days"] = 0
		m["assault_due"] = 0
		m["starved"] = 0
		m["siege_town"] = ""


## One town's siege day, kept by its leading host `h`.
static func _siege_day(repo: DataRepository, state: GameState, h: String, battle_events: Array, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[h]
	var town := String(mind.get("target_id", ""))
	var hosts := besiegers(repo, state, town)
	if hosts.is_empty():
		hosts = [h]
	var today := state.absolute_day()
	if String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN \
			or not EnemyAi.target_held(repo, state, EnemyAi.KIND_TOWN, town):
		# the town is no longer the crown's: nothing to besiege, nothing to take
		for x: String in hosts:
			_go_home(repo, state, x, WITHDRAW, "the town is no longer the enemy's to take", events)
		_lifted(repo, state, h, "lost", events)
		for x: String in hosts:
			state.ai_hosts[x]["siege_town"] = ""
		return
	_adopt(state, h, hosts)
	mind["siege_town"] = town
	var progress := int(mind.get("siege_progress", 0))
	# today's assault, round by round
	var a := _assault_day(repo, state, town, hosts, battle_events)
	if bool(a["fought"]):
		mind["assault_due"] = 0
	if bool(a["breach"]):
		progress = 1000
	elif int(a["checks"]) > 0:
		var fail := int(repo.bal("siege_assault_fail_permille")) * int(a["checks"])
		var lost := mini(progress, fail)
		progress -= lost
		events.append({"kind": "siege_repulsed", "host": h, "town": town, "day": today, "progress": progress,
			"lost": lost})
	mind["siege_progress"] = progress
	if garrison_fit(repo, state, town) == 0:
		# An established siege remains an occupation order when its defenders
		# depart. A camp in the outer ring has not yet occupied the town.
		if _at_gate(repo, state, town, hosts):
			_fall(repo, state, h, hosts, events)
			return
		for x: String in hosts:
			state.ai_hosts[x]["assault"] = 0
			EnemyAi.march_host(repo, state, x)
		return
	if progress >= 1000:
		_fall(repo, state, h, hosts, events)
		return
	var att := attack_power(repo, state, town)
	var def := defend_power(repo, state, town)
	var hungry := starving(repo, state, town)
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
	var ev := capture(repo, state, h, events)
	if not ev.is_empty():
		# the fall is told before what it costs (capture appended the defeat's events)
		var at := events.size()
		while at > 0 and String((events[at - 1] as Dictionary).get("kind", "")).begins_with("defeat_"):
			at -= 1
		events.insert(at, ev)
	for x: String in hosts:
		state.ai_hosts[x]["siege_town"] = ""


## A HOLD host: when the town's manor is another house's again (taken back)
## or it has no live column left to hold it, it RETREATs and gives back what
## it took.
static func _hold_day(repo: DataRepository, state: GameState, h: String, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[h]
	var town := String(mind.get("target_id", ""))
	var why := ""
	var house := String(mind.get("occupied_house", ""))
	var cell := EnemyAi.target_cell(repo, state, EnemyAi.KIND_TOWN, town)
	if house != "" and cell >= 0 and (mind.get("occupied", {}) as Dictionary).has(str(cell)) \
			and MapManors.owner_of(repo, state, cell) != house:
		why = "the town was taken back"
	elif EnemyAi.live_regiments(repo, state, h).is_empty():
		why = "no column left to hold the town"
	if why == "":
		return
	_go_home(repo, state, h, RETREAT, why, events)
	_liberate(repo, state, h, "retreat", events)


## A host that took a town and holds it no more gives its manors back: each
## manor its house still holds returns to the house it had (MapManors.set_owner,
## reason "liberated: <host> left <town>"); a manor someone took back already
## stays as it is. Told once as siege_liberated.
static func _liberate(repo: DataRepository, state: GameState, h: String, why: String, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[h]
	var occupied: Dictionary = mind.get("occupied", {})
	if occupied.is_empty():
		return
	var town := String(mind.get("target_id", ""))
	var house := String(mind.get("occupied_house", ""))
	var reason := "liberated: %s left %s" % [host_label(repo, h),
		String((repo.burgs.get(town, {}) as Dictionary).get("label", town))]
	var cells: Array = occupied.keys()
	cells.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in cells:
		var cell := int(key)
		if MapManors.owner_of(repo, state, cell) == house:
			MapManors.set_owner(repo, state, cell, String(occupied[key]), reason)
	mind["occupied"] = {}
	mind["occupied_house"] = ""
	events.append({"kind": "siege_liberated", "host": h, "town": town, "day": state.absolute_day(),
		"progress": 0, "why": why})


## A siege that ended otherwise (the host beaten, hungry, gone home) told once:
## siege_lifted {why}, one line a town a day.
static func _lifted(repo: DataRepository, state: GameState, h: String, why: String, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[h]
	var town := String(mind.get("siege_town", ""))
	if town == "":
		town = String(mind.get("target_id", ""))
	mind["siege_town"] = ""
	if town == "" or besieged(repo, state, town):
		return
	for e: Dictionary in events:
		if String(e.get("kind", "")) == "siege_lifted" and String(e["town"]) == town:
			return
	events.append({"kind": "siege_lifted", "host": h, "town": town, "day": state.absolute_day(),
		"progress": 0, "why": why})


## Today's assault on `town`, from the day's battle events: the battles at the
## town a column of the besieging hosts fought in. Each ROUND the besiegers
## fought as attackers moves the siege by its tier's `siege` column
## (data/battle/battle_outcomes.csv: `repulsed` a check, `breach` the walls taken); an
## assault that ENDED with the besiegers keeping the field is a breach too
## (the garrison broke or left). {fought, checks, breach}.
static func _assault_day(repo: DataRepository, state: GameState, town: String, hosts: Array,
		battle_events: Array) -> Dictionary:
	var effect: Dictionary = {}
	for row: Dictionary in repo.battle_outcomes:
		effect[String(row["tier"])] = String(row.get("siege", ""))
	var out := {"fought": false, "checks": 0, "breach": false}
	for e: Dictionary in battle_events:
		var kind := String(e.get("kind", ""))
		if not kind in ["round", "end"] or String(e.get("town", "")) != town:
			continue
		var side := _hosts_side(state, e, hosts)
		if side == "":
			continue
		out["fought"] = true
		if kind == "round" and side == "att":
			match String(effect.get(String(e["tier"]), "")):
				TIER_REPULSED:
					out["checks"] = int(out["checks"]) + 1
				TIER_BREACH:
					out["breach"] = true
		elif kind == "end" and String(e["winner"]) == side:
			out["breach"] = true
	return out


## The side ("att" / "def") of a battle event the besieging hosts fought on;
## "" when none of their columns is in it.
static func _hosts_side(state: GameState, e: Dictionary, hosts: Array) -> String:
	for side: String in BattleSystem.SIDES:
		for c: Variant in e.get(side, []):
			if _of_hosts(state, String(c), hosts):
				return side
	for l: Dictionary in e.get("left", []):
		if _of_hosts(state, String(l["code"]), hosts):
			return String(l["side"])
	return ""


## True while a battle at the town holds a column of the besieging hosts.
static func _assault_running(state: GameState, town: String, hosts: Array) -> bool:
	for b: Dictionary in state.battles:
		if String(b["town"]) == town and _holds_hosts(state, b, hosts):
			return true
	return false


static func _holds_hosts(state: GameState, b: Dictionary, hosts: Array) -> bool:
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
		var k := String(ArmySystem.regiment(repo, c, state).get("kingdom_code", ""))
		if k != "" and repo.kingdoms.has(k):
			return k
	return repo.resolve_realm("raider_realm")


## A kingdom's ruling house: the house of the province its capital stands in
## (MapObjects.house_name_of); "" with none.
static func _house_of(repo: DataRepository, kingdom: String) -> String:
	var cap := String((repo.kingdoms.get(kingdom, {}) as Dictionary).get("capital_burg", ""))
	var prov := String((repo.burgs.get(cap, {}) as Dictionary).get("province_code", ""))
	return MapObjects.house_name_of(repo, prov) if prov != "" else ""
