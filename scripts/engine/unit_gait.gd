class_name UnitGait extends RefCounted
## Walking and running in whole numbers (spec 2026-10-17-unit-behavior-and-
## battlefield-design §5): a running substep covers army_run_speed_permille of
## the walk and its runners eat army_run_supply_permille of their base for that
## time. Pure; the caller owns who runs and when (guide/battle_deployment.md).

## Metres a running substep covers where walking covers `walk_m`, after every
## existing walk modifier.
static func run_step_m(repo: DataRepository, walk_m: int) -> int:
	@warning_ignore("integer_division")  # whole metres
	return walk_m * int(repo.bal("army_run_speed_permille")) / 1000


## Pay one running substep's supply increment out of `entry.supplies`; false
## (nothing changed) means the substep walks. `base_bite` is today's whole base
## meal, still to be eaten at the day's end and reserved first; `run_bite` the
## part of it belonging to the personnel who run. The fraction below one supply
## is kept in `entry.run_supply_rem` (over 1000 × `substeps`), so short or small
## runs are paid in full later, never truncated away.
static func run_substep(repo: DataRepository, entry: Dictionary, base_bite: int, run_bite: int,
		substeps: int) -> bool:
	var supplies := int(entry.get("supplies", 0))
	if supplies < base_bite:
		return false
	var owed := int(entry.get("run_supply_rem", 0)) \
		+ run_bite * (int(repo.bal("army_run_supply_permille")) - 1000)
	var per_supply := 1000 * maxi(substeps, 1)
	@warning_ignore("integer_division")  # whole supplies, the rest carried
	var charge := owed / per_supply
	if supplies - charge < base_bite:
		return false
	entry["supplies"] = supplies - charge
	entry["run_supply_rem"] = owed % per_supply
	return true


## The commander's saved gait on `entry` (spec §5.1), kept per substep: a gait
## whose stop condition holds is dropped, then a run is recorded for a reason the
## engine can see — a withdrawal march, or a march to a battle its own side
## fights. No key means walk.
static func refresh(repo: DataRepository, state: GameState, code: String, entry: Dictionary) -> void:
	var gait: Dictionary = entry.get("gait", {})
	if not gait.is_empty() and not _holds(repo, state, code, entry, gait):
		entry.erase("gait")
		gait = {}
	if not gait.is_empty() or String(entry.get("order", "")) != ArmySystem.ORDER_MARCH \
			or ArmySystem.is_naval(repo, state, code):
		return
	if int(entry.get("disengaging", 0)) == 1:
		entry["gait"] = {"mode": "run", "reason": "withdrawal", "until": "march_end"}
		return
	for battle: Dictionary in state.battles:
		if _joins(repo, state, code, entry, battle):
			entry["gait"] = {"mode": "run", "reason": "join_battle", "until": "battle_over",
				"battle_id": int(battle["id"])}
			return


static func _holds(repo: DataRepository, state: GameState, code: String, entry: Dictionary,
		gait: Dictionary) -> bool:
	if String(entry.get("order", "")) != ArmySystem.ORDER_MARCH:
		return false
	if String(gait.get("until", "")) == "march_end":
		return int(entry.get("disengaging", 0)) == 1
	for battle: Dictionary in state.battles:
		if int(battle["id"]) == int(gait.get("battle_id", -1)):
			return _joins(repo, state, code, entry, battle)
	return false


## A battle the unit marches to join: it is in none, its destination is within
## battle_contact_km of the battle's place, and a unit of its own side (the
## crown's regiments, or the foes) fights there, so the side knows of it.
static func _joins(repo: DataRepository, state: GameState, code: String, entry: Dictionary,
		battle: Dictionary) -> bool:
	if not BattleSystem.battle_of(state, code).is_empty():
		return false
	var dx := int(entry.get("dest_x_m", 0)) - int(battle.get("place_x_m", 0))
	var dy := int(entry.get("dest_y_m", 0)) - int(battle.get("place_y_m", 0))
	var reach := int(repo.bal("battle_contact_km") * 1000)
	if dx * dx + dy * dy > reach * reach:
		return false
	var own: Dictionary = state.foes if state.foes.has(code) else state.regiments
	for member: String in (battle["att"] as Array) + (battle["def"] as Array):
		if own.has(member):
			return true
	return false


## The part of today's base meal `base_bite` its runners eat: the fit, never the
## wounded or the prisoners, who keep only their base (spec §5.2).
static func run_bite(repo: DataRepository, state: GameState, code: String, base_bite: int) -> int:
	var quality := MilitaryQuality.profile(repo, state, code)
	var fit: Dictionary = quality["fit_by_identity"]
	var runners := int(MilitaryQuality.from_counts(repo, int(fit["commoner"]), int(fit["noble"]))["supply_milli"])
	var all := int(quality["supply_milli"]) + PrisonerBurden.supply_milli(repo, state, code)
	@warning_ignore("integer_division")  # whole supplies; run_substep carries its own fraction
	return base_bite * runners / all if all > 0 else 0


## Whether this substep runs: a saved run gait the unit can afford, paid now out
## of `entry` (ArmySystem.march_day_saved scales the step by run_step_m).
static func pays_run(repo: DataRepository, state: GameState, code: String, entry: Dictionary,
		substeps: int) -> bool:
	if String(entry.get("gait", {}).get("mode", "")) != "run":
		return false
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty():
		return false
	var base := ArmySystem.day_bite(ArmySystem.supply_use(repo, reg, state), state.day)
	return run_substep(repo, entry, base, run_bite(repo, state, code, base), substeps)
