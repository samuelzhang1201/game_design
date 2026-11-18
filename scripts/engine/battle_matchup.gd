class_name BattleMatchup
extends RefCounted
## Matchups against the arms actually faced (spec 2026-11-18-axemen-arm-design, step 2).
##
## An arm's base power (ArmySystem._arm_base) is the mean of ALL its data/army/army_matchups.csv
## rows, whoever it fights. This factor puts the situation back: for each of a unit's arms, the
## people-weighted mean over the opposing units' arms of its row against that arm (the attack
## column when it attacks, defense when it defends; a pair with no row reads the arm's own mean),
## over that mean. The unit's factor is the people-weighted mean of its arms' ratios, so a uniform
## foe gives about 1000 and only the edge of the matchup is new. People = count x crew, in
## unit_types order.


## The factor row for `code` against `enemies` (unit codes), for a battle's factor list.
static func factor(repo: DataRepository, state: GameState, code: String, enemies: Array, attacking: bool) -> Dictionary:
	var foes: Array = []
	for enemy: Variant in enemies:
		foes.append(ArmySystem.regiment(repo, String(enemy), state))
	return {"source": "matchup:arms", "category": "formation_terrain",
		"permille": permille(repo, ArmySystem.regiment(repo, code, state), foes, attacking),
		"reason": "This unit's arms against the arms opposite (data/army/army_matchups.csv)"}


## `own` and each of `foes` are rows of arm -> count (a regiment row will do).
static func permille(repo: DataRepository, own: Dictionary, foes: Array, attacking: bool) -> int:
	var types := repo.world_table("military", "unit_types")
	var against: Dictionary = {}
	var foe_people := 0
	for arm: String in types:
		var people := 0
		for foe: Variant in foes:
			people += _people(types, foe as Dictionary, arm)
		if people > 0:
			against[arm] = people
			foe_people += people
	var own_people := 0
	var weighted := 0
	for arm: String in types:
		var people := _people(types, own, arm)
		if people <= 0 or foe_people <= 0:
			continue
		var mean := ArmySystem._arm_base(repo, "", arm, 0)
		var rows: Dictionary = {}
		for m: Dictionary in repo.army_matchups.get(arm, []):
			rows[String(m["vs"])] = int(m["attack" if attacking else "defense"])
		var sum := 0
		for foe_arm: String in against:
			sum += int(against[foe_arm]) * int(rows.get(foe_arm, mean))
		@warning_ignore("integer_division")  # whole per-mille: the foe-weighted value, then its ratio to the mean
		var ratio := sum / foe_people * 1000 / mean if mean > 0 else 1000
		weighted += people * ratio
		own_people += people
	@warning_ignore("integer_division")  # the unit's whole people-weighted mean
	return weighted / own_people if own_people > 0 else 1000


static func _people(types: Dictionary, row: Dictionary, arm: String) -> int:
	return maxi(0, int(float(row.get(arm, 0)))) * int(types[arm].get("crew", 0))
