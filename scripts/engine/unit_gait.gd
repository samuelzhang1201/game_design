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
