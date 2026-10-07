extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The Missive log (spec 2026-09-28-missive-board-and-spies §1).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _m(column: String, day: int) -> Dictionary:
	return MissiveLog.make("spy", column, day, MissiveLog.subject("point", "", -1, Vector2(10.4, 20.6)),
		"A letter", [MissiveLog.exact("people", "People", 3000)])


func test_add_gives_ids_and_starts_unread() -> void:
	var s := SuiteData.campaign(repo, 7)
	assert_eq(MissiveLog.add(repo, s, _m("credible", 3)), 1)
	assert_eq(MissiveLog.add(repo, s, _m("rumour", 4)), 2)
	assert_eq(MissiveLog.unread(s), 2)
	var one := MissiveLog.find(s, 1)
	assert_eq(String(one["column"]), "credible")
	assert_eq(int(one["subject"]["x"]), 10, "pack px are whole")
	assert_eq(int(one["subject"]["y"]), 21)
	MissiveLog.mark_read(s, 1)
	assert_eq(MissiveLog.unread(s), 1)


func test_a_column_lists_newest_first() -> void:
	var s := SuiteData.campaign(repo, 7)
	for d in [1, 2, 3]:
		MissiveLog.add(repo, s, _m("credible", d))
	MissiveLog.add(repo, s, _m("truth", 9))
	var ids: Array = MissiveLog.column(s, "credible").map(func(m: Dictionary) -> int: return int(m["id"]))
	assert_eq(ids, [3, 2, 1])


func test_each_column_is_capped_on_its_own() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo.balance["missive_keep_per_column"] = 2.0
	MissiveLog.add(repo, s, _m("truth", 1))
	for d in [1, 2, 3]:
		MissiveLog.add(repo, s, _m("credible", d))
	assert_eq(MissiveLog.column(s, "credible").size(), 2)
	assert_eq(MissiveLog.find(s, 2), {}, "the oldest credible letter left")
	assert_eq(MissiveLog.column(s, "truth").size(), 1, "another column is untouched")


func _supply(day: int) -> Dictionary:
	return MissiveLog.make("supply", "credible", day, MissiveLog.subject("regiment", "r", -1, Vector2.ZERO),
		"Supply dispatch", [MissiveLog.words("supply_0", "Low", "x")])


## Spec 2026-10-07-army-supply-lines §5.5: the marshal's letters have a cap of
## their own and never push another kind off the column.
func test_supply_letters_never_evict_a_spy_report() -> void:
	var s := SuiteData.campaign(repo, 7)
	var spy := MissiveLog.add(repo, s, _m("credible", 1))
	for d in 45:
		MissiveLog.add(repo, s, _supply(d))
	assert_ne(MissiveLog.find(s, spy), {}, "the spy's report stays")
	var supply: Array = MissiveLog.column(s, "credible").filter(
		func(m: Dictionary) -> bool: return String(m["kind"]) == "supply")
	assert_eq(supply.size(), int(repo.bal("missive_keep_supply")))
	assert_eq(int(supply[0]["day"]), 44, "the newest stay")


func test_other_letters_are_capped_without_counting_supply() -> void:
	var s := SuiteData.campaign(repo, 7)
	for d in 5:
		MissiveLog.add(repo, s, _supply(d))
	for d in 41:
		MissiveLog.add(repo, s, _m("credible", d))
	var spy: Array = MissiveLog.column(s, "credible").filter(
		func(m: Dictionary) -> bool: return String(m["kind"]) == "spy")
	assert_eq(spy.size(), int(repo.bal("missive_keep_per_column")))
	var supply: Array = MissiveLog.column(s, "credible").filter(
		func(m: Dictionary) -> bool: return String(m["kind"]) == "supply")
	assert_eq(supply.size(), 5, "the supply letters are untouched")


func test_the_log_survives_a_save() -> void:
	var s := SuiteData.campaign(repo, 7)
	MissiveLog.add(repo, s, _m("rumour", 5))
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(copy.next_missive_id, 1)
	assert_eq(JSON.stringify(copy.missives), JSON.stringify(s.missives))


func test_an_old_save_has_an_empty_board() -> void:
	var s := SuiteData.campaign(repo, 7)
	var d: Dictionary = s.to_dict()
	d.erase("missives")
	d.erase("next_missive_id")
	var old := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(old.missives, [])
	assert_eq(MissiveLog.unread(old), 0)


func test_the_tables() -> void:
	for key in ["people", "tax", "output", "wealth", "troops_own", "troops_foreign", "holder", "stance"]:
		assert_true(repo.intel_facts.has(key), key)
	assert_eq(Array(repo.intel_facts["wealth"]["tiers"]).size(), 3, "one word per tercile")
	assert_lt(int(repo.spy_difficulty["foreign"]), 0, "abroad is harder to read")
	assert_gt(int(repo.courier_kinds["spy"]["speed_permille"]), 0, "a spy rides")
	assert_true(repo.courier_art.has("spy"))
	for c: String in MissiveLog.COLUMNS:
		assert_true(repo.palette.has("intel_" + c), c)
