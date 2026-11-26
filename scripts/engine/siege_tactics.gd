class_name SiegeTactics
extends RefCounted
## The besiegers' men and their plan (player siege spec docs/superpowers/specs/
## 2026-11-18-player-siege-design.md §3, §4 "The men pool", step 7). Each day
## the POOL is the fit men of the record's stationed besiegers (SiegeSystem.
## stationed): no wounded, no captives, no guards of prisoners, none fighting a
## battle elsewhere. The record's `alloc` (tactic -> whole men; {} = no plan
## received) never sums above it. An AI commander plans afresh each day from its
## doctrine (ai_doctrines.csv siege_<tactic>_permille); a standing plan (the
## crown's) is cut when the pool shrinks, in CUT_ORDER, each cut a reasoned line
## in the record's `history`. Whole men, fixed orders, no random number.

const TACTICS := ["blockade", "mine", "bombard", "ladders", "engines"]
const CUT_ORDER := ["engines", "ladders", "mine", "bombard", "blockade"]


## The men unit `code` gives a siege of `town` today: its fit men less its
## prisoners' guards (PrisonerBurden.guard_count); none while it fights a
## battle that is not at the town.
static func men_of(repo: DataRepository, state: GameState, code: String, town: String) -> int:
	var b := BattleSystem.battle_of(state, code)
	if not b.is_empty() and String(b.get("town", "")) != town:
		return 0
	return maxi(0, ArmySystem.fit_count(repo, state, code) - PrisonerBurden.guard_count(repo, state, code))


## Record `id`'s pool today: men_of over its stationed besiegers.
static func pool(repo: DataRepository, state: GameState, id: String) -> int:
	var rec: Dictionary = state.sieges.get(id, {})
	var total := 0
	for c: String in SiegeSystem.stationed(repo, state, id):
		total += men_of(repo, state, c, String(rec["town"]))
	return total


## Why `alloc` is no plan for `men` ("" when it is): a tactic it names is not
## one of TACTICS, a figure is not whole and non-negative, or the sum is above
## the pool.
static func refusal(alloc: Dictionary, men: int) -> String:
	var sum := 0
	for t: Variant in alloc:
		if not String(t) in TACTICS:
			return "no tactic %s" % t
		var v: Variant = alloc[t]
		if not (v is int or (v is float and v == floorf(v))) or int(v) < 0:
			return "%s: not whole men" % t
		sum += int(v)
	if sum > men:
		return "%d men planned, %d to hand" % [sum, men]
	return ""


## Every tactic's men in `alloc`, in TACTICS order (0 for one it leaves out).
static func whole(alloc: Dictionary) -> Dictionary:
	var out := {}
	for t: String in TACTICS:
		out[t] = int(alloc.get(t, 0))
	return out


## The commander receives plan `alloc` for record `id`: {alloc} stored, or
## {error} (refusal) with the plan kept.
static func allocate(repo: DataRepository, state: GameState, id: String, alloc: Dictionary) -> Dictionary:
	if not state.sieges.has(id):
		return {"error": "no siege %s" % id}
	var why := refusal(alloc, pool(repo, state, id))
	if why != "":
		return {"error": why}
	state.sieges[id]["alloc"] = whole(alloc)
	return {"alloc": state.sieges[id]["alloc"]}


## Cuts `alloc` (in place) to `men`, the excess taken in CUT_ORDER. One
## {tactic, from, to} a tactic cut; [] when it fits.
static func cut(alloc: Dictionary, men: int) -> Array:
	var over := -maxi(0, men)
	for t: String in TACTICS:
		over += int(alloc.get(t, 0))
	var out: Array = []
	for t: String in CUT_ORDER:
		var has := int(alloc.get(t, 0))
		if over <= 0:
			break
		if has <= 0:
			continue
		var take := mini(has, over)
		alloc[t] = has - take
		over -= take
		out.append({"tactic": t, "from": has, "to": has - take})
	return out


## The plan a doctrine row makes of `men`: its siege_<tactic>_permille shares
## (TownStores.apportion, largest remainder), whole men summing to `men`.
static func plan(doctrine: Dictionary, men: int) -> Dictionary:
	var weights := {}
	for t: String in TACTICS:
		weights[t] = int(doctrine.get("siege_%s_permille" % t, 0))
	return whole(TownStores.apportion(maxi(0, men), weights))


## Record `id`'s plan for today (SiegeSystem._siege_day, before the blockade):
## an AI record plans its pool by its leading host's doctrine; a standing plan
## (the crown's) is cut to the pool, each cut a line in `history`
## {day, kind alloc_cut, tactic, from, to, reason}.
static func day(repo: DataRepository, state: GameState, id: String) -> void:
	var rec: Dictionary = state.sieges[id]
	var men := pool(repo, state, id)
	if String(rec["attacker"]) != repo.resolve_realm("player_realm"):
		var lead := SiegeSystem.lead_of(repo, state, String(rec["town"]))
		rec["alloc"] = plan(EnemyAi.doctrine_of(repo, lead), men)
		return
	var alloc: Dictionary = rec.get("alloc", {})
	if alloc.is_empty():
		return
	var label := String((repo.burgs.get(String(rec["town"]), {}) as Dictionary).get("label", rec["town"]))
	var history: Array = rec.get("history", [])
	for c: Dictionary in cut(alloc, men):
		history.append({"day": state.absolute_day(), "kind": "alloc_cut", "tactic": c["tactic"],
			"from": c["from"], "to": c["to"], "reason": "siege of %s down to %d men: %s cut from %d to %d"
				% [label, men, c["tactic"], c["from"], c["to"]]})
	rec["history"] = history


## The men record `id` puts to `tactic` today: its plan's; with no plan
## received, the whole pool blockades.
static func men_for(repo: DataRepository, state: GameState, id: String, tactic: String) -> int:
	var alloc: Dictionary = state.sieges[id].get("alloc", {})
	if alloc.is_empty():
		return pool(repo, state, id) if tactic == "blockade" else 0
	return int(alloc.get(tactic, 0))
