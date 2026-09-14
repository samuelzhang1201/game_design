extends GutTest
## RealmEconomy (spec §4.4, §11.2): province sums from the columnar cache,
## the realm and the crown over the real pack, exact tie-out, and a cache
## that recomputes only what changed.

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_a_province_is_the_sum_of_its_manors_lines() -> void:
	var codes: Array = Array(MapOwnership.provinces_of(data, s, data.resolve_realm("player_realm")))
	codes.sort()
	for code: String in codes.slice(0, 3):
		var sum := {"tax": 0, "strategic": 0, "civil": 0}
		for cell: int in MapManors.manors_of_province(data, code):
			var line := ManorEconomy.line_of(data, s, cell, s.tick)
			sum["tax"] += int(line["tax"])
			sum["strategic"] += int(line["strategic"])
			sum["civil"] += int(line["civil"])
			var cached := RealmEconomy.line_of(data, s, cell)
			assert_eq(cached, {"tax": line["tax"], "strategic": line["strategic"], "civil": line["civil"]}, "the cache keeps the line of %d" % cell)
		assert_eq(RealmEconomy.province(data, s, code), sum, "province %s ties out" % code)

func test_the_realm_is_the_sum_of_its_provinces_and_the_crown_of_its_own() -> void:
	var e := RealmEconomy.realm(data, s)
	var realm := {"tax": 0, "strategic": 0, "civil": 0}
	var crown := {"tax": 0, "strategic": 0, "civil": 0}
	var mine := MapManors.controlled_provinces(data, s)
	assert_gt(mine.size(), 0, "the crown controls a province")
	for code: String in e["per_province"]:
		var p: Dictionary = e["per_province"][code]
		for k in ["tax", "strategic", "civil"]:
			realm[k] += int(p[k])
			if code in mine:
				crown[k] += int(p[k])
	assert_eq(e["realm"], realm)
	assert_eq(e["crown"], crown)
	assert_gt(int(realm["tax"]), int(crown["tax"]), "the realm is more than the crown's provinces")
	for k in ["tax", "strategic", "civil"]:
		assert_typeof(e["realm"][k], TYPE_INT, "%s is whole gold" % k)

func test_the_cache_recomputes_only_what_changed() -> void:
	RealmEconomy.realm(data, s)
	var n := RealmEconomy.compute_count
	var realm_size: int = Array(MapOwnership.provinces_of(data, s, data.resolve_realm("player_realm"))).size()
	assert_gt(n, 0, "every province of the realm was computed once")
	assert_eq(n, realm_size, "exactly the realm's provinces were computed")
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n, "a second read is a hit")
	s.day = 7
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n, "a day step is a hit")
	var cell: int = MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm"))[0]
	s.manor_buildings[str(cell)] = ["mill"]
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n + 1, "a building recomputes exactly its province")
	s.tick += 1
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n + 1 + realm_size, "a new month recomputes every province")

func test_the_day_buckets_spread_the_months_work() -> void:
	RealmEconomy.realm(data, s)
	s.tick += 1
	var total := 0
	for d in range(1, Calendar.DAYS_PER_TICK + 1):
		s.day = d
		total += RealmEconomy.step_day(data, s)
	assert_eq(total, RealmEconomy._codes.size(), "thirty buckets covered every province once")
	var n := RealmEconomy.compute_count
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n, "the month's end had nothing left to do")

func test_the_full_recompute_agrees_with_the_cache() -> void:
	RealmEconomy.realm(data, s)
	var cell: int = MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm"))[0]
	s.manor_buildings[str(cell)] = ["mill", "market"]
	WorldLedger.apply(data, s, "economy.provinces.%s.rural_population" % MapManors.province_of(data, cell), 500, "test", "test")
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.check_full(data, s), [], "no province differs")
