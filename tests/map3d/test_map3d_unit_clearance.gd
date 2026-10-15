extends GutTest
## The clearance between land units (spec 2026-10-14-unit-clearance-and-
## scouting-design, owner ruling R-A 2026-10-15) is only honest if a piece, drawn
## at the opening zoom, fits the room its arm is given: each arm's clearance
## radius (data/army/army_clearance.csv) is at least the arm's full-strength
## formation half extent in pack metres, so two units' pieces never overlap on
## screen when their centres are a radius sum apart; and the camp lattice's pitch
## holds two of the widest. A failure reports the numbers; the balance is the
## owner's to rule on, not this test's to change.

const SuiteData := preload("res://tests/suite_data.gd")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


## Each arm's full-strength half extent (the larger axis) at the opening
## reference scale, in pack metres: {arm: metres}.
func _half_extents(repo: DataRepository, state: GameState) -> Dictionary:
	var out: Dictionary = {}
	var view_h := 1080.0
	var ref_m := Map3DGeometry.distance_for_bar(repo, WORLD, repo.bal("map3d_zoom_start_scale"), view_h)
	var full := Map3DFormation.tier_of(repo, 1000)
	var to_pack_m := float(ArmySystem.metres_per_pack_px(repo)) / float(WORLD["m_per_px"])
	var realm := repo.resolve_realm("player_realm")
	for reg: Dictionary in MapObjects.regiments_of(repo, realm, state):
		var arm := MapObjects.regiment_arm(repo, reg)
		if out.has(arm):
			continue
		var built := Map3DFormation.of_regiment(repo, reg, full, 1.6)
		if built.is_empty():
			continue
		var k := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), view_h, ref_m,
			float(built["height_m"]), built["size"])
		var ext: Vector2 = built["extent"]
		out[arm] = maxf(ext.x, ext.y) * k * to_pack_m
		(built["node"] as Node).free()
	return out


func test_each_arms_radius_covers_its_formation_and_the_pitch_holds_two() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var half := _half_extents(repo, state)
	assert_gt(half.size(), 0, "some arm has a piece")
	var report := []
	for arm: String in half:
		report.append("%s %.1f m (radius %d)" % [arm, half[arm], ArmyGround.arm_radius(repo, arm)])
		assert_gte(float(ArmyGround.arm_radius(repo, arm)), float(half[arm]),
			"%s: the clearance radius covers the formation's half extent" % arm)
	gut.p("half extents (pack metres): %s; army_slot_spacing_m %.0f" % [", ".join(report), repo.bal("army_slot_spacing_m")])
	var largest := 0
	for arm: String in repo.army_clearance:
		largest = maxi(largest, ArmyGround.arm_radius(repo, arm))
	assert_gte(int(repo.bal("army_slot_spacing_m")), 2 * largest,
		"the camp lattice's pitch holds two of the widest units (%s)" % ", ".join(report))
