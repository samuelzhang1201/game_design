extends RefCounted
## The suite's game data and campaigns, made once and handed out as copies.
##
## `DataRepository.load_all("res://data")` parses every table and the whole
## map pack (~200 ms) and `GameState.new_campaign` seeds the roster, the
## economy and the realm's wealth tiers (~200 ms); before 2026-10-02 most of
## ~1,000 tests paid both in before_each, about half the suite's time.
##
## `repo()` parses once per run and gives every caller its OWN deep copy
## (~13 ms), so a test may change any table it likes without reaching another
## test. `campaign(repo, seed)` keys a pristine campaign by the repository's
## CONTENT (one recursive hash, ~3 ms) and the seed, and hands out a copy made
## through the save format (~2 ms) — the same round trip the determinism
## tests hold bit-exact — so a test that tuned its repository first gets a
## campaign of that repository, never one of the pristine data.

static var _pristine: DataRepository
static var _campaigns := {}


## A deep copy of the game's data, parsed once per run.
static func repo() -> DataRepository:
	if _pristine == null:
		_pristine = DataRepository.load_all("res://data")
	return _copy(_pristine)


## A new campaign of `data` on `seed_value`, exactly as
## GameState.new_campaign(data, seed_value) would make it.
## Every ground at the base pace (data/army_ground_speed.csv all 1000), for
## a test of the march's own mechanics — readiness, weather, the even step —
## that must not depend on the road or the terrain the pack puts under it;
## the ground's pace has its own tests (test_army_towns.gd). Returns `data`.
static func flat_ground(data: DataRepository) -> DataRepository:
	for k: String in data.army_ground_speed:
		data.army_ground_speed[k] = 1000
	return data

static func campaign(data: DataRepository, seed_value: int) -> GameState:
	var key := "%d:%d" % [content_hash(data), seed_value]
	if not _campaigns.has(key):
		_campaigns[key] = GameState.new_campaign(data, seed_value).to_dict()
	return GameState.from_dict(_campaigns[key])


## One hash over every table the repository holds.
static func content_hash(data: DataRepository) -> int:
	var h := 0
	for p: Dictionary in data.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			h = hash([h, p["name"], data.get(p["name"])])
	return h


static func _copy(src: DataRepository) -> DataRepository:
	var out := DataRepository.new()
	var names: Array[String] = []
	for p: Dictionary in src.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(p["name"])
	for name in names:
		var v: Variant = src.get(name)
		if v is Dictionary or v is Array:
			out.set(name, v.duplicate(true))
		else:
			out.set(name, v)
	# The named tables (repo.burgs, repo.provinces, …) ARE world_tables' rows
	# in a loaded repository, one object under two names; copied one by one
	# they would come apart, and a test editing repo.burgs would not reach
	# world_table("political", "burgs") as it does in the game.
	for domain: String in src.world_tables:
		for area: String in src.world_tables[domain]:
			var table: Variant = src.world_tables[domain][area]
			for name in names:
				if name != "world_tables" and is_same(src.get(name), table):
					out.set(name, out.world_tables[domain][area])
	return out
