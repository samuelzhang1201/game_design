extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Artisans raise buildings faster (spec 2026-09-30-ledger-industry-trade-design, M5).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
	var mw: Character = s.characters.get(String(s.council.get("master_of_works", "")))
	if mw != null:
		mw.skills["sk_steward"] = 16
		mw.opinion = 50

func test_the_speed_grows_with_the_townsfolk_and_is_capped() -> void:
	var home := MapManors.home_province(data, s)
	var urban := RealmEconomy._figure(data, s, "economy.provinces.%s.urban_population" % home)
	var bonus := mini(int(data.bal("artisan_speed_cap_permille")),
		urban / int(data.bal("artisan_per_step")) * int(data.bal("artisan_step_permille")))
	# The Master of Works seat is empty on a fresh campaign (controller
	# ruling 2026-09-30): Governance.factors reads that as any other vacant
	# flow, min_permille — the same floor a seated governor's efficiency
	# clamps to, so the expectation goes through the real formula rather
	# than assuming 1000 (full, unscaled).
	var eff := int(Governance.factors(data, s, "works")["efficiency"])
	assert_eq(MapManors.work_speed_permille(data, s, home), 1000 + bonus * eff / 1000)

## Controller ruling 2026-09-30: appointing a Master of Works, at any skill
## or opinion, must never make the artisans SLOWER than having no one govern
## the flow at all — Governance.factors clamps a seated governor's
## efficiency to the same min_permille floor a vacant flow reads, so this
## holds structurally, not by luck of the fixture.
func test_a_master_of_works_never_slows_the_artisans_below_the_empty_seat() -> void:
	var home := MapManors.home_province(data, s)
	var empty_speed := MapManors.work_speed_permille(data, s, home)
	var steward_id := String(s.council["steward"])
	s.governors["works"] = steward_id
	var mw: Character = s.characters[steward_id]
	for skill in [0, 4, 8, 16, 20]:
		mw.skills["sk_steward"] = skill
		for opinion in [-100, -50, 0, 50, 100]:
			mw.opinion = opinion
			assert_gte(MapManors.work_speed_permille(data, s, home), empty_speed,
				"skill %d, opinion %d must never be slower than a vacant seat" % [skill, opinion])

## Final fix wave, Minor2: the artisans are the LEDGER's own — a province
## the crown does not control has no master of works, so work_speed_permille
## gives it the plain 1000‰ regardless of its own urban population.
func test_an_uncontrolled_province_builds_at_the_plain_pace() -> void:
	var home := MapManors.home_province(data, s)
	var foreign := ""
	for p: String in data.provinces:
		if p != home and not MapManors.controlled_provinces(data, s).has(p):
			foreign = p
			break
	assert_ne(foreign, "", "the pack has an uncontrolled province")
	assert_eq(MapManors.work_speed_permille(data, s, foreign), 1000)

func test_a_work_finishes_sooner_with_artisans() -> void:
	var home := MapManors.home_province(data, s)
	var cell := int(MapManors.manors_of_province(data, home, s)[0])
	assert_true(MapManors.start_work(data, s, cell, "chapel", "a test chapel"))
	var days := int(data.manor_buildings["chapel"]["build_days"])
	var speed := MapManors.work_speed_permille(data, s, home)
	var need := int(ceil(float(days) * 1000.0 / float(speed)))
	for i in need - 1:
		s.day += 1
		MapManors.advance_works(data, s)
	assert_false("chapel" in MapManors.buildings_of(s, cell), "not yet")
	s.day += 1
	MapManors.advance_works(data, s)
	assert_true("chapel" in MapManors.buildings_of(s, cell), "done in %d days, not %d" % [need, days])

func test_an_old_work_keeps_its_days() -> void:
	var home := MapManors.home_province(data, s)
	var cell := int(MapManors.manors_of_province(data, home, s)[0])
	s.manor_works[str(cell)] = [{"building": "chapel", "start": s.absolute_day() - 10, "days": 40}]
	MapManors.advance_works(data, s)
	var w: Dictionary = s.manor_works[str(cell)][0]
	assert_gte(int(w["done"]), 10 * 1000, "the days already spent are counted")
