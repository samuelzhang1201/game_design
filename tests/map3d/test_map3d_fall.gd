extends GutTest
## Which figure falls for a lost group (Map3DFall; spec 2026-11-16-infantry-duel-animation-design.md,
## owner: 前排倒，后排补位): a duelling front figure, one per removed group.


func test_one_fall_per_removal_from_the_duel() -> void:
	var plan := Map3DFall.plan("REG", [9], [1, 2, 3], [0, 1, 2, 3, 4], 0)
	assert_eq(plan.size(), 1)
	assert_eq(int(plan[0]["removed"]), 9)
	assert_true(int(plan[0]["faller"]) in [1, 2, 3], "a duellist falls")
	assert_eq(plan, Map3DFall.plan("REG", [9], [1, 2, 3], [0, 1, 2, 3, 4], 0), "the same loss, the same faller")


func test_more_removals_than_pairs() -> void:
	var plan := Map3DFall.plan("REG", [8, 9], [2], [0, 1, 2], 0)
	assert_eq(plan.size(), 2, "one fall per removed group")
	var fallers: Array = plan.map(func(p: Dictionary) -> int: return int(p["faller"]))
	assert_eq(fallers.count(2), 1, "the one duellist falls once")
	assert_ne(fallers[0], fallers[1], "never the same figure twice")
	for p: Dictionary in plan:
		if int(p["faller"]) != 2:
			assert_eq(int(p["faller"]), int(p["removed"]), "the other falls where it stands")


func test_no_pairs_falls_where_it_stands() -> void:
	assert_eq(Map3DFall.plan("REG", [7], [], [0, 1], 0), [{"removed": 7, "faller": 7}])


func test_a_duellist_no_longer_kept_does_not_fall_for_another() -> void:
	# slot 3 is paired but is itself removed: it falls as itself, not for slot 9.
	var plan := Map3DFall.plan("REG", [3, 9], [3, 5], [0, 5], 0)
	var by: Dictionary = {}
	for p: Dictionary in plan:
		by[int(p["removed"])] = int(p["faller"])
	assert_eq(by[9], 5)
	assert_eq(by[3], 3)


func test_alpha_holds_then_fades() -> void:
	assert_eq(Map3DFall.alpha(0.0, 2.0, 1.5), 1.0)
	assert_eq(Map3DFall.alpha(2.0, 2.0, 1.5), 1.0)
	assert_almost_eq(Map3DFall.alpha(2.75, 2.0, 1.5), 0.5, 0.0001)
	assert_eq(Map3DFall.alpha(3.5, 2.0, 1.5), 0.0)
	assert_eq(Map3DFall.alpha(9.0, 2.0, 0.0), 0.0, "no fade time: gone after the hold")
