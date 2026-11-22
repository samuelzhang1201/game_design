class_name TownMilitia
extends RefCounted
## A besieged town's militia (player siege spec §5, step 4a). A town with no
## defenders when its siege opens raises ONE unit from its townsfolk:
##
##   men(arm) = min(population x men_permille / 1000, men_cap), whole crews
##
## for each row of data/battle/town_militia.csv of the town's best works
## (citadel over walls over none), the arms in file order each taking at most
## what is left of what the province can still mobilise (MilitaryPopulation.
## available, urban) and of army_living_cap_men. The men are enlisted through
## MilitaryRoster.mobilize (no population debit: only a death debits it) and
## released when the siege ends ("militia of <town> stood down"). The unit is
## an ordinary one on the town's seat — in `regiments` for a crown town, in
## `foes` (host "") for any other — marked `militia_town`, and never marches.

const FIELD := "urban_population"


## The town's best works: "citadel", "walls" or "town" (ArmySystem.works_of's
## test, read from the burg).
static func works_of_town(repo: DataRepository, town: String) -> String:
	var feats := String((repo.burgs.get(town, {}) as Dictionary).get("features", "")).split("|")
	if "citadel" in feats:
		return "citadel"
	if "walls" in feats:
		return "walls"
	return "town"


## The militia `town` would raise: arm -> men, in table order, arms with no men
## left out. `state` null reads the table alone (no province bound).
static func size(repo: DataRepository, state: GameState, town: String) -> Dictionary:
	var b: Dictionary = repo.burgs.get(town, {})
	if b.is_empty():
		return {}
	var people := int(float(b.get("population", 0)))
	var works := works_of_town(repo, town)
	var types := repo.world_table("military", "unit_types")
	var left := int(repo.bal("army_living_cap_men"))
	if state != null:
		left = mini(left, MilitaryPopulation.available(repo, state, String(b.get("province_code", "")), FIELD))
	var out: Dictionary = {}
	for row: Dictionary in repo.town_militia:
		if String(row["works"]) != works:
			continue
		var crew := maxi(1, int((types.get(String(row["arm"]), {}) as Dictionary).get("crew", 1)))
		@warning_ignore("integer_division")  # whole men, whole crews
		var men := mini(mini(people * int(row["men_permille"]) / 1000, int(row["men_cap"])), maxi(0, left)) / crew * crew
		if men > 0:
			out[String(row["arm"])] = int(out.get(String(row["arm"]), 0)) + men
			left -= men
	return out
