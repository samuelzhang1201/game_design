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
static var _grids := {}   # water_open -> the pristine pack's MarchPath (null: none)


## A deep copy of the game's data, parsed once per run.
static func repo() -> DataRepository:
	if _pristine == null:
		_pristine = DataRepository.load_all("res://data")
	DataRepository.forget_derived()  # the last tests' copies' caches, else the run holds them all
	var out := _copy(_pristine)
	_install_grids(out)
	return out


## The pack's two march grids (land and water-open) are read and their A*
## built once per run, not once per test: forget_derived dropped them with the
## rest, and each test that asks a courier for a road would read the PNG and
## build the grid again (~200 ms). The grid is geometry only; the road graph
## on it (costs from road_speed, which a test may tune) is built per test.
static func _install_grids(data: DataRepository) -> void:
	for water_open in [false, true]:
		if not _grids.has(water_open):
			_grids[water_open] = MarchPath.load_pack(_pristine, water_open) \
				if int(_pristine.bal("army_march_grid_px")) > 0 else null
		if _grids[water_open] != null:
			MarchPath.use(data, _grids[water_open], water_open)


## A new campaign of `data` on `seed_value`, exactly as
## GameState.new_campaign(data, seed_value) would make it.
## Every ground at the base pace (data/army/army_ground_speed.csv all 1000), for
## a test of the march's own mechanics — readiness, weather, the even step —
## that must not depend on the road or the terrain the pack puts under it,
## nor bend round it (open_country); the ground's pace has its own tests
## (test_army_towns.gd). Returns `data`.
static func flat_ground(data: DataRepository) -> DataRepository:
	for k: String in data.army_ground_speed:
		data.army_ground_speed[k] = 1000
	return open_country(data)


## No ground a column must go round (army_march_grid_px 0: MarchPath has no
## grid, spec 2026-10-10-march-slope-detour): every march walks its straight
## line, for a test whose march must not bend round the pack's scarps and
## water (a short hop from the capital to a town across its bay). The detour
## has its own tests (test_march_path.gd). Returns `data`.
static func open_country(data: DataRepository) -> DataRepository:
	data.balance["army_march_grid_px"] = 0
	return data

## No clearance between units (army_clearance_on 0), for a test that stacks
## units on one point on purpose (a siege, a battle fixture) or walks a column
## through another's place. The clearance has its own tests
## (test_army_clearance.gd). Returns `data`.
static func no_clearance(data: DataRepository) -> DataRepository:
	data.balance["army_clearance_on"] = 0
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


## Historical test setup: configure casualties without charging today's population.
static func set_losses(state: GameState, code: String, wanted: Dictionary) -> void:
	assert(state.military_rosters.has(code), "Fixture unit needs initialized personnel")
	var totals: Dictionary = {}
	for field: String in ["wounded", "captured_current", "dead", "released"]:
		totals[field] = MilitaryRoster.count(state, code, field)
	for field: String in wanted:
		totals["released" if field == "deserted" else field] = int(wanted[field])
	var initial := MilitaryRoster.count(state, code, "initial")
	var lost := 0
	for field: String in totals:
		assert(int(totals[field]) >= 0, "Fixture casualties must be nonnegative")
		lost += int(totals[field])
	assert(lost <= initial, "Fixture casualties cannot exceed initial personnel")
	for id: String in state.military_rosters[code]["cohort_ids"]:
		var cohort: Dictionary = state.military_cohorts[id]
		for field: String in MilitaryRoster.STATES:
			cohort[field] = int(cohort.initial) if field == "fit" else 0
	for field: String in totals:
		for move: Dictionary in MilitaryRoster.plan_changes(state, code, "fit", field, int(totals[field])):
			var cohort: Dictionary = state.military_cohorts[move.cohort_id]
			cohort["fit"] -= int(move.count)
			cohort[field] += int(move.count)
	MilitaryRoster.sync_projections(state, code)


## Hand-sized test armies retain their named one-person cohorts.
static func set_headcount(state: GameState, code: String, total: int) -> void:
	if total == 0:
		set_losses(state, code, {"released": MilitaryRoster.count(state, code, "initial"), "wounded": 0, "dead": 0, "captured_current": 0})
		return
	var anonymous := ""
	var named := 0
	for id: String in state.military_rosters[code]["cohort_ids"]:
		var cohort: Dictionary = state.military_cohorts[id]
		var person := String(cohort.get("person_id", "")) != ""
		cohort["initial"] = 1 if person else 0
		named += 1 if person else 0
		if not person and anonymous == "":
			anonymous = id
	assert(total >= named and anonymous != "", "Fixture needs room for its named personnel")
	state.military_cohorts[anonymous]["initial"] = total - named
	set_losses(state, code, {"dead": 0, "wounded": 0, "released": 0, "captured_current": 0})
