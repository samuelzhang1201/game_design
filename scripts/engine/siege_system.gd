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
##   progress (of 1000, on the town's record in GameState.sieges) += gain
##
## A = the besiegers' columns at the town, ArmySystem.power "attack"; D = the
## garrison's ArmySystem.power "defend" (the town's works are inside it). Every
## siege_assault_days days of siege the host STORMS the town: the assault is the
## ordinary town battle (Ruling 3), let through BattleSystem by the record's
## `assault` flag (assault_armed); each of its rounds moves the siege by its tier's `siege`
## column (data/battle/battle_outcomes.csv). At 1000, or with the garrison slain to the
## last man, the town falls — at the MANOR level (capture): the province, its
## border and its capital never move. Whole numbers, host code order, no random
## number.
##
## The figures live on the town's record (SiegeRecord, GameState.sieges:
## progress, days, assault, assault_due, starved); a besieger's mind keeps
## only siege_id, until the siege's end is told. The record's SIDES drive it
## (player siege spec §5, §7, step 3): its attacker besieges with the hosts'
## stationed columns and the record's own `units` (a crown besieger), its
## defender holds the town with defenders_of. A town taken is OCCUPIED
## (GameState.occupations[town], either side's); its holder (holder_of) is
## the occupier until it is freed.

const SIEGE := "SIEGE"
const HOLD := "HOLD"
const RETREAT := "RETREAT"
const WITHDRAW := "WITHDRAW"
const RAID := "RAID"
## The prefix of a crown besieger's events (siege_ours_begin, _day, _repulsed,
## _taken, _lifted, _liberated).
const OURS := "siege_ours_"

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


## The host leaves its town's record (SiegeRecord.leave): the figures reset
## once no host is left; `siege_id` stays for settle_day to tell the siege's
## end. EnemyAi.set_mode calls it whenever a host leaves SIEGE or DEPLOYING —
## the one place a siege's figures are cleared.
static func clear(state: GameState, host: String) -> void:
	SiegeRecord.leave(state, host)


## The record the host's mind names (live), {} for none.
static func record_of(state: GameState, host: String) -> Dictionary:
	return SiegeRecord.of_host(state, host)


## True when the host is in its record and the record's assault flag is up:
## tomorrow's battles may storm the town.
static func assault_armed(state: GameState, host: String) -> bool:
	var rec := SiegeRecord.of_host(state, host)
	return not rec.is_empty() and host in (rec["hosts"] as Array) and int(rec["assault"]) == 1


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


## The kingdom that occupies manor `cell` (took it with a town and holds it,
## GameState.occupations), "" for none — such a manor is no target of the
## crown's (EnemyAi.target_held).
static func occupier_of(state: GameState, cell: int) -> String:
	var key := str(cell)
	for town: String in state.occupations:
		var occ: Dictionary = state.occupations[town]
		if (occ["cells"] as Dictionary).has(key):
			return String(occ["occupier"])
	return ""


## The kingdom holding `town` now: its occupier (GameState.occupations), else
## its province's owner; "" for no such town.
static func holder_of(repo: DataRepository, state: GameState, town: String) -> String:
	if state != null and state.occupations.has(town):
		return String(state.occupations[town]["occupier"])
	var b: Dictionary = repo.burgs.get(town, {})
	return "" if b.is_empty() else MapOwnership.owner_of(repo, state, String(b.get("province_code", "")))


## The occupation the host `host` took (GameState.occupations, its `host`), {}
## for none: a reserve that HOLDs beside it took nothing.
static func occupation_of_host(state: GameState, host: String) -> Dictionary:
	for town: String in state.occupations:
		if String(state.occupations[town]["host"]) == host:
			return state.occupations[town]
	return {}


## Who defends `town`: the crown's garrison (EnemyAi.garrison_of) while the
## crown holds it; else the holder's foes standing at it (not marching, at_town;
## a woken unit at its post, TownMilitia.at_post, its camp's too) with fit men,
## in code order — a town's militia and woken units (TownMilitia) among them.
static func defenders_of(repo: DataRepository, state: GameState, town: String) -> Array:
	var holder := holder_of(repo, state, town)
	if holder == repo.resolve_realm("player_realm"):
		return EnemyAi.garrison_of(repo, state, town)
	var out: Array = []
	var codes: Array = state.foes.keys()
	codes.sort()
	for c: String in codes:
		if ArmySystem.realm_of(repo, c, state) == holder \
				and String(state.foes[c].get("order", "")) != ArmySystem.ORDER_MARCH \
				and ArmySystem.fit_count(repo, state, c) > 0 \
				and (at_town(repo, state, c, town) or TownMilitia.at_post(repo, state, c, town)):
			out.append(c)
	return out


## The crown's record a unit of the crown's besieges in, {} for none.
static func crown_record_of(state: GameState, code: String) -> Dictionary:
	for id: String in state.sieges:
		if code in (state.sieges[id].get("units", []) as Array):
			return state.sieges[id]
	return {}


## The town a unit of the crown's besieges while it waits for its assault: in
## a record's `units` and that record's assault flag down; "" any other time.
## Such a unit makes no contact with the town's defenders (the mirror of
## BattleSystem.siege_town_of).
static func investing(repo: DataRepository, state: GameState, code: String) -> String:
	var rec := crown_record_of(state, code)
	if rec.is_empty() or not storming(repo, state, code).is_empty():
		return ""
	return String(rec["town"])


## The town a unit of the crown's storms today: stationed at it (deployed_at)
## for a record whose assault flag is up; "" otherwise.
static func storming(repo: DataRepository, state: GameState, code: String) -> String:
	var rec := crown_record_of(state, code)
	if rec.is_empty() or int(rec["assault"]) != 1 or not deployed_at(repo, state, code, String(rec["town"])):
		return ""
	return String(rec["town"])


## The record's besieging units stationed at its town (deployed_at, fit men):
## the hosts' live columns, then its own `units`, in code order each.
static func stationed(repo: DataRepository, state: GameState, id: String) -> Array:
	var rec: Dictionary = state.sieges.get(id, {})
	if rec.is_empty():
		return []
	var town := String(rec["town"])
	var out: Array = []
	for h: String in besiegers(repo, state, town):
		for c: String in EnemyAi.live_regiments(repo, state, h):
			if deployed_at(repo, state, c, town):
				out.append(c)
	for c: String in rec.get("units", []):
		if state.regiments.has(c) and ArmySystem.fit_count(repo, state, c) > 0 and deployed_at(repo, state, c, town):
			out.append(c)
	return out


## True while record `id` is a siege under way: a host before it is active, or
## one of its own units is stationed at the town.
static func record_active(repo: DataRepository, state: GameState, id: String) -> bool:
	return not stationed(repo, state, id).is_empty()


## The besieging side of record `id` in words for a reason: the crown's
## "<player realm>'s royal army", else the leading host's (host_label).
static func side_label(repo: DataRepository, state: GameState, id: String) -> String:
	var rec: Dictionary = state.sieges.get(id, {})
	if String(rec.get("attacker", "")) == repo.resolve_realm("player_realm"):
		return "%s's royal army" % repo.realm_label("player_realm")
	return host_label(repo, lead_of(repo, state, String(rec.get("town", ""))))


## True when a foe stands at the town: within battle_contact_km of its point
## or within its reach (data/army/army_town_reach.csv) — the ring arrival uses —
## or, with the clearance on, within army_spread_reach_m: a host's columns are
## spread round their target on the camp lattice (ArmySystem._spread_foe), the
## outer rings further than the contact, and the whole host is at the town.
static func at_town(repo: DataRepository, state: GameState, code: String, town: String) -> bool:
	if BattleSystem._stored(state, code).is_empty():
		return false
	var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	var reach := maxi(int(round(repo.bal("battle_contact_km") * 1000.0)),
		int(round(float(repo.army_town_reach.get(String((repo.burgs.get(town, {}) as Dictionary).get("group", "")), 0.0)) * 1000.0)))
	if ArmyGround.clearance_on(repo):
		reach = maxi(reach, int(repo.bal("army_spread_reach_m")))
	var m := BattleSystem._at_m(repo, state, code)
	var dx := m.x - at.x
	var dy := m.y - at.y
	return dx * dx + dy * dy <= reach * reach


## Only a column actually stationed here contributes to investment or assault.
static func deployed_at(repo: DataRepository, state: GameState, code: String, town: String) -> bool:
	var e := BattleSystem._stored(state, code)
	return String(e.get("order", "")) == ArmySystem.ORDER_GARRISON and int(e.get("disengaging", 0)) == 0 \
		and at_town(repo, state, code, town)


## The besiegers' power: every live column of every host in SIEGE before the
## town that stands at it (at_town), and every unit of the town's record
## stationed there, ArmySystem.power "attack".
static func attack_power(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for h: String in besiegers(repo, state, town):
		for c: String in EnemyAi.live_regiments(repo, state, h):
			if deployed_at(repo, state, c, town):
				total += ArmySystem.power(repo, state, c, "attack")
	var rec: Dictionary = state.sieges.get(SiegeRecord.of_town(state, town), {})
	for c: String in rec.get("units", []):
		if state.regiments.has(c) and ArmySystem.fit_count(repo, state, c) > 0 and deployed_at(repo, state, c, town):
			total += ArmySystem.power(repo, state, c, "attack")
	return total


## Occupation uses the same physical gate reach as a real town assault: a
## stationed column of `hosts`, or a stationed unit of `units`, within it.
static func _at_gate(repo: DataRepository, state: GameState, town: String, hosts: Array, units: Array = []) -> bool:
	var codes: Array = []
	for h: String in hosts:
		codes.append_array(EnemyAi.live_regiments(repo, state, h))
	for c: String in units:
		if state.regiments.has(c) and ArmySystem.fit_count(repo, state, c) > 0:
			codes.append(c)
	for c: String in codes:
		if deployed_at(repo, state, c, town) and BattleSystem.town_contact(repo, state, town, c) == town:
			return true
	return false


## Fit defenders of the entire town, including its seat and outer camps
## (defenders_of).
static func garrison_fit(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for p: String in defenders_of(repo, state, town):
		total += ArmySystem.fit_count(repo, state, p)
	return total


## The defenders' power: each unit that defends the town (defenders_of),
## ArmySystem.power "defend" — a crown seat's works in it.
static func defend_power(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for p: String in defenders_of(repo, state, town):
		total += ArmySystem.power(repo, state, p, "defend")
	return total


## True when the town STARVES: its own stores (TownStores: crown, lord and
## house) are spent AND its garrison's hungriest regiment has no day in hand
## (ArmySystem.days_in_hand) — the men eat what they carry first. A town with
## no garrison does not. A town the crown does not hold starves when its
## record's stores (SiegeBlockade) are spent and defenders stand in it.
static func starving(repo: DataRepository, state: GameState, town: String) -> bool:
	if holder_of(repo, state, town) != repo.resolve_realm("player_realm"):
		var rec: Dictionary = state.sieges.get(SiegeRecord.of_town(state, town), {})
		return rec.has("stores") and int(rec["stores"]) <= 0 and not defenders_of(repo, state, town).is_empty()
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
## but the quiet day's wearing down and the crown's own sieges (siege_ours_*:
## their letters ride by the commander's courier, player siege spec §9), and a
## fall's cost (defeat_*, DefeatSystem); host_mode events are EnemyAi's.
static func news(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		var k := String(e.get("kind", ""))
		return k == "end" or (k.begins_with("siege_") and k != "siege_day" and not k.begins_with(OURS)) \
			or k.begins_with("defeat_"))


## The sieges' day, run once a day right AFTER BattleSystem.settle_day (an
## assault is in that day's `battle_events`). In order:
##  1. a reserve follows its main host: out of a SIEGE when it goes home
##     (WITHDRAW, RETREAT) or takes the town (HOLD), out of a HOLD when it goes
##     home;
##  2. each town's siege, by its leading host (lead_of; every besieger joins
##     the town's one record, SiegeRecord.ensure_for — a reserve that sat down
##     first opened it — and a reserve beside its main host adds its columns): the town no longer the
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
## {open_share, stores} (SiegeBlockade.day; stores 0 for a crown town, whose
## food is TownStores), siege_starving, siege_repulsed {lost}, siege_fallen {days, reason,
## garrison_out}, siege_undefended, siege_lifted {why}, siege_liberated {why};
## after a siege_fallen, its cost (DefeatSystem.on_town_lost: defeat_town_lost).
static func settle_day(repo: DataRepository, state: GameState, battle_events: Array = []) -> Array:
	var events: Array = []
	EnemyAi.ensure_deployments(repo, state, events)
	if state.ai_hosts.is_empty():
		events.append_array(TownMilitia.stand_down(repo, state))
		events.append_array(TownMilitia.send_back(repo, state))
		return events
	follow_main(repo, state, events)
	for h: String in EnemyAi.host_codes(state):
		var mind: Dictionary = state.ai_hosts[h]
		var mode := String(mind["mode"])
		if mode == SIEGE:
			var town := String(mind.get("target_id", ""))
			if lead_of(repo, state, town) == h or String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN:
				_siege_day(repo, state, h, "", battle_events, events)
		elif mode == EnemyAi.MODE_DEPLOYING:
			continue
		elif mode == HOLD:
			_hold_day(repo, state, h, events)
		else:
			if not occupation_of_host(state, h).is_empty():
				_liberate(repo, state, h, mode.to_lower(), events)
			if mind.has("siege_id"):
				_lifted(repo, state, h, mode.to_lower(), events)
	_crown_sieges(repo, state, battle_events, events)
	# a siege over, its militia stand down and its woken units go back (spec §5, §8)
	events.append_array(TownMilitia.stand_down(repo, state))
	events.append_array(TownMilitia.send_back(repo, state))
	return events


## The crown's sieges (records with `units` and the player's realm as
## attacker, id order) after the hosts': each active one runs the shared day
## (_siege_day, no lead host); one whose units are all gone is lifted. Then
## each town the crown occupies is held or freed (_crown_hold_day).
static func _crown_sieges(repo: DataRepository, state: GameState, battle_events: Array, events: Array) -> void:
	var player := repo.resolve_realm("player_realm")
	var ids: Array = state.sieges.keys()
	ids.sort()
	for id: String in ids:
		if not state.sieges.has(id):
			continue
		var rec: Dictionary = state.sieges[id]
		if String(rec["attacker"]) != player or (rec.get("units", []) as Array).is_empty():
			continue
		if record_active(repo, state, id):
			_siege_day(repo, state, "", id, battle_events, events)
		elif not (rec["units"] as Array).any(func(c: String) -> bool:
				return state.regiments.has(c) and ArmySystem.fit_count(repo, state, c) > 0):
			_crown_lifted(repo, state, id, "no unit left", events)
	var towns: Array = state.occupations.keys()
	towns.sort()
	for town: String in towns:
		if String(state.occupations[town]["occupier"]) == player:
			_crown_hold_day(repo, state, town, events)


## Takes the besieged town of `host_code` (a host in SIEGE before a town the
## crown still holds; anything else is refused with {}), at the MANOR level:
## the town's own manor and its province's manors within
## siege_capture_radius_km of the town go to the host's kingdom's ruling house
## (MapManors.set_owner, reason "taken by <host>: siege of <town>"), each
## one's house before kept on the town's occupation (GameState.occupations,
## its `host` this host) to give it back when the host leaves; no province,
## border or capital moves (_take, _occupy). An assault
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
	return _take(repo, state, town, _kingdom_of(repo, state, host_code), repo.resolve_realm("player_realm"),
		host_label(repo, host_code), host_code, besiegers(repo, state, town), [], events)


## The fall of `town` to `attacker`, either side's (player siege spec §7): the
## assault under way there is called off (the attacker's side the victor); the
## manors move (_occupy: a fresh occupation, or the town taken back from its
## occupier); the defenders leave — a crown garrison marches out, an
## occupying host in HOLD there turns home; the besieging hosts turn HOLD;
## the crown's record is closed. A fall of a crown town then costs the crown
## (DefeatSystem.on_town_lost). Returns siege_fallen (siege_ours_taken for a
## crown besieger); `events` gets the host_mode events, then the defeat's.
static func _take(repo: DataRepository, state: GameState, town: String, attacker: String, defender: String,
		by: String, lead: String, hosts: Array, units: Array, events: Array) -> Dictionary:
	var player := repo.resolve_realm("player_realm")
	var label := String((repo.burgs.get(town, {}) as Dictionary).get("label", town))
	var id := SiegeRecord.of_town(state, town)
	var rec: Dictionary = state.sieges.get(id, {})
	var days := int(rec.get("days", 0))
	var progress := int(rec.get("progress", 0))
	# the assault under way ends with the town
	for bt: Dictionary in state.battles.duplicate():
		if String(bt["town"]) == town and _holds_side(state, bt, hosts, units):
			var winner := ""
			for side: String in BattleSystem.SIDES:
				for unit: String in bt.get(side, []):
					if ArmySystem.realm_of(repo, unit, state) == attacker: winner = side
			events.append(BattleSystem.call_off(state, int(bt["id"]), repo, winner))
	var garrison := defenders_of(repo, state, town)
	# the town's month, read before its manors move (the sack's measure)
	var month := RaidSystem.month_of(repo, state, EnemyAi.target_cell(repo, state, EnemyAi.KIND_TOWN, town)) \
		if attacker == player else 0
	var reason := _occupy(repo, state, town, attacker, defender, by, lead)
	var gains := {"opinion": [], "sack": 0}
	if attacker == player and String((state.occupations.get(town, {}) as Dictionary).get("occupier", "")) == player:
		# a fresh occupation of a foreign town (a retake ends the occupation instead)
		gains = _gains(repo, state, town, defender, units, month)
	var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	var out := 0
	for p: String in garrison:
		# a militia marches nowhere: it stands down once the record is gone
		if ArmySystem.fit_count(repo, state, p) > 0 and TownMilitia.town_of(state, p) == "":
			if state.regiments.has(p):
				BattleSystem.march_out(repo, state, p, at)
			out += 1
	if defender != player:
		for x: String in EnemyAi.host_codes(state):
			var mind: Dictionary = state.ai_hosts[x]
			if String(mind["mode"]) == HOLD and String(mind.get("target_id", "")) == town:
				_go_home(repo, state, x, RETREAT, "the town was taken back", events)
	for h: String in hosts:
		EnemyAi.set_mode(state, h, HOLD, "took " + label, events)
		SiegeRecord.drop(state, h)
	if attacker == player and state.sieges.has(id):
		state.sieges.erase(id)
	if defender == player:
		# what the fall costs the crown, once the manors have moved (spec §6)
		events.append_array(DefeatSystem.on_town_lost(repo, state, town, lead))
	return {"kind": (OURS + "taken") if attacker == player else "siege_fallen", "host": lead, "town": town,
		"day": state.absolute_day(), "progress": maxi(progress, 1000), "days": days, "reason": reason,
		"garrison_out": out, "opinion": gains["opinion"], "sack": gains["sack"]}


## What a capture gives the crown (spec §7), once per occupation
## (GameState.town_takes {town, day}, the occupation's day):
##  - the council: each seat +round(battle_victory_opinion x (1 + w)), w the
##    OpinionDrift.weight of TOWN_TAKEN (the mirror of DefeatSystem's loss), so
##    0..2 x base and never a loss; reason "took <town> from <realm> (supports,
##    <axis>)";
##  - the sack: when the plunder law of the lead unit (the first of `units` in
##    code order) reads allow, `month` (the town's own manor, before the fall)
##    x siege_sack_permille / 1000, whole gold rounded down, into
##    metrics.strategic (WorldLedger, source "sack", reason "sacked <town>").
## The occupied manors' lines pay their holder as any manor's do: nothing extra.
## {opinion [{character_id, delta, reason}], sack (gold)}.
static func _gains(repo: DataRepository, state: GameState, town: String, defender: String, units: Array,
		month: int) -> Dictionary:
	var none := {"opinion": [], "sack": 0}
	var occ: Dictionary = state.occupations.get(town, {})
	var key := {"town": town, "day": int(occ.get("day", state.absolute_day()))}
	if key in state.town_takes:
		return none
	state.town_takes.append(key)
	var label := String((repo.burgs.get(town, {}) as Dictionary).get("label", town))
	return {"opinion": _council_gain(repo, state, "took %s from %s" % [label, repo.realm_label(defender)]),
		"sack": _sack(repo, state, label, units, month)}


## One seat's gain: round(base x (1 + w)), w clamped to -1..1, so 0..2 x base.
static func opinion_gain(base: int, w: float) -> int:
	return roundi(float(base) * (1.0 + clampf(w, -1.0, 1.0)))


static func _council_gain(repo: DataRepository, state: GameState, what: String) -> Array:
	var out: Array = []
	var sig := OpinionDrift.signature_for(repo, "TOWN_TAKEN", {})
	var base := int(repo.bal("battle_victory_opinion"))
	var seats: Array = state.council.keys()
	seats.sort()
	for seat: String in seats:
		var id := String(state.council[seat])
		var c: Character = state.characters.get(id)
		if c == null:
			continue
		var delta := opinion_gain(base, OpinionDrift.weight(sig, c) if not sig.is_empty() else 0.0)
		if delta == 0:
			continue
		var axis := OpinionDrift.dominant_axis(sig, c.ideology) if not sig.is_empty() else "the realm"
		var reason := "%s (supports, %s)" % [what, axis]
		c.change_opinion(delta, reason, state.tick)
		out.append({"character_id": id, "delta": delta, "reason": reason})
	return out


static func _sack(repo: DataRepository, state: GameState, label: String, units: Array, month: int) -> int:
	var lead := units.duplicate()
	lead.sort()
	if lead.is_empty() or LawSystem.value(repo, state, "plunder", String(lead[0])) != "allow":
		return 0
	@warning_ignore("integer_division")  # whole gold, rounded down
	var gold := maxi(month, 0) * int(repo.bal("siege_sack_permille")) / 1000
	if gold <= 0:
		return 0
	var out := WorldLedger.apply(repo, state, "metrics.strategic", float(gold), "sacked " + label, "sack")
	return 0 if out.has("error") else int(float(out["delta"]))


## The manors of `town` move to `attacker`, with their reason (returned): a
## town taken back from the occupation that took it from `attacker` (its
## occupier the defender) gives each manor the occupier's house still holds
## back to its house before, "liberated: <by> retook <town> from <occupier>",
## and the occupation ends; else the town's manors (taken_cells) go to the
## attacker's ruling house, "taken by <by>: siege of <town>", and the town is
## occupied (GameState.occupations, the houses before kept) once a manor moved.
static func _occupy(repo: DataRepository, state: GameState, town: String, attacker: String, defender: String,
		by: String, host: String) -> String:
	var label := String((repo.burgs.get(town, {}) as Dictionary).get("label", town))
	var occ: Dictionary = state.occupations.get(town, {})
	if not occ.is_empty() and String(occ["occupier"]) == defender and String(occ["from"]) == attacker:
		var back := "liberated: %s retook %s from %s" % [by, label, String(occ["by"])]
		_give_back(repo, state, town, back)
		return back
	var reason := "taken by %s: siege of %s" % [by, label]
	var house := MapManors.crown(state) if attacker == repo.resolve_realm("player_realm") else _house_of(repo, attacker)
	if house == "":
		return reason
	var cells: Dictionary = {}
	for cell: int in taken_cells(repo, state, town):
		var was := MapManors.owner_of(repo, state, cell)
		if MapManors.set_owner(repo, state, cell, house, reason):
			cells[str(cell)] = was
	if not cells.is_empty():
		state.occupations[town] = {"town": town, "occupier": attacker, "from": defender, "house": house,
			"host": host, "by": by, "day": state.absolute_day(), "cells": cells}
	return reason


## The occupation of `town` ends: each manor its house still holds goes back
## to the house it had (MapManors.set_owner with `reason`), in cell order; a
## manor someone took back already stays as it is.
static func _give_back(repo: DataRepository, state: GameState, town: String, reason: String) -> void:
	var occ: Dictionary = state.occupations.get(town, {})
	if occ.is_empty():
		return
	var cells_was: Dictionary = occ["cells"]
	var cells: Array = cells_was.keys()
	cells.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in cells:
		var cell := int(key)
		if MapManors.owner_of(repo, state, cell) == String(occ["house"]):
			MapManors.set_owner(repo, state, cell, String(cells_was[key]), reason)
	state.occupations.erase(town)


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
			SiegeRecord.drop(state, h)
		elif mode in [EnemyAi.MODE_DEPLOYING, SIEGE, HOLD] and main_mode in [WITHDRAW, RETREAT]:
			_go_home(repo, state, h, main_mode, "the main host is going home", events)


## A host leaves for home (RETREAT or WITHDRAW, EnemyAi.set_mode) and its
## columns are sent there at once.
static func _go_home(repo: DataRepository, state: GameState, host_code: String, mode: String, why: String,
		events: Array) -> void:
	EnemyAi.set_mode(state, host_code, mode, why, events)
	EnemyAi.march_host(repo, state, host_code)


## One town's siege day: an AI record kept by its leading host `lead`, or —
## `lead` "" — the crown's record `id`. The same rules for both sides; the
## crown's has no assault timer (an assault is owed only by order, player
## siege spec §4.4) and its events are siege_ours_*.
static func _siege_day(repo: DataRepository, state: GameState, lead: String, id: String, battle_events: Array,
		events: Array) -> void:
	var crown := lead == ""
	var k := OURS if crown else "siege_"
	var rec: Dictionary = state.sieges.get(id, {})
	var mind: Dictionary = {} if crown else state.ai_hosts[lead]
	var town := String(rec["town"]) if crown else String(mind.get("target_id", ""))
	var hosts: Array = [] if crown else besiegers(repo, state, town)
	if not crown and hosts.is_empty():
		hosts = [lead]
	var units: Array = (rec.get("units", []) as Array).duplicate() if crown else []
	var today := state.absolute_day()
	if crown:
		if holder_of(repo, state, town) != String(rec["defender"]):
			_crown_lifted(repo, state, id, "lost", events)
			return
	elif String(mind.get("target_kind", "")) != EnemyAi.KIND_TOWN \
			or not EnemyAi.target_held(repo, state, EnemyAi.KIND_TOWN, town):
		# the town is no longer the crown's: nothing to besiege, nothing to take
		for x: String in hosts:
			_go_home(repo, state, x, WITHDRAW, "the town is no longer the enemy's to take", events)
		_lifted(repo, state, lead, "lost", events)
		for x: String in hosts:
			SiegeRecord.drop(state, x)
		return
	if not crown:
		# one record a town: the lead joins it first, then every besieger (a
		# reserve that sat down first opened it; its figures carry on)
		rec = SiegeRecord.ensure_for(repo, state, lead)
		for x: String in hosts:
			SiegeRecord.ensure_for(repo, state, x)
	var progress := int(rec["progress"])
	# today's assault, round by round
	var a := _assault_day(repo, state, town, hosts, units, battle_events)
	if bool(a["fought"]):
		rec["assault_due"] = 0
	if bool(a["breach"]):
		progress = 1000
	elif int(a["checks"]) > 0:
		var fail := int(repo.bal("siege_assault_fail_permille")) * int(a["checks"])
		var lost := mini(progress, fail)
		progress -= lost
		events.append({"kind": k + "repulsed", "host": lead, "town": town, "day": today, "progress": progress,
			"lost": lost})
	rec["progress"] = progress
	if garrison_fit(repo, state, town) == 0:
		# An established siege remains an occupation order when its defenders
		# depart. A camp in the outer ring has not yet occupied the town.
		if _at_gate(repo, state, town, hosts, units):
			_fall(repo, state, lead, id, hosts, events)
			return
		rec["assault"] = 0
		for x: String in hosts:
			EnemyAi.march_host(repo, state, x)
		return
	if progress >= 1000:
		_fall(repo, state, lead, id, hosts, events)
		return
	# the men's plan for today (spec §4, SiegeTactics), the engines and the
	# bombardment against the repair (§4.2), then the blockade's
	# day (spec §4.1): entries close, the stores move, and a
	# starving garrison may yield under the laws, handing the town over
	var sid := id if crown else SiegeRecord.of_town(state, town)
	SiegeTactics.day(repo, state, sid)
	SiegeTactics.bombard(repo, state, sid)
	var blockade := SiegeBlockade.day(repo, state, sid)
	if SiegeBlockade.yields(repo, state, sid) and not SiegeBlockade.hand_over(repo, state, sid).has("error"):
		_fall(repo, state, lead, id, hosts, events, true)
		return
	var att := attack_power(repo, state, town)
	var def := defend_power(repo, state, town)
	var hungry := starving(repo, state, town)
	var gain := day_gain(att, def, int(repo.bal("siege_rate")), hungry, int(repo.bal("siege_starve_bonus_permille")))
	progress = mini(1000, progress + gain)
	rec["progress"] = progress
	rec["days"] = int(rec["days"]) + 1
	var day := {"kind": k + "day", "host": lead, "town": town, "day": today, "progress": progress,
		"attack": att, "defend": def, "gain": gain, "starving": hungry,
		"open_share": int(blockade["open_share"]), "stores": int(blockade["stores"])}
	if int(rec["days"]) == 1:
		var begin := day.duplicate()
		begin["kind"] = k + "begin"
		events.append(begin)
	events.append(day)
	if hungry and int(rec["starved"]) == 0:
		rec["starved"] = 1
		events.append({"kind": k + "starving", "host": lead, "town": town, "day": today, "progress": progress})
	if progress >= 1000:
		_fall(repo, state, lead, id, hosts, events)
		return
	if not crown and int(rec["days"]) % maxi(1, int(repo.bal("siege_assault_days"))) == 0:
		rec["assault_due"] = 1
	# tomorrow's battles: an owed assault, or the assault still being fought
	rec["assault"] = 1 if int(rec["assault_due"]) == 1 or _assault_running(state, town, hosts, units) else 0


## The town falls to the record's besiegers (an AI record's leading host
## `lead`, or the crown's record `id`). `yielded`: its garrison yielded to
## hunger and is the besiegers' captives (SiegeBlockade.hand_over), so no
## column needs to stand at the gate; the fall's event carries yielded 1.
static func _fall(repo: DataRepository, state: GameState, lead: String, id: String, hosts: Array, events: Array,
		yielded := false) -> void:
	var ev: Dictionary
	if lead == "":
		var rec: Dictionary = state.sieges[id]
		ev = _take(repo, state, String(rec["town"]), String(rec["attacker"]), String(rec["defender"]),
			side_label(repo, state, id), "", [], (rec["units"] as Array).duplicate(), events)
	elif yielded:
		var town := String(state.ai_hosts[lead].get("target_id", ""))
		ev = _take(repo, state, town, _kingdom_of(repo, state, lead), repo.resolve_realm("player_realm"),
			host_label(repo, lead), lead, besiegers(repo, state, town), [], events)
	else:
		# the capture reads its host in SIEGE: every host before the town still is
		ev = capture(repo, state, lead, events)
	if yielded and not ev.is_empty():
		ev["yielded"] = 1
	if not ev.is_empty():
		# the fall is told before what it costs (capture appended the defeat's events)
		var at := events.size()
		while at > 0 and String((events[at - 1] as Dictionary).get("kind", "")).begins_with("defeat_"):
			at -= 1
		events.insert(at, ev)
	for x: String in hosts:
		SiegeRecord.drop(state, x)


## A HOLD host: when the town's manor is another house's again (taken back)
## or it has no live column left to hold it, it RETREATs and gives back what
## it took.
static func _hold_day(repo: DataRepository, state: GameState, h: String, events: Array) -> void:
	var mind: Dictionary = state.ai_hosts[h]
	var town := String(mind.get("target_id", ""))
	var why := ""
	var occ := occupation_of_host(state, h)
	var house := String(occ.get("house", ""))
	var cell := EnemyAi.target_cell(repo, state, EnemyAi.KIND_TOWN, town)
	if house != "" and cell >= 0 and (occ["cells"] as Dictionary).has(str(cell)) \
			and MapManors.owner_of(repo, state, cell) != house:
		why = "the town was taken back"
	elif EnemyAi.live_regiments(repo, state, h).is_empty():
		why = "no column left to hold the town"
	if why == "":
		return
	_go_home(repo, state, h, RETREAT, why, events)
	_liberate(repo, state, h, "retreat", events)


## A town the crown occupies: when its manor is another house's again (taken
## back) or no land unit of the crown's with fit men stands at it, the crown
## holds it no more and its manors go back (_give_back, reason "liberated:
## <the crown's army> left <town>"), told once as siege_ours_liberated.
static func _crown_hold_day(repo: DataRepository, state: GameState, town: String, events: Array) -> void:
	var occ: Dictionary = state.occupations[town]
	var cell := EnemyAi.target_cell(repo, state, EnemyAi.KIND_TOWN, town)
	var why := ""
	if cell >= 0 and (occ["cells"] as Dictionary).has(str(cell)) \
			and MapManors.owner_of(repo, state, cell) != String(occ["house"]):
		why = "the town was taken back"
	elif not state.regiments.keys().any(func(c: Variant) -> bool:
			return String(ArmySystem.regiment(repo, String(c), state).get("is_naval", "0")) != "1" \
				and ArmySystem.fit_count(repo, state, String(c)) > 0 and at_town(repo, state, String(c), town)):
		why = "no unit left in the town"
	if why == "":
		return
	_give_back(repo, state, town, "liberated: %s left %s" % [String(occ["by"]),
		String((repo.burgs.get(town, {}) as Dictionary).get("label", town))])
	events.append({"kind": OURS + "liberated", "host": "", "town": town, "day": state.absolute_day(),
		"progress": 0, "why": why})


## A host that took a town and holds it no more gives its manors back: each
## manor its house still holds returns to the house it had (MapManors.set_owner,
## reason "liberated: <host> left <town>"); a manor someone took back already
## stays as it is. Told once as siege_liberated.
static func _liberate(repo: DataRepository, state: GameState, h: String, why: String, events: Array) -> void:
	var occ := occupation_of_host(state, h)
	if occ.is_empty():
		return
	var town := String(occ["town"])
	_give_back(repo, state, town, "liberated: %s left %s" % [host_label(repo, h),
		String((repo.burgs.get(town, {}) as Dictionary).get("label", town))])
	events.append({"kind": "siege_liberated", "host": h, "town": town, "day": state.absolute_day(),
		"progress": 0, "why": why})


## A siege that ended otherwise (the host beaten, hungry, gone home) told once:
## siege_lifted {why}, one line a town a day.
static func _lifted(repo: DataRepository, state: GameState, h: String, why: String, events: Array) -> void:
	var town := String(SiegeRecord.of_host(state, h).get("town", ""))
	if town == "":
		town = String(state.ai_hosts[h].get("target_id", ""))
	SiegeRecord.drop(state, h)
	if town == "" or besieged(repo, state, town):
		return
	for e: Dictionary in events:
		if String(e.get("kind", "")) == "siege_lifted" and String(e["town"]) == town:
			return
	events.append({"kind": "siege_lifted", "host": h, "town": town, "day": state.absolute_day(),
		"progress": 0, "why": why})


## The crown's siege `id` ends without the town (lost to it, its units gone):
## the record closes, told once as siege_ours_lifted {why}.
static func _crown_lifted(repo: DataRepository, state: GameState, id: String, why: String, events: Array) -> void:
	var town := String(state.sieges[id]["town"])
	state.sieges.erase(id)
	events.append({"kind": OURS + "lifted", "host": "", "town": town, "day": state.absolute_day(),
		"progress": 0, "why": why})


## Today's assault on `town`, from the day's battle events: the battles at the
## town a besieging unit fought in (a column of `hosts`, or one of `units`).
## Each ROUND the besiegers fought as attackers moves the siege by its tier's
## `siege` column (data/battle/battle_outcomes.csv: `repulsed` a check, `breach`
## the walls taken); an assault that ENDED with the besiegers keeping the
## field is a breach too (the garrison broke or left). {fought, checks, breach}.
static func _assault_day(repo: DataRepository, state: GameState, town: String, hosts: Array, units: Array,
		battle_events: Array) -> Dictionary:
	var effect: Dictionary = {}
	for row: Dictionary in repo.battle_outcomes:
		effect[String(row["tier"])] = String(row.get("siege", ""))
	var out := {"fought": false, "checks": 0, "breach": false}
	for e: Dictionary in battle_events:
		var kind := String(e.get("kind", ""))
		if not kind in ["round", "end"] or String(e.get("town", "")) != town:
			continue
		var side := _besiegers_side(state, e, hosts, units)
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


## The side ("att" / "def") of a battle event the besiegers fought on; ""
## when none of them is in it.
static func _besiegers_side(state: GameState, e: Dictionary, hosts: Array, units: Array) -> String:
	for side: String in BattleSystem.SIDES:
		for c: Variant in e.get(side, []):
			if _of_side(state, String(c), hosts, units):
				return side
	for l: Dictionary in e.get("left", []):
		if _of_side(state, String(l["code"]), hosts, units):
			return String(l["side"])
	return ""


## True while a battle at the town holds a besieging unit.
static func _assault_running(state: GameState, town: String, hosts: Array, units: Array) -> bool:
	for b: Dictionary in state.battles:
		if String(b["town"]) == town and _holds_side(state, b, hosts, units):
			return true
	return false


static func _holds_side(state: GameState, b: Dictionary, hosts: Array, units: Array) -> bool:
	for side: String in BattleSystem.SIDES:
		for c: Variant in b[side]:
			if _of_side(state, String(c), hosts, units):
				return true
	return false


## True for a column of one of `hosts`, or one of `units`.
static func _of_side(state: GameState, code: String, hosts: Array, units: Array) -> bool:
	return code in units or String((state.foes.get(code, {}) as Dictionary).get("host", "")) in hosts


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
