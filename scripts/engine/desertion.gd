class_name Desertion
extends RefCounted
## Desertion (spec 2026-10-10-foraging-and-desertion §3.2): a land unit that is
## broken, untrained or unfed loses men each day. Whole men, integers only: the
## rate is per 100000 of the fit men and the fraction carries in `desert_rem`.

const SCALE := 100000


static func _is_fleet(repo: DataRepository, state: GameState, code: String) -> bool:
	return String(ArmySystem.regiment(repo, code, state).get("is_naval", "0")) == "1"


## How many of the three lines hold: morale and training under their marks, the
## days in hand at or under the supply mark. 0 for a unit that eats nothing.
static func conditions(repo: DataRepository, state: GameState, code: String) -> int:
	var entry: Dictionary = state.regiments.get(code, {})
	var reg := ArmySystem.regiment(repo, code, state)
	if entry.is_empty() or reg.is_empty():
		return 0
	var use := ArmySystem.supply_use(repo, reg, state)
	if use <= 0:
		return 0
	var n := 0
	if int(entry.get("morale", 0)) < int(repo.bal("desert_morale")):
		n += 1
	if int(entry.get("training", 0)) < int(repo.bal("desert_training")):
		n += 1
	if ArmySystem.days_in_hand(int(entry.get("supplies", 0)), use) <= int(repo.bal("desert_supply_days")):
		n += 1
	return n


## The law's multiplier, per mille: `desert_mult_<fine|lenient|hanging>`.
static func multiplier_permille(repo: DataRepository, state: GameState, code: String) -> int:
	return int(repo.bal("desert_mult_" + LawSystem.value(repo, state, "desertion_penalty", code)))


## The men the unit loses today; moves `desert_rem` and `deserted`.
static func daily_loss(repo: DataRepository, state: GameState, code: String) -> int:
	if _is_fleet(repo, state, code):
		return 0
	var n := conditions(repo, state, code)
	var entry: Dictionary = state.regiments.get(code, {})
	if n == 0 or entry.is_empty():
		return 0
	var reg := ArmySystem.regiment(repo, code, state)
	var fit := ArmySystem.fit_heads(ArmySystem.headcount(repo, reg), entry)
	if fit <= 0:
		return 0
	@warning_ignore("integer_division")  # whole men, the rest carried
	var rate := int(repo.bal("desert_permille_per_day")) * 100 * n * multiplier_permille(repo, state, code) / 1000
	var units := fit * rate + int(entry.get("desert_rem", 0))
	@warning_ignore("integer_division")
	var lost := mini(units / SCALE, fit)
	entry["desert_rem"] = 0 if lost >= fit else units % SCALE   # nobody left to carry a fraction of
	entry["deserted"] = int(entry.get("deserted", 0)) + lost
	return lost
