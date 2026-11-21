extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The impact's pure curves (Map3DImpact; spec 2026-11-21-infantry-melee-scrum-design.md):
## the hit-stop window and the knock-back's out-and-back, hand-computed.


func test_held_is_the_hitstop_window() -> void:
	assert_false(Map3DImpact.held(-0.01, 0.08), "not before contact")
	assert_true(Map3DImpact.held(0.0, 0.08), "from the contact instant")
	assert_true(Map3DImpact.held(0.079, 0.08))
	assert_false(Map3DImpact.held(0.08, 0.08), "over once the hold has passed")


func test_knock_goes_out_and_back() -> void:
	assert_eq(Map3DImpact.knock(-0.1, 0.12, 0.35), 0.0, "nothing before contact")
	assert_almost_eq(Map3DImpact.knock(0.0, 0.12, 0.35), 0.0, 0.0001, "starts from the stand")
	# halfway out: ease-out 1 - (1 - 0.5)^2 = 0.75
	assert_almost_eq(Map3DImpact.knock(0.06, 0.12, 0.35), 0.75, 0.0001)
	assert_almost_eq(Map3DImpact.knock(0.12, 0.12, 0.35), 1.0, 0.0001, "full out at out_s")
	# halfway back: 1 - smoothstep(0.5) = 1 - (3 x 0.25 - 2 x 0.125) = 0.5
	assert_almost_eq(Map3DImpact.knock(0.295, 0.12, 0.35), 0.5, 0.0001)
	assert_almost_eq(Map3DImpact.knock(0.47, 0.12, 0.35), 0.0, 0.0001, "back on its stand")
	assert_eq(Map3DImpact.knock(1.0, 0.12, 0.35), 0.0)


func test_tune_reads_the_keys() -> void:
	var repo := SuiteData.repo()
	repo.balance["map3d_melee_hitstop_s"] = 0.1
	repo.balance["map3d_melee_block_knock"] = 0.5
	var tune := Map3DImpact.tune_of(repo)
	assert_eq(float(tune["hitstop"]), 0.1)
	assert_eq(float(tune["block_knock"]), 0.5)
	for key: String in ["knock_h", "knock_out", "knock_back"]:
		assert_true(tune.has(key), key)
