extends GutTest

func test_same_seed_same_sequence() -> void:
	var a := Rng.new(42)
	var b := Rng.new(42)
	for i in 20:
		assert_eq(a.randi_range(0, 1000), b.randi_range(0, 1000))

func test_round_trip_preserves_stream() -> void:
	var a := Rng.new(7)
	a.randf(); a.randf()
	var b := Rng.from_dict(a.to_dict())
	for i in 10:
		assert_eq(a.randi_range(0, 99), b.randi_range(0, 99))

func test_pick_weighted_is_deterministic_and_in_range() -> void:
	var a := Rng.new(3)
	var b := Rng.new(3)
	for i in 50:
		var ia: int = a.pick_weighted([1.0, 5.0, 2.0])
		assert_eq(ia, b.pick_weighted([1.0, 5.0, 2.0]))
		assert_between(ia, 0, 2)

## Final review M6: the seed survives a JSON round trip exactly, above 2^53
## too (Weather hashes it), and an old save's numeric seed still loads.
func test_a_seed_above_2_to_the_53_survives_the_save() -> void:
	var big := 9007199254740993  # 2^53 + 1: a double cannot hold it
	var a := Rng.new(big)
	var back: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	var b := Rng.from_dict(back)
	assert_eq(b.seed_value(), big)
	for i in 10:
		assert_eq(a.randi_range(0, 99), b.randi_range(0, 99))

func test_an_old_saves_numeric_seed_still_loads() -> void:
	var a := Rng.new(42)
	var old := {"seed": 42.0, "state": str(a.to_dict()["state"])}
	assert_eq(Rng.from_dict(old).seed_value(), 42)
