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


## --- bombardment (spec §4.2, step 8) ----------------------------------------

## The guns unit `code` can fire: its `artillery` × fit / personnel capacity,
## whole (guns whose crews still stand).
static func fit_guns(repo: DataRepository, state: GameState, code: String) -> int:
	var reg := ArmySystem.regiment(repo, code, state)
	var guns := int(float(reg.get("artillery", 0)))
	var cap := ArmySystem.personnel_capacity(repo, reg)
	if guns <= 0 or cap <= 0:
		return 0
	@warning_ignore("integer_division")
	return guns * mini(cap, ArmySystem.fit_count(repo, state, code)) / cap


## The works after a day: `crewed` engines knock `damage` each off `integrity`
## (never below 0), then the defenders mend `repair` while it stands above 0
## (never above 1000).
static func batter(integrity: int, crewed: int, damage: int, repair: int) -> int:
	var left := maxi(0, integrity - maxi(0, crewed) * maxi(0, damage))
	return mini(1000, left + maxi(0, repair)) if left > 0 else 0


## Record `id`'s engines and bombardment today (SiegeSystem._siege_day, after
## the plan, before the blockade). A town with no works to batter
## (siege_tactics.csv bombard_damage 0) spends nothing. Else: the engines men's
## work builds engines (siege_engine_man_days each, siege_engine_gold paid on
## finishing — the crown's treasury, an AI record's leading host's plunder;
## short of it the work waits at one engine); the bombard men crew the
## stationed fit guns first, then the built engines (siege_engine_crew each);
## the walls take crewed × bombard_damage and the defenders mend
## garrison_fit × siege_repair_per_100_men / 100 (batter); every
## siege_engine_wear_days a built engine fired, one is lost; integrity at
## siege_breach_integrity or below sets breach 1 for good. Each built, worn
## engine and the breach is a reasoned `history` line.
static func bombard(repo: DataRepository, state: GameState, id: String) -> void:
	var rec: Dictionary = state.sieges[id]
	var town := String(rec["town"])
	var damage := int((repo.siege_tactics.get(TownMilitia.works_of_town(repo, town), {}) as Dictionary).get("bombard_damage", 0))
	if damage <= 0:
		return
	var label := String((repo.burgs.get(town, {}) as Dictionary).get("label", town))
	var history: Array = rec.get("history", [])
	var today := state.absolute_day()
	var need := maxi(1, int(repo.bal("siege_engine_man_days")))
	var built := int(rec.get("engines_built", 0))
	var work := int(rec.get("engine_work", 0)) + men_for(repo, state, id, "engines")
	while work >= need:
		if not _pay_engine(repo, state, rec, label):
			work = need
			break
		built += 1
		work -= need
		history.append({"day": today, "kind": "engine_built", "engines": built,
			"reason": "siege engine %d built before %s" % [built, label]})
	var guns := 0
	for c: String in SiegeSystem.stationed(repo, state, id):
		guns += fit_guns(repo, state, c)
	@warning_ignore("integer_division")
	var crewed := mini(guns + built, men_for(repo, state, id, "bombard") / maxi(1, int(repo.bal("siege_engine_crew"))))
	@warning_ignore("integer_division")
	var repair := SiegeSystem.garrison_fit(repo, state, town) * int(repo.bal("siege_repair_per_100_men")) / 100
	var integrity := batter(int(rec["integrity"]), crewed, damage, repair)
	var wear := int(rec.get("engine_wear", 0))
	if crewed > guns and built > 0:
		wear += 1
		if wear >= maxi(1, int(repo.bal("siege_engine_wear_days"))):
			built -= 1
			wear = 0
			history.append({"day": today, "kind": "engine_worn", "engines": built,
				"reason": "a siege engine before %s worn out: %d left" % [label, built]})
	rec["engines_built"] = built
	rec["engine_work"] = work
	rec["engine_wear"] = wear
	rec["integrity"] = integrity
	if int(rec.get("breach", 0)) == 0 and integrity <= int(repo.bal("siege_breach_integrity")):
		rec["breach"] = 1
		history.append({"day": today, "kind": "breach", "integrity": integrity,
			"reason": "the walls of %s breached at %d/1000" % [label, integrity]})
	rec["history"] = history


## Pays one engine's siege_engine_gold for record `rec`: the crown's from its
## treasury (WorldLedger), an AI record's from its leading host's plunder.
## False, nothing paid, when the chest holds less.
static func _pay_engine(repo: DataRepository, state: GameState, rec: Dictionary, label: String) -> bool:
	var gold := int(repo.bal("siege_engine_gold"))
	if String(rec["attacker"]) == repo.resolve_realm("player_realm"):
		if float(WorldLedger.value_of(repo, state, "metrics.treasury")) < float(gold):
			return false
		return not WorldLedger.apply(repo, state, "metrics.treasury", -float(gold),
			"siege engine before " + label, "siege_engine").has("error")
	var mind: Dictionary = state.ai_hosts.get(SiegeSystem.lead_of(repo, state, String(rec["town"])), {})
	if int(mind.get("plunder", 0)) < gold:
		return false
	mind["plunder"] = int(mind["plunder"]) - gold
	return true


## The "siege works" figure for one arm (spec §4.4): the walls' bonus
## `defend` (army_town_defence.csv) scaled by `integrity`,
## 1000 + (defend − 1000) × integrity / 1000; for a unit that already `holds`
## the works (ArmySystem.works_of), that over the full figure, never above 1000.
static func works_permille(defend: int, integrity: int, holds: bool) -> int:
	@warning_ignore("integer_division")
	var scaled := 1000 + (defend - 1000) * clampi(integrity, 0, 1000) / 1000
	@warning_ignore("integer_division")
	return mini(1000, scaled * 1000 / defend) if holds and defend > 0 else scaled
