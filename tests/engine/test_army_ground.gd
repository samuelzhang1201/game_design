extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The hex ground (spec 2026-10-07-army-split-and-ground §4.2).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_rings_have_six_k_slots_starting_east_counter_clockwise() -> void:
	assert_eq(ArmyGround.ring(0), [Vector2i.ZERO])
	assert_eq(ArmyGround.ring(1), [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)])
	for k in range(1, 6):
		assert_eq(ArmyGround.ring(k).size(), 6 * k)


func test_slot_metres_on_the_lattice() -> void:
	# pitch 400: east (400, 0); north-east (200, -346) — y grows down the map
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(1, 0), 400), Vector2i(1400, 1000))
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(1, -1), 400), Vector2i(1200, 654))
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(0, 1), 400), Vector2i(1200, 1346))


func test_start_rings_are_the_tables() -> void:
	for row: Dictionary in repo.army_split:
		assert_eq(ArmyGround.start_ring(repo, String(row["arm"])), int(row["start_ring"]))


## A land point well inside the player's capital province, in metres.
func _land_m() -> Vector2i:
	var cap: Dictionary = repo.burgs[String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])]
	return ArmySystem.pack_to_metres(repo, Vector2(float(cap["x"]), float(cap["y"])))


func test_a_taken_point_blocks_half_a_pitch_round_it() -> void:
	var taken := ArmyGround.new_taken(repo)
	var p := _land_m()
	assert_true(ArmyGround.is_free(repo, taken, p))
	ArmyGround.take(taken, p)
	var half := int(repo.bal("army_slot_spacing_m")) / 2
	assert_false(ArmyGround.is_free(repo, taken, p + Vector2i(half - 1, 0)))
	assert_true(ArmyGround.is_free(repo, taken, p + Vector2i(half, 0)) \
		or not ArmyGround.is_free(repo, ArmyGround.new_taken(repo), p + Vector2i(half, 0)),
		"free unless that ground is itself water or blocked")


func test_the_sea_is_never_free() -> void:
	assert_false(ArmyGround.is_free(repo, ArmyGround.new_taken(repo), Vector2i(-5000, -5000)))


func test_free_slot_starts_at_the_arms_ring() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for row: Dictionary in repo.army_split:
		var arm := String(row["arm"])
		var got := ArmyGround.free_slot(repo, c, arm, taken, true)
		assert_ne(got, ArmyGround.NONE)
		# its ring: the lattice distance from the centre, never inside start_ring
		var d := Vector2(got - c).length()
		assert_gte(d, float(spacing * int(row["start_ring"])) * 0.85, arm)


func test_the_field_centre_goes_to_the_first() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	assert_eq(ArmyGround.free_slot(repo, c, "cavalry", taken, false), c, "an empty field: the centre")
	ArmyGround.take(taken, c)
	assert_ne(ArmyGround.free_slot(repo, c, "cavalry", taken, false), c)


func test_a_town_centre_is_never_a_camp_slot() -> void:
	var c := _land_m()
	assert_ne(ArmyGround.free_slot(repo, c, "infantry", ArmyGround.new_taken(repo), true), c)


func test_no_free_slot_returns_none() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for k in range(0, int(repo.bal("army_slot_max_rings")) + 1):
		for ax: Vector2i in ArmyGround.ring(k):
			ArmyGround.take(taken, ArmyGround.slot_m(c, ax, spacing))
	assert_eq(ArmyGround.free_slot(repo, c, "infantry", taken, true), ArmyGround.NONE)


func test_two_slots_in_order_are_distinct() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var a := ArmyGround.free_slot(repo, c, "infantry", taken, true)
	ArmyGround.take(taken, a)
	var b := ArmyGround.free_slot(repo, c, "infantry", taken, true)
	assert_ne(a, b)
	assert_gte(Vector2(a - b).length(), float(int(repo.bal("army_slot_spacing_m")) / 2))
