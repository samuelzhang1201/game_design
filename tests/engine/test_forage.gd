extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const H := preload("res://tests/engine/conduct_helpers.gd")
## Forage (spec 2026-10-10-foraging-and-desertion §3.1): capacity, the day's
## share, land kind, the protection cut and the stripping, hand-computed.

var repo: DataRepository
var state: GameState
var prov: String


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 11)
	Forage.forget()
	repo.balance["forage_supply_per_food_unit"] = 30.0
	repo.balance["forage_summer_permille"] = 1000.0
	repo.balance["forage_share_permille"] = 1000.0
	repo.balance["forage_strip_k"] = 500.0
	repo.balance["army_supply_max_days"] = 600.0  # room to need 60 units
	prov = H.home_province(repo, state)
	H.set_food(repo, prov, 9)
	state.forage_stripped.clear()
	state.day = 1
	# the fifth month of the year is in summer
	state.tick = 5
	assert_eq(Calendar.season_of_day(state.absolute_day()), "summer")


func after_each() -> void:
	Forage.forget()


func test_food_units_counts_only_food_tagged() -> void:
	var table: Dictionary = repo.world_table("economy", "production")
	var burg := H.burg_of(repo, prov)
	var other_food := ""
	var codes: Array = repo.world_table("economy", "goods").keys()
	codes.sort()
	for c: String in codes:
		var tags: PackedStringArray = String(repo.world_row("economy", "goods", c).get("tags", "")).split("|", false)
		if "food" in tags and c != H.food_good(repo):
			other_food = c
			break
	assert_ne(other_food, "")
	var before := Forage.food_units(repo, prov)
	table["%s:%s" % [burg, other_food]] = {"burg_code": burg, "good_code": other_food, "units": 7}
	Forage.forget()
	assert_eq(Forage.food_units(repo, prov), before + 7)
	var other := H.other_good(repo)
	table["%s:%s" % [burg, other]] = {"burg_code": burg, "good_code": other, "units": 5}
	Forage.forget()
	assert_eq(Forage.food_units(repo, prov), before + 7)


func test_monthly_capacity_by_season() -> void:
	assert_eq(Forage.monthly_capacity(repo, state, prov), 270)
	repo.balance["forage_spring_permille"] = 600.0
	repo.balance["forage_winter_permille"] = 300.0
	state.tick = 2  # spring
	assert_eq(Calendar.season_of_day(state.absolute_day()), "spring")
	assert_eq(Forage.monthly_capacity(repo, state, prov), 162)
	state.tick = 11  # winter
	assert_eq(Calendar.season_of_day(state.absolute_day()), "winter")
	assert_eq(Forage.monthly_capacity(repo, state, prov), 81)


func test_daily_capacities_sum_to_the_month() -> void:
	var sum := 0
	for d in range(1, 31):
		assert_eq(Forage.day_capacity(repo, state, prov, d), 9)
		sum += Forage.day_capacity(repo, state, prov, d)
	assert_eq(sum, 270)
	state.forage_stripped[prov] = 500
	sum = 0
	for d in range(1, 31):
		sum += Forage.day_capacity(repo, state, prov, d)
	assert_eq(sum, 135)
	assert_eq(Forage.day_capacity(repo, state, prov, 1), 4)
	assert_eq(Forage.day_capacity(repo, state, prov, 2), 5)


func test_land_kind() -> void:
	assert_eq(Forage.land_kind(repo, state, prov), "home")
	assert_eq(Forage.land_kind(repo, state, ""), "none")
	var foreign := H.foreign_province(repo, state)
	assert_ne(foreign, "")
	var holder := MapOwnership.owner_of(repo, state, foreign)
	var cases := {"Enemy": "enemy", "Neutral": "grey", "Suspicion": "grey",
		"Unknown": "grey", "Suzerain": "none", "Vassal": "none"}
	for stance: String in cases:
		H.set_stance(repo, holder, stance)
		assert_eq(Forage.land_kind(repo, state, foreign), cases[stance], stance)


## Set a unit's need to exactly `want`.
func _need(code: String, want: int) -> void:
	state.regiments[code]["carry_days"] = 999
	state.regiments[code]["supplies"] = 0
	var base := Forage.need_of(repo, state, code)
	assert_true(base >= want, "%s can take %d in (%d)" % [code, want, base])
	state.regiments[code]["supplies"] = base - want
	assert_eq(Forage.need_of(repo, state, code), want)


func test_shares_proportional_to_need() -> void:
	var units := H.land_units(repo, state)
	assert_true(units.size() >= 2)
	var a: String = units[0]
	var b: String = units[1]
	_need(a, 60)
	_need(b, 30)
	var got := Forage.shares(repo, state, prov, [b, a], 1)
	assert_eq(got[a], 6)
	assert_eq(got[b], 3)
	_need(b, 2)
	got = Forage.shares(repo, state, prov, [a, b], 1)
	assert_eq(got[a], 8)
	assert_eq(got[b], 0)
	_need(a, 4)
	got = Forage.shares(repo, state, prov, [a], 1)
	assert_eq(got[a], 4)
	# a later change to one unit's stores never reaches a result already given
	_need(a, 60)
	_need(b, 30)
	got = Forage.shares(repo, state, prov, [a, b], 1)
	var second: int = got[b]
	state.regiments[a]["supplies"] = 0
	assert_eq(got[b], second)


func test_protect_laws_cut_the_yield() -> void:
	var a := H.land_unit(repo, state)
	_need(a, 60)
	assert_eq(Forage.shares(repo, state, prov, [a], 1)[a], 9)
	repo.balance["forage_protect_cut_permille"] = 100.0
	for law: String in ["protect_church", "protect_women"]:
		LawSystem.impose(repo, state, law, "on")
	assert_eq(Forage.cut_permille(repo, state, a), 800)
	assert_eq(Forage.shares(repo, state, prov, [a], 1)[a], 7)


func test_strip_arithmetic() -> void:
	Forage.strip(repo, state, prov, 9)
	assert_eq(int(state.forage_stripped[prov]), 16)
	Forage.strip(repo, state, prov, 100000)
	assert_eq(int(state.forage_stripped[prov]), 1000)
	H.set_food(repo, prov, 0)
	state.forage_stripped.clear()
	Forage.strip(repo, state, prov, 50)
	assert_false(state.forage_stripped.has(prov))
