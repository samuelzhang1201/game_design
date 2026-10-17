class_name PrisonerBurden
extends RefCounted

## Wounded captives are a subset of these identities, never another mouth.
static func supply_milli(repo: DataRepository, state: GameState, holder: String) -> int:
	if state == null:
		return 0
	var counts := PrisonerSystem.held_counts(state, holder)
	return int(counts["commoners"]) * int(repo.noble_quality["commoner"]["supply_permille"]) \
		+ int(counts["nobles"]) * int(repo.noble_quality["noble"]["supply_permille"])

## Guards stay fit in the personnel ledger but cannot contribute to combat.
static func guard_count(repo: DataRepository, state: GameState, holder: String) -> int:
	if state == null:
		return 0
	var held := int(PrisonerSystem.held_counts(state, holder)["total"])
	@warning_ignore("integer_division")
	return mini(ArmySystem.fit_count(repo, state, holder),
		(held * maxi(0, int(repo.bal("prisoner_guard_permille"))) + 999) / 1000)

## Captive load is relative to the holder's own living personnel.
static func pace_permille(repo: DataRepository, state: GameState, holder: String) -> int:
	if state == null:
		return 1000
	var held := int(PrisonerSystem.held_counts(state, holder)["total"])
	var living := ArmySystem.living_count(repo, state, holder)
	if living <= 0:
		return 0
	@warning_ignore("integer_division")
	return 1_000_000 * living / (1000 * living + held * maxi(0, int(repo.bal("prisoner_load_permille"))))
