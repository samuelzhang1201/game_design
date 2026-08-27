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
