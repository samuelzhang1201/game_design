extends GutTest
## Graphics tiers for ordinary machines (spec 2026-09-20 §4):
## data/graphics_quality.csv read by Map3DQuality — pure: the row, the GPU
## detection, the saved setting.

const CFG := "user://test_quality_settings.cfg"


func before_all() -> void:
	Game.start_campaign(42)


func after_each() -> void:
	if FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func test_every_tier_has_a_row() -> void:
	for tier: String in Map3DQuality.TIERS:
		assert_true(Game.data.graphics_quality.has(tier), tier)
	assert_eq(Map3DQuality.row(Game.data, "nonsense"), Map3DQuality.row(Game.data, "high"))


func test_high_is_todays_look() -> void:
	var r := Map3DQuality.row(Game.data, "high")
	assert_eq(Map3DQuality.num(r, "render_scale"), 1.0)
	assert_eq(Map3DQuality.num(r, "line_step_mul"), 1.0)
	assert_eq(Map3DQuality.num(r, "road_step_mul"), 1.0)
	assert_eq(Map3DQuality.num(r, "river_step_mul"), 1.0)
	assert_eq(Map3DQuality.num(r, "clouds"), Game.data.bal("map3d_cloud_max"))
	assert_eq(Map3DQuality.num(r, "shadow_max_m"), Game.data.bal("map3d_sun_shadow_max_m"))
	assert_eq(Map3DQuality.num(r, "hud_hz"), 0.0)


func test_the_spec_steps_come_out_in_metres() -> void:
	var low := Map3DQuality.row(Game.data, "low")
	assert_almost_eq(Game.data.bal("map3d_line_step_m") * Map3DQuality.num(low, "line_step_mul"), 300.0, 0.01)
	assert_almost_eq(Game.data.bal("map3d_road_step_m") * Map3DQuality.num(low, "road_step_mul"), 50.0, 0.01)
	assert_almost_eq(Game.data.bal("map3d_river_mesh_step_m") * Map3DQuality.num(low, "river_step_mul"), 30.0, 0.01)
	var med := Map3DQuality.row(Game.data, "medium")
	assert_almost_eq(Game.data.bal("map3d_line_step_m") * Map3DQuality.num(med, "line_step_mul"), 200.0, 0.01)
	assert_almost_eq(Game.data.bal("map3d_road_step_m") * Map3DQuality.num(med, "road_step_mul"), 35.0, 0.01)
	assert_almost_eq(Game.data.bal("map3d_river_mesh_step_m") * Map3DQuality.num(med, "river_step_mul"), 18.0, 0.01)


func test_detection_by_adapter_name() -> void:
	var cases := {
		["Intel(R) Iris(R) Xe Graphics", "Intel"]: "low",
		["Intel(R) UHD Graphics 620", "Intel"]: "low",
		["Intel(R) HD Graphics 520", "Intel"]: "low",
		["AMD Radeon(TM) Graphics", "AMD"]: "low",
		["AMD Radeon Vega 8 Graphics", "AMD"]: "low",
		["llvmpipe (LLVM 15.0.7, 256 bits)", "Mesa"]: "low",
		["Apple M1", "Apple"]: "medium",
		["Apple M3", "Apple"]: "medium",
		["NVIDIA GeForce GTX 1060 6GB", "NVIDIA"]: "medium",
		["NVIDIA GeForce MX450", "NVIDIA"]: "medium",
		["Apple M2 Pro", "Apple"]: "high",
		["Apple M5 Pro", "Apple"]: "high",
		["NVIDIA GeForce RTX 3060", "NVIDIA"]: "high",
		["NVIDIA GeForce GTX 1660 SUPER", "NVIDIA"]: "high",
		["AMD Radeon RX 6600", "AMD"]: "high",
		["AMD Radeon Pro 5500M", "AMD"]: "high",
		["Intel(R) Arc(TM) A770 Graphics", "Intel"]: "high",
		["", ""]: "high",
	}
	for k: Array in cases:
		assert_eq(Map3DQuality.detect(k[0], k[1]), cases[k], "%s" % k)


func test_the_setting_overrides_the_detection() -> void:
	assert_eq(Map3DQuality.setting(CFG), Map3DQuality.AUTO, "no file: auto")
	Map3DQuality.save_setting(CFG, "low")
	assert_eq(Map3DQuality.setting(CFG), "low")
	var was := Map3DQuality.forced
	Map3DQuality.forced = ""
	assert_eq(Map3DQuality.resolve(CFG, "Apple M5 Pro", "Apple"), "low")
	Map3DQuality.save_setting(CFG, Map3DQuality.AUTO)
	assert_eq(Map3DQuality.resolve(CFG, "Apple M1", "Apple"), "medium")
	Map3DQuality.forced = was


func test_the_menu_cycles_auto_then_each_tier() -> void:
	assert_eq(Map3DQuality.next_setting("auto"), "low")
	assert_eq(Map3DQuality.next_setting("ultra"), "auto")
