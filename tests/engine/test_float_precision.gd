extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

## Regression coverage for a verified Godot 4.7.1 engine bug:
## JSON.parse_string(JSON.stringify(x, "", true, true)) mis-decodes a
## meaningful fraction of float64 values by exactly 1 ULP. GameState.to_dict()
## must route every numeric value through a hex-encoded byte-exact round trip
## (GameState._float_to_hex / _hex_to_float) instead of relying on JSON's
## own float formatting/parsing.

const RunDir := preload("res://tests/run_dir.gd")


func test_hex_round_trip_is_bit_exact_for_10k_random_doubles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 10000:
		var v := (rng.randf() - 0.5) * pow(10.0, rng.randi_range(-3, 6))
		var back := GameState._hex_to_float(GameState._float_to_hex(v))
		assert_eq(var_to_bytes(back), var_to_bytes(v), "bit mismatch at %d: %.17f" % [i, v])

func test_save_load_bit_exact_for_adversarial_metric_values() -> void:
	var data := SuiteData.repo()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var s := SuiteData.campaign(data, 42)
	for i in 30:
		s.metrics["treasury"] = (rng.randf() - 0.5) * pow(10.0, rng.randi_range(-2, 5))
		s.metrics["unrest"] = rng.randf() * 100.0
		var path := RunDir.dir("float_precision").path_join("float_test.json")
		SaveLoad.save_game(s, path)
		var loaded := SaveLoad.load_game(path)
		assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(s), "hash diverged at %d" % i)
		assert_eq(var_to_bytes(loaded.metrics["treasury"]), var_to_bytes(s.metrics["treasury"]), "treasury bits at %d" % i)
