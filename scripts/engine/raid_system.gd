class_name RaidSystem
extends RefCounted
## Raiding and spoils (spec docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md
## §5.3). A host in mode RAID (EnemyAi sets it on arrival at an open manor or a
## town with no garrison; SiegeSystem when a garrison marches off) that stands
## at its target lives off it, a day at a time:
##
##   cap   = month x raid_plunder_permille / 1000      (the manor's share)
##   take  = min(cap, month x raid_plunder_permille x n / (1000 x 30)) - taken
##
## `month` is the manor's MONTH in whole gold — its tax and its goods' worth,
## ManorBars.worth_of(ManorEconomy.line_of(...)), read, never rounded again
## (invariant 11) — `n` the host's raid days on the manor, `taken` what it has
## had of it: whole gold every day, the remainders carried on the running sum,
## and never more than the share of the month from one manor (summed over
## every host). Of the take, raid_supply_permille is FOOD: units at a supply
## unit's gold (army_supply_gold_permille), loaded into the host's live columns
## by their free room (never past army_supply_max_days); the rest — and what
## they cannot carry — is the host's `plunder`. The crown's books lose it as a
## ledger line WITH a reason (Ruling 4, WorldLedger.apply, source "raid"): the
## lord's purse the whole take when the crown controls the manor's province,
## else the treasury its crown_share_permille of it (on the running sum). The
## first take from a manor marks it `Raided` (Hazards, public, id
## raided_<cell>). A host that has stripped its manor bare — or whose target is
## no longer the crown's — sets out again (ADVANCE, no target, thinks at once)
## and never chooses that manor again (EnemyAi.candidates skips it).
##
## A host BEATEN by the crown (a column routed, retreating or broken in a
## battle, BattleSystem's `left`) hands battle_spoils_permille of its plunder to
## the crown's strategic stores, with its reason; its plunder is gone, so it
## pays once. Whole numbers, host code order, no random number.
##
## Mind fields (GameState.ai_hosts[h], saved): `plunder` (gold), `raided`
## (manor cell as a string -> {days, taken}).

const RAID := "RAID"
const ADVANCE := "ADVANCE"
const KIND := "Raided"
## How a column leaves a battle beaten (BattleSystem._exit_why).
const BEATEN := ["rout", "retreat", "broken"]


## The share of a manor's month a raid can take: month x permille / 1000.
static func cap_of(month: int, permille: int) -> int:
	@warning_ignore("integer_division")  # whole gold
	return maxi(0, month) * maxi(0, permille) / 1000


## One day's take from a manor of `month` gold on the host's day `days_done` + 1
## there, `taken` already had: the running sum's share of the cap, rounded down
## once, less what was taken; never below 0.
static func take_on(month: int, permille: int, days_done: int, taken: int) -> int:
	@warning_ignore("integer_division")  # whole gold, the remainder carried
	var due := maxi(0, month) * maxi(0, permille) * (days_done + 1) / (1000 * Calendar.DAYS_PER_TICK)
	return maxi(0, mini(cap_of(month, permille), due) - taken)


## The food a take of `take` gold makes: supply_permille of it, in units at
## `gold_permille` (a unit's gold, per mille).
static func food_units(take: int, supply_permille: int, gold_permille: int) -> int:
	@warning_ignore("integer_division")  # whole units
	return maxi(0, take) * maxi(0, supply_permille) / maxi(1, gold_permille)


## The whole gold `units` of food cost the plunder (a part of a gold is a whole one).
static func food_gold(units: int, gold_permille: int) -> int:
	@warning_ignore("integer_division")  # rounded up
	return (maxi(0, units) * maxi(0, gold_permille) + 999) / 1000


## A manor's month in whole gold: ManorEconomy.line_of's tax and goods' worth.
static func month_of(repo: DataRepository, state: GameState, cell: int) -> int:
	return ManorBars.worth_of(ManorEconomy.line_of(repo, state, cell, state.tick))


## What every host has taken of manor `cell`.
static func taken_of(state: GameState, cell: int) -> int:
	var key := str(cell)
	var total := 0
	for h: Variant in state.ai_hosts:
		var rec: Dictionary = ((state.ai_hosts[h] as Dictionary).get("raided", {}) as Dictionary).get(key, {})
		total += int(rec.get("taken", 0))
	return total


## True when a host has raided manor `cell` and nothing of its share is left.
static func stripped(repo: DataRepository, state: GameState, cell: int) -> bool:
	var key := str(cell)
	var raided := false
	for h: Variant in state.ai_hosts:
		raided = raided or ((state.ai_hosts[h] as Dictionary).get("raided", {}) as Dictionary).has(key)
	if not raided:
		return false
	return taken_of(state, cell) >= cap_of(month_of(repo, state, cell), int(repo.bal("raid_plunder_permille")))


## The Raided hazard's id for manor `cell`.
static func hazard_id(cell: int) -> String:
	return "raided_%d" % cell


## Today's take of a host in RAID at its target (0 for anything else), with
## all that goes with it: the food loaded, the plunder, the crown's ledger
## line, the Raided hazard on the first take.
static func day_take(repo: DataRepository, state: GameState, host_code: String) -> int:
	return int(_take(repo, state, host_code).get("take", 0))


## The crown beat `host_code` at `place`: battle_spoils_permille of its plunder
## into the crown's strategic stores (WorldLedger, reason "spoils: <host>
## routed at <place>"), its plunder gone. 0 for a winner that is not the
## player's realm, or a host with no plunder; once (nothing is left after).
static func spoils(repo: DataRepository, state: GameState, host_code: String, winner: String,
		place: String = "") -> int:
	if not state.ai_hosts.has(host_code) or winner != repo.resolve_realm("player_realm"):
		return 0
	var mind: Dictionary = state.ai_hosts[host_code]
	var plunder := int(mind.get("plunder", 0))
	if plunder <= 0:
		return 0
	@warning_ignore("integer_division")  # whole gold
	var got := plunder * int(repo.bal("battle_spoils_permille")) / 1000
	mind["plunder"] = 0
	if got > 0:
		WorldLedger.apply(repo, state, "metrics.strategic", float(got),
			"spoils: %s routed at %s" % [SiegeSystem.host_label(repo, host_code), place], "spoils")
	return got


## The events that make a letter's line: raid_begin and raid_spoils (the quiet
## raid_day and the host_mode events are not).
static func news(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		return String(e.get("kind", "")) in ["raid_begin", "raid_spoils"])


## The raids' day, run once a day right after SiegeSystem.settle_day (given the
## day's battle events). Host code order:
##  1. a host beaten by the crown today pays its spoils (raid_spoils {host,
##     spoils, plunder, place, place_x_m, place_y_m});
##  2. a host in RAID takes its day (raid_begin {host, cell, place, ...} on its
##     first day at a manor, raid_day {host, cell, take, food, plunder, debit,
##     purse} every day it took);
##  3. a host in RAID whose manor is stripped bare or no longer the crown's
##     sets out again: ADVANCE, target dropped, think_day 0 (EnemyAi.set_mode,
##     its host_mode event among the returned).
static func settle_day(repo: DataRepository, state: GameState, battle_events: Array = []) -> Array:
	var events: Array = []
	if state.ai_hosts.is_empty():
		return events
	var beaten := _beaten(state, battle_events)
	var today := state.absolute_day()
	for h: String in EnemyAi.host_codes(state):
		var mind: Dictionary = state.ai_hosts[h]
		if beaten.has(h):
			var b: Dictionary = beaten[h]
			var plunder := int(mind.get("plunder", 0))
			var place := BattleSystem.place_label(repo, state, b)
			var got := spoils(repo, state, h, repo.resolve_realm("player_realm"), place)
			if got > 0:
				events.append({"kind": "raid_spoils", "host": h, "day": today, "spoils": got, "plunder": plunder,
					"place": place, "place_x_m": int(b["place_x_m"]), "place_y_m": int(b["place_y_m"])})
		if String(mind["mode"]) != RAID:
			continue
		var r := _take(repo, state, h)
		if not r.is_empty():
			var at := EnemyAi.target_point_m(repo, String(mind["target_kind"]), String(mind["target_id"]))
			if bool(r["begun"]):
				events.append({"kind": "raid_begin", "host": h, "cell": int(r["cell"]), "day": today,
					"place": Intel.place_label(repo, state, ArmySystem.metres_to_pack(repo, at)),
					"place_x_m": at.x, "place_y_m": at.y})
			events.append({"kind": "raid_day", "host": h, "cell": int(r["cell"]), "day": today,
				"take": int(r["take"]), "food": int(r["food"]), "plunder": int(mind.get("plunder", 0)),
				"debit": int(r["debit"]), "purse": String(r["purse"])})
		var why := _done_why(repo, state, h)
		if why != "":
			mind["target_kind"] = ""
			mind["target_id"] = ""
			mind["think_day"] = 0
			EnemyAi.set_mode(state, h, ADVANCE, why, events)
	return events


## --- inside ------------------------------------------------------------------

## The host's target manor cell (a town's own manor), -1 for none.
static func _cell_of(repo: DataRepository, state: GameState, mind: Dictionary) -> int:
	var id := String(mind.get("target_id", ""))
	if id == "":
		return -1
	return EnemyAi.target_cell(repo, state, String(mind.get("target_kind", "")), id)


## Why a RAIDing host leaves its target, "" while it stays: the target no
## longer the crown's, or its manor stripped bare.
static func _done_why(repo: DataRepository, state: GameState, h: String) -> String:
	var mind: Dictionary = state.ai_hosts[h]
	var cell := _cell_of(repo, state, mind)
	if cell < 0 or not EnemyAi.target_held(repo, state, String(mind["target_kind"]), String(mind["target_id"])):
		return "the target is no longer the enemy's"
	if stripped(repo, state, cell):
		return "the manor is stripped bare"
	return ""


## True while a host can raid its target today: a live column stands at it
## (within battle_contact_km of its point, or a town's reach), none of its
## columns is in a battle or falling back beaten.
static func _at_target(repo: DataRepository, state: GameState, h: String, mind: Dictionary) -> bool:
	var live := EnemyAi.live_regiments(repo, state, h)
	if live.is_empty():
		return false
	for c: String in EnemyAi.regiments_of(state, h):
		if int((state.foes[c] as Dictionary).get("disengaging", 0)) == 1 \
				or not BattleSystem.battle_of(state, c).is_empty():
			return false
	var kind := String(mind["target_kind"])
	var id := String(mind["target_id"])
	var at := EnemyAi.target_point_m(repo, kind, id)
	var reach := int(round(repo.bal("battle_contact_km") * 1000.0))
	for c: String in live:
		if kind == EnemyAi.KIND_TOWN and SiegeSystem.at_town(repo, state, c, id):
			return true
		var e: Dictionary = state.foes[c]
		var dx := int(e["x_m"]) - at.x
		var dy := int(e["y_m"]) - at.y
		if dx * dx + dy * dy <= reach * reach:
			return true
	return false


## A host's day at its target: {} when it takes nothing today (not raiding,
## not there, the target lost); else {cell, take, food, debit, purse, begun}.
static func _take(repo: DataRepository, state: GameState, h: String) -> Dictionary:
	if not state.ai_hosts.has(h):
		return {}
	var mind: Dictionary = state.ai_hosts[h]
	if String(mind["mode"]) != RAID:
		return {}
	var cell := _cell_of(repo, state, mind)
	if cell < 0 or not EnemyAi.target_held(repo, state, String(mind["target_kind"]), String(mind["target_id"])) \
			or not _at_target(repo, state, h, mind):
		return {}
	var permille := int(repo.bal("raid_plunder_permille"))
	var month := month_of(repo, state, cell)
	var key := str(cell)
	var raided: Dictionary = mind.get("raided", {})
	var rec: Dictionary = raided.get(key, {"days": 0, "taken": 0})
	var before := int(rec["taken"])
	var take := take_on(month, permille, int(rec["days"]), before)
	take = mini(take, maxi(0, cap_of(month, permille) - taken_of(state, cell)))
	var begun := int(rec["days"]) == 0
	raided[key] = {"days": int(rec["days"]) + 1, "taken": before + take}
	mind["raided"] = raided
	_mark(repo, state, cell, h)
	var food := _feed(repo, state, h, take)
	mind["plunder"] = int(mind.get("plunder", 0)) + take - int(food["gold"])
	var debit := _debit(repo, state, h, cell, before, take)
	return {"cell": cell, "take": take, "food": int(food["units"]), "debit": int(debit["gold"]),
		"purse": String(debit["purse"]), "begun": begun}


## Loads the take's food into the host's live columns by their free room (never
## past army_supply_max_days, BattleSystem.apportion); {units, gold}.
static func _feed(repo: DataRepository, state: GameState, h: String, take: int) -> Dictionary:
	var gp := int(repo.bal("army_supply_gold_permille"))
	var units := food_units(take, int(repo.bal("raid_supply_permille")), gp)
	var live := EnemyAi.live_regiments(repo, state, h)
	var rooms: Array = []
	var room := 0
	for c: String in live:
		var e: Dictionary = state.foes[c]
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), state)
		var free := maxi(0, ArmySystem.max_units(repo, use) - int(e["supplies"]))
		rooms.append(free)
		room += free
	var load := mini(units, room)
	var shares := BattleSystem.apportion(rooms, load)
	for i in live.size():
		var e: Dictionary = state.foes[live[i]]
		e["supplies"] = int(e["supplies"]) + int(shares[i])
	return {"units": load, "gold": mini(take, food_gold(load, gp))}


## The crown's ledger line for the take (Ruling 4): the lord's purse the whole
## take when the crown controls the manor's province, else the treasury its
## crown_share_permille of it, on the host's running sum there. {gold, purse}.
static func _debit(repo: DataRepository, state: GameState, h: String, cell: int, before: int, take: int) -> Dictionary:
	var path := "metrics.lord_gold"
	var gold := take
	if not MapManors.crown_controls(repo, state, MapManors.province_of(repo, cell, state)):
		path = "metrics.treasury"
		var share := int(repo.bal("crown_share_permille"))
		@warning_ignore("integer_division")  # whole gold on the running sum
		gold = (before + take) * share / 1000 - before * share / 1000
	if gold > 0:
		WorldLedger.apply(repo, state, path, -float(gold),
			"raided by %s: %s" % [SiegeSystem.host_label(repo, h), MapManors.label_of(repo, cell)], "raid")
	return {"gold": gold, "purse": path.trim_prefix("metrics.")}


## The manor's Raided hazard, once (the kind's months from this tick).
static func _mark(repo: DataRepository, state: GameState, cell: int, h: String) -> void:
	var id := hazard_id(cell)
	if state.hazards.has(id):
		return
	var months := int(Hazards.kind_of(repo, KIND).get("months", 0))
	Hazards.add(state, id, KIND, "raid on " + MapManors.label_of(repo, cell), [cell], state.tick,
		state.tick + months if months > 0 else -1, "raid:" + h)


## The hosts the crown beat in today's battles: a column of theirs left a
## battle beaten (rout, retreat, broken) — host -> the round event (its place).
static func _beaten(state: GameState, battle_events: Array) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in battle_events:
		if String(e.get("kind", "")) != "round":
			continue
		for l: Dictionary in e.get("left", []):
			if not String(l.get("why", "")) in BEATEN:
				continue
			var h := String((state.foes.get(String(l["code"]), {}) as Dictionary).get("host", ""))
			if h != "" and not out.has(h):
				out[h] = e
	return out
