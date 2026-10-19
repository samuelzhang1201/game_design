extends GutTest
## P4.4c1: integer walk/run ground speed and the run supply increment
## (spec 2026-10-17-unit-behavior-and-battlefield-design §5, §14). Every
## expected value below is hand-computed from army_run_speed_permille = 1200,
## army_run_supply_permille = 1300 and battle_substeps = 10.
const SuiteData := preload("res://tests/suite_data.gd")

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()

func _substeps() -> int:
	return int(repo.bal("battle_substeps"))

## Run `count` substeps; the number of them actually run.
func _run(entry: Dictionary, base_bite: int, run_bite: int, count: int) -> int:
	var ran := 0
	for i in count:
		if UnitGait.run_substep(repo, entry, base_bite, run_bite, _substeps()):
			ran += 1
	return ran

func test_tuning_lives_in_csv() -> void:
	assert_eq(int(repo.bal("army_run_speed_permille")), 1200)
	assert_eq(int(repo.bal("army_run_supply_permille")), 1300)
	assert_eq(_substeps(), 10)

func test_run_ground_speed_is_120_percent_of_walk() -> void:
	assert_eq(UnitGait.run_step_m(repo, 100), 120)
	assert_eq(UnitGait.run_step_m(repo, 0), 0)
	# 600 m: six walking substeps at 100, five running at 120.
	assert_eq(ceili(600.0 / 100.0), 6)
	assert_eq(ceili(600.0 / float(UnitGait.run_step_m(repo, 100))), 5)

func test_full_day_run_costs_130_half_day_115() -> void:
	# Base 100 a day eaten at day end; the increment is paid per run substep.
	var full := {"supplies": 1000}
	assert_eq(_run(full, 100, 100, 10), 10)
	assert_eq(1000 - int(full.supplies) + 100, 130)
	var half := {"supplies": 1000}
	assert_eq(_run(half, 100, 100, 5), 5)
	assert_eq(1000 - int(half.supplies) + 100, 115)

func test_only_running_personnel_pay_the_increment() -> void:
	# 40 of the 100 base belong to people who run all day; the other 60 walk.
	var entry := {"supplies": 1000}
	assert_eq(_run(entry, 100, 40, 10), 10)
	assert_eq(1000 - int(entry.supplies) + 100, 112)
	assert_eq(int(entry.get("run_supply_rem", 0)), 0)

func test_same_distance_running_costs_108_permille_more_not_130() -> void:
	# 600 m: walking six substeps eats 6 × 10 base; running five eats 5 × 10
	# base plus the increment of five substeps (3 each).
	var entry := {"supplies": 1000}
	_run(entry, 100, 100, 5)
	var run_total := 5 * 10 + (1000 - int(entry.supplies))
	assert_eq(run_total, 65)
	assert_eq(run_total * 1000 / (6 * 10), 1083)

func test_remainder_is_saved_so_small_steps_are_never_free() -> void:
	# 3 × 300 = 900 per substep over 10 000: nothing until the 12th substep.
	var entry := {"supplies": 50}
	assert_eq(_run(entry, 3, 3, 11), 11)
	assert_eq(int(entry.supplies), 50)
	assert_eq(int(entry.run_supply_rem), 9900)
	assert_true(UnitGait.run_substep(repo, entry, 3, 3, _substeps()))
	assert_eq(int(entry.supplies), 49)
	assert_eq(int(entry.run_supply_rem), 800)

func test_remainder_survives_json() -> void:
	var straight := {"supplies": 1000}
	_run(straight, 100, 40, 7)
	var split := {"supplies": 1000}
	_run(split, 100, 40, 3)
	split = JSON.parse_string(JSON.stringify(split))
	_run(split, 100, 40, 4)
	assert_eq(int(split.supplies), int(straight.supplies))
	assert_eq(int(split.run_supply_rem), int(straight.run_supply_rem))

func test_base_ration_comes_first_and_stores_never_go_negative() -> void:
	# 103 in hand, 100 reserved for today's base: one run substep (3), then walk.
	var entry := {"supplies": 103}
	assert_eq(_run(entry, 100, 100, 10), 1)
	assert_eq(int(entry.supplies), 100)
	# A walking substep leaves the remainder untouched.
	var tight := {"supplies": 100, "run_supply_rem": 4000}
	assert_false(UnitGait.run_substep(repo, tight, 100, 100, _substeps()))
	assert_eq(int(tight.supplies), 100)
	assert_eq(int(tight.run_supply_rem), 4000)
	# The base itself short: walk, the hunger rules take it from there.
	var hungry := {"supplies": 99}
	assert_false(UnitGait.run_substep(repo, hungry, 100, 1, _substeps()))
	assert_eq(int(hungry.supplies), 99)
