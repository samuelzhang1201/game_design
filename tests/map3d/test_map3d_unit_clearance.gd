extends GutTest
## The clearance between land units (spec 2026-10-14-unit-clearance-and-
## scouting-design) is only honest if a piece, drawn at the opening zoom, is
## smaller than the room it is given: two full-strength formations side by side
## (2 x the largest half extent, in pack metres) fit inside army_clearance_m,
## which itself sits under army_slot_spacing_m. A failure reports the numbers;
## the balance is the owner's to rule on, not this test's to change.

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


func test_two_full_strength_formations_fit_inside_the_clearance() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var half := _half_extents(repo, state)
	assert_gt(half.size(), 0, "some arm has a piece")
	var largest := 0.0
	var report := []
	for arm: String in half:
		largest = maxf(largest, float(half[arm]))
		report.append("%s %.1f m" % [arm, half[arm]])
	var clearance := repo.bal("army_clearance_m")
	gut.p("half extents (pack metres): %s; 2 x largest %.1f, army_clearance_m %.0f, army_slot_spacing_m %.0f"
		% [", ".join(report), 2.0 * largest, clearance, repo.bal("army_slot_spacing_m")])
	assert_lte(2.0 * largest, clearance, "2 x the largest formation half extent (%.1f) fits army_clearance_m (%s)"
		% [largest, ", ".join(report)])
	assert_lt(clearance, repo.bal("army_slot_spacing_m"), "the clearance is under the camp lattice's pitch")
