class_name Forage
extends RefCounted
## Foraging (spec 2026-10-10-foraging-and-desertion §3.1): what the land under
## a column can feed it. A province's capacity is its FOOD production (the
## economy tables, goods tagged `food`) × forage_supply_per_food_unit × the
## season's per mille; the days of a month share it out, foragers strip it
## (GameState.forage_stripped, per mille), and the units on the ground split
## the day's yield by need. Integers only; every number a balance key.

const HOME := "home"
const ENEMY := "enemy"
const GREY := "grey"
const NONE := "none"
## The laws that thin a column's yield (balance forage_protect_cut_permille each).
const PROTECT_LAWS: Array[String] = ["protect_church", "protect_women"]

## repo instance id -> {province: food units}; tests build a repo per test.
static var _cache: Dictionary = {}


## Drop the cached food counts (a test that rewrites the production table).
static func forget() -> void:
	_cache.clear()


## Food units a province's burgs produce a month, whole.
static func food_units(repo: DataRepository, province: String) -> int:
	var key := repo.get_instance_id()
	if not _cache.has(key):
		if _cache.size() >= 4:
			_cache.erase(_cache.keys()[0])
		_cache[key] = _count(repo)
	return int((_cache[key] as Dictionary).get(province, 0))


static func _count(repo: DataRepository) -> Dictionary:
	var food: Dictionary = {}
	for g: Variant in repo.world_table("economy", "goods").values():
		var row: Dictionary = g
		if "food" in String(row.get("tags", "")).split("|", false):
			food[String(row["good_code"])] = true
	var out: Dictionary = {}
	for p: Variant in repo.world_table("economy", "production").values():
		var prow: Dictionary = p
		if not food.has(String(prow["good_code"])):
			continue
		var prov := String((repo.burgs.get(String(prow["burg_code"]), {}) as Dictionary).get("province_code", ""))
		if prov == "":
			continue
		out[prov] = int(out.get(prov, 0)) + int(float(prow.get("units", 0)))
	return out


static func season_permille(repo: DataRepository, state: GameState) -> int:
	return int(repo.bal("forage_%s_permille" % Calendar.season_of_day(state.absolute_day())))


## The month's yield in supply units, before any stripping.
static func monthly_capacity(repo: DataRepository, state: GameState, province: String) -> int:
	@warning_ignore("integer_division")  # whole supplies, one division
	return food_units(repo, province) * int(repo.bal("forage_supply_per_food_unit")) \
		* season_permille(repo, state) / 1000


## Day `day` (1..30) of the month's yield after the stripping so far: the
## month's thirtieths cut as running totals, so the days sum to the month.
static func day_capacity(repo: DataRepository, state: GameState, province: String, day: int) -> int:
	var d := clampi(day, 1, Calendar.DAYS_PER_TICK)
	var c := stripped_capacity(repo, state, province)
	@warning_ignore("integer_division")  # whole supplies
	return (c * d / Calendar.DAYS_PER_TICK - c * (d - 1) / Calendar.DAYS_PER_TICK) \
		* int(repo.bal("forage_share_permille")) / 1000


## The month's yield left once foragers have stripped the province.
static func stripped_capacity(repo: DataRepository, state: GameState, province: String) -> int:
	@warning_ignore("integer_division")  # whole supplies
	return monthly_capacity(repo, state, province) \
		* (1000 - clampi(int(state.forage_stripped.get(province, 0)), 0, 1000)) / 1000


## "home" (the crown's own), "enemy", "grey" (neutral, wary, unknown) or "none"
## (a friend's land, a province nobody holds, or no province at all).
static func land_kind(repo: DataRepository, state: GameState, province: String) -> String:
	if province == "":
		return NONE
	var holder := MapOwnership.owner_of(repo, state, province)
	if holder == "":
		return NONE
	if holder == repo.resolve_realm("player_realm"):
		return HOME
	match Intel.stance_of(repo, holder):
		"Enemy":
			return ENEMY
		"Neutral", "Suspicion", "Unknown":
			return GREY
	return NONE


## What is left of a unit's yield after the protection laws it keeps, per mille.
static func cut_permille(repo: DataRepository, state: GameState, code: String) -> int:
	var out := 1000
	for law: String in PROTECT_LAWS:
		if LawSystem.value(repo, state, law, code) == "on":
			out -= int(repo.bal("forage_protect_cut_permille"))
	return maxi(out, 0)


## What a unit could still take in: its carried-load order in days of use,
## bound by what it can carry, less its stores; never below 0.
static func need_of(repo: DataRepository, state: GameState, code: String) -> int:
	var entry: Dictionary = state.regiments.get(code, {})
	var reg := ArmySystem.regiment(repo, code, state)
	var use := ArmySystem.supply_use(repo, reg, state)
	@warning_ignore("integer_division")  # whole supplies
	var carried := ArmySystem.carry_of(repo, entry) * use / Calendar.DAYS_PER_TICK
	return maxi(0, mini(ArmySystem.max_units(repo, use), carried) - int(entry.get("supplies", 0)))


## {code: units}: the day's yield split by need among `codes`, each capped at
## its need and cut by its protection laws; what is left over goes to no one.
static func shares(repo: DataRepository, state: GameState, province: String, codes: Array,
		day: int) -> Dictionary:
	var sorted: Array = codes.duplicate()
	sorted.sort()
	var needs: Dictionary = {}
	var total := 0
	for c: String in sorted:
		needs[c] = need_of(repo, state, c)
		total += int(needs[c])
	var cap := day_capacity(repo, state, province, day)
	var out: Dictionary = {}
	for c: String in sorted:
		var n := int(needs[c])
		var got := 0
		if total > 0 and n > 0:
			@warning_ignore("integer_division")  # whole supplies
			got = mini(n, cap * n / total)
			@warning_ignore("integer_division")
			got = got * cut_permille(repo, state, c) / 1000
		out[c] = got
	return out


## The province loses `taken` units' worth of its forage: taken × forage_strip_k
## over the month's capacity, per mille, floored; none where there is no capacity.
static func strip(repo: DataRepository, state: GameState, province: String, taken: int) -> void:
	var cap := monthly_capacity(repo, state, province)
	if cap <= 0 or taken <= 0:
		return
	@warning_ignore("integer_division")  # whole per mille
	var add := taken * int(repo.bal("forage_strip_k")) / cap
	if add <= 0:
		return   # no 0 entry: only non-zero stripping is kept
	state.forage_stripped[province] = clampi(int(state.forage_stripped.get(province, 0)) + add, 0, 1000)


## A province's forage in a word, from today's yield against a full unstripped
## summer day: "rich" (forage_word_rich_permille and up), "fair"
## (forage_word_fair_permille), "thin" (any), "stripped" (none).
static func word_of(repo: DataRepository, state: GameState, province: String) -> String:
	var today := day_capacity(repo, state, province, state.day)
	var full := _full_day(repo, province, state.day)
	if today <= 0 or full <= 0:
		return "stripped"
	@warning_ignore("integer_division")  # whole per mille
	var share := today * 1000 / full
	if share >= int(repo.bal("forage_word_rich_permille")):
		return "rich"
	if share >= int(repo.bal("forage_word_fair_permille")):
		return "fair"
	return "thin"


## What day `day` yields in high summer with nothing stripped (day_capacity's
## own split of the month).
static func _full_day(repo: DataRepository, province: String, day: int) -> int:
	var d := clampi(day, 1, Calendar.DAYS_PER_TICK)
	@warning_ignore("integer_division")  # whole supplies
	var c := food_units(repo, province) * int(repo.bal("forage_supply_per_food_unit")) \
		* int(repo.bal("forage_summer_permille")) / 1000
	@warning_ignore("integer_division")  # whole supplies
	return (c * d / Calendar.DAYS_PER_TICK - c * (d - 1) / Calendar.DAYS_PER_TICK) \
		* int(repo.bal("forage_share_permille")) / 1000


## The provinces stripped past forage_bare_permille, sorted.
static func stripped_bare(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for p: String in state.forage_stripped:
		if int(state.forage_stripped[p]) > int(repo.bal("forage_bare_permille")):
			out.append(p)
	out.sort()
	return out
