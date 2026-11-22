extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Town militia (player siege spec §5, step 4a): a besieged town with no
## defenders raises a militia from its population (town_militia.csv by works,
## capped, bounded by what its province can still mobilise), enlisted and
## released through the personnel model, so the people are conserved over
## raise -> dead -> stand down; militia never march.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

func _urban(s: GameState, prov: String) -> int:
	return int(WorldLedger.value_of(repo, s, MilitaryPopulation.path(prov, "urban_population")))


func _set_urban(s: GameState, prov: String, people: int) -> void:
	WorldLedger.apply(repo, s, MilitaryPopulation.path(prov, "urban_population"), people - _urban(s, prov),
		"test: the province's townsfolk", "test")


func _prov(town: String) -> String:
	return String(repo.burgs[town]["province_code"])


## A town held by `realm`, not the capital, with no unit on its seat and no
## unit of the realm's standing at it.
func _empty_town(s: GameState, realm: String) -> String:
	var towns: Array = repo.burgs.keys()
	towns.sort()
	for t: String in towns:
		if SiegeSystem.holder_of(repo, s, t) != realm or ArmyGround.seat_of(repo, s, t) != "" \
				or String(repo.burgs[t].get("is_capital", "0")) == "1":
			continue
		if SiegeSystem.defenders_of(repo, s, t).is_empty():
			return t
	return ""


## --- the size ---------------------------------------------------------------

func test_size_by_works_and_population() -> void:
	var town := String(repo.burgs.keys()[0])
	var b: Dictionary = repo.burgs[town]
	b["population"] = "12551"
	b["features"] = "walls"
	assert_eq(TownMilitia.size(repo, null, town), {"infantry": 251, "archers": 125},
		"walls: 12551 x 20/1000, x 10/1000")
	b["features"] = "walls|citadel"
	assert_eq(TownMilitia.size(repo, null, town), {"infantry": 376, "archers": 188},
		"a citadel: x 30/1000, x 15/1000")
	b["features"] = "temple"
	assert_eq(TownMilitia.size(repo, null, town), {"infantry": 125, "archers": 62},
		"an open town: x 10/1000, x 5/1000")
	b["features"] = "walls"
	b["population"] = "40000"
	assert_eq(TownMilitia.size(repo, null, town), {"infantry": 400, "archers": 200}, "the caps")


func test_size_bounded_by_what_the_province_can_mobilise() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := _empty_town(s, repo.resolve_realm("raider_realm"))
	assert_ne(town, "", "an empty raider town")
	var prov := _prov(town)
	repo.burgs[town]["population"] = "40000"
	repo.burgs[town]["features"] = "walls"
	var held := MilitaryPopulation.occupied(s, prov, "urban_population") \
		+ MilitaryPopulation.restricted(s, prov, "urban_population")
	# available = people x 250/1000 - held = 100
	_set_urban(s, prov, (100 + held) * 4)
	assert_eq(MilitaryPopulation.available(repo, s, prov, "urban_population"), 100)
	assert_eq(TownMilitia.size(repo, s, town), {"infantry": 100}, "infantry first takes what is left")
