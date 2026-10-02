extends GutTest
## Graphics tiers for ordinary machines (spec 2026-09-20 §4):
## data/graphics_quality.csv read by Map3DQuality — pure: the row, the GPU
## detection, the saved setting.

const RunDir := preload("res://tests/run_dir.gd")
## In this run's own directory (tests/run_dir.gd), which no other suite deletes.
var _cfg := RunDir.dir("map3d_quality").path_join("settings.cfg")


func before_all() -> void:
	Game.start_campaign(42)


func after_each() -> void:
	if FileAccess.file_exists(_cfg):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_cfg))
	# test_the_pause_menu_remembers_the_tier writes the REAL settings file
	# (GameRoot.settings_path, not _cfg); restore it here so a failing assert
	# mid-test can't leave it pinned at a tier.
	Map3DQuality.save_setting(GameRoot.settings_path, Map3DQuality.AUTO)


func test_every_tier_has_a_row() -> void:
	for tier: String in Map3DQuality.TIERS:
		assert_true(Game.data.graphics_quality.has(tier), tier)
	assert_eq(Map3DQuality.row(Game.data, "nonsense"), Map3DQuality.row(Game.data, "high"))


## high is today's look: every multiplier 1 (balance.csv's own steps at the
## window's resolution), the clouds and shadows balance.csv's, the HUD unthrottled.
func test_high_is_todays_look() -> void:
	var r := Map3DQuality.row(Game.data, "high")
	for col: String in ["render_scale", "line_step_mul", "road_step_mul", "river_step_mul"]:
		assert_eq(Map3DQuality.num(r, col), 1.0, col)
	var world := (load(Map3DEnvironment.WORLD_SCENE) as PackedScene).instantiate()
	assert_eq(Map3DQuality.num(r, "clouds"), float((world.get_node("Clouds") as Map3DLayerClouds).max_clouds))
	assert_eq(Map3DQuality.num(r, "shadow_max_m"), (world.get_node("Sun") as Map3DSun).shadow_max_m)
	world.free()
	assert_eq(Map3DQuality.num(r, "hud_hz"), 0.0)


## A cheaper tier never draws a line, road or river in FINER steps than a dearer one.
func test_the_cheaper_tiers_take_longer_steps() -> void:
	for col: String in ["line_step_mul", "road_step_mul", "river_step_mul"]:
		var low := Map3DQuality.num(Map3DQuality.row(Game.data, "low"), col)
		var med := Map3DQuality.num(Map3DQuality.row(Game.data, "medium"), col)
		var high := Map3DQuality.num(Map3DQuality.row(Game.data, "high"), col)
		assert_gte(low, med, col + ": low over medium")
		assert_gte(med, high, col + ": medium over high")


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
		assert_eq(Map3DQuality.detect(k[0], k[1]), cases[k], "%s" % [k])


func test_the_setting_overrides_the_detection() -> void:
	assert_eq(Map3DQuality.setting(_cfg), Map3DQuality.AUTO, "no file: auto")
	Map3DQuality.save_setting(_cfg, "low")
	assert_eq(Map3DQuality.setting(_cfg), "low")
	var was := Map3DQuality.forced
	Map3DQuality.forced = ""
	assert_eq(Map3DQuality.resolve(_cfg, "Apple M5 Pro", "Apple"), "low")
	Map3DQuality.save_setting(_cfg, Map3DQuality.AUTO)
	assert_eq(Map3DQuality.resolve(_cfg, "Apple M1", "Apple"), "medium")
	Map3DQuality.forced = was


func test_the_menu_cycles_auto_then_each_tier() -> void:
	assert_eq(Map3DQuality.next_setting("auto"), "low")
	assert_eq(Map3DQuality.next_setting("ultra"), "auto")


var _q_fixture := RunDir.dir("map3d_quality").path_join("test_map3d_quality_world.tscn")


func _q_view() -> Map3DView:
	var root := Node3D.new()
	root.set_meta("map3d_world", {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
		"pack_px": [2560, 929], "sea_y": 5.0})
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _q_fixture)
	root.free()
	var v := Map3DView.create(Game.data, _q_fixture)
	# the authored scene fills its parent; pin the size these pixel counts assume
	v.set_anchors_preset(Control.PRESET_TOP_LEFT)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	v.refresh_borders()
	return v


func test_a_lower_render_scale_renders_fewer_pixels() -> void:
	var v := _q_view()
	assert_eq(v.quality_tier(), "high")
	assert_eq(v.viewport().size, Vector2i(800, 450))
	v.set_quality("low")
	assert_eq(v.viewport().size, Vector2i(int(800 * 0.67), int(450 * 0.67)))
	assert_almost_eq(v.context().viewport_px_scale(), 0.67, 0.0001)
	var ink := v.line_mesh("Kingdoms").surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(ink.get_shader_parameter("width_px")),
		float(Map3DLayerLines.KINGDOM_INK.get_shader_parameter("width_px")) * 0.67, 0.0001,
		"screen widths follow the pixels")


func test_picks_round_trip_at_any_render_scale() -> void:
	var v := _q_view()
	for tier: String in ["high", "low"]:
		v.set_quality(tier)
		var c := v.context()
		var checked := 0
		for e: Dictionary in c.projected_settlements():
			var p: Vector2 = e["screen"]
			if not bool(e["shown"]) or not Rect2(Vector2.ZERO, v.size).has_point(p):
				continue
			var hit: Variant = c.ground_at(p)
			assert_not_null(hit)
			var w: Vector3 = e["world"]
			assert_almost_eq((hit as Vector3).x, w.x, 1.0, "%s at %s" % [e["code"], tier])
			assert_almost_eq((hit as Vector3).z, w.z, 1.0)
			checked += 1
			if checked >= 8:
				break
		assert_gt(checked, 0)
		var capital := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
		var burg: Dictionary = Game.data.burgs[capital]
		v.set_military(false)  # the fleet lies at the capital; this is the town's pick
		v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])))
		assert_eq(v.pick_at(v.size * 0.5), {"kind": "burg", "code": capital}, tier)


func test_the_tier_reaches_clouds_steps_and_shadows() -> void:
	var v := _q_view()
	v.set_quality("low")
	var c := v.context()
	var low := Map3DQuality.row(Game.data, "low")
	assert_almost_eq(c.line_step(), Game.data.bal("map3d_line_step_m") * Map3DQuality.num(low, "line_step_mul"), 0.01)
	Game.set_clock_speed(1)
	v._process(0.1)
	assert_eq(v.cloud_count(), int(Map3DQuality.num(low, "clouds")), "the low tier's clouds over the whole map (owner 2026-09-30)")
	Game.set_clock_speed(0)
	assert_false((v.get_node("Viewport/World/Clouds/Shadows") as Node3D).visible)
	assert_false((v.get_node("Viewport/World/Sun") as DirectionalLight3D).shadow_enabled)
	v.set_quality("ultra")
	assert_eq(v.viewport().msaa_3d, Viewport.MSAA_4X)
	assert_true((v.get_node("Viewport/World/Sun") as DirectionalLight3D).shadow_enabled)


func test_a_throttled_hud_redraws_at_most_at_its_rate() -> void:
	var v := _q_view()
	var hud := v.get_node("Hud") as Map3DHud
	hud.hz = 30.0
	var n := hud.redraws
	hud.refresh()
	hud.refresh()
	assert_eq(hud.redraws, n + 1, "two moves in one frame, one redraw")
	hud._process(0.05)
	assert_eq(hud.redraws, n + 2, "the pending redraw lands after 1/30 s")


func test_the_pause_menu_remembers_the_tier() -> void:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	var button := r.pause_menu().find_child("GraphicsQuality", true, false) as Button
	assert_not_null(button)
	var before := r.quality_setting()
	button.pressed.emit()
	assert_eq(r.quality_setting(), Map3DQuality.next_setting(before))
	assert_eq(Map3DQuality.setting(GameRoot.settings_path), r.quality_setting())
	assert_string_contains(button.text, "Graphics")


## Forward+'s screen effects are per tier (2026-09-24): low has no SSAO,
## only ultra has SSIL, and a tier can only take an effect away — with the
## sky's own switch off, no tier turns it on.
func test_a_tier_only_takes_effects_away() -> void:
	var sky := _sky(true)
	Map3DEnvironment.apply_effects_quality(sky, Map3DQuality.row(Game.data, "low"))
	assert_false(sky.environment.ssao_enabled, "low: no SSAO")
	assert_false(sky.environment.ssil_enabled)
	assert_true(sky.environment.fog_enabled, "the haze stays on every tier")
	Map3DEnvironment.apply_effects_quality(sky, Map3DQuality.row(Game.data, "high"))
	assert_true(sky.environment.ssao_enabled)
	var off := _sky(false)
	Map3DEnvironment.apply_effects_quality(off, Map3DQuality.row(Game.data, "ultra"))
	assert_false(off.environment.ssao_enabled, "the sky's own switch off wins over every tier")
	sky.free()
	off.free()


func _sky(ssao: bool) -> Map3DSky:
	var sky := Map3DSky.new()
	sky.environment = Environment.new()
	sky.environment.ssao_enabled = ssao
	sky.remember()
	return sky


## Owner 2026-10-02 (按缩放切换): high wears MSAA 4x and SSAO up close and
## SMAA without SSAO past map3d_close_effects_m; ultra keeps its own at every
## zoom (its far_* are blank).
func test_the_finishing_effects_are_spent_up_close() -> void:
	var vp := SubViewport.new()
	var sky := _sky(true)
	var env := sky.environment
	var high := Map3DQuality.row(Game.data, "high")
	var edge := Game.data.bal("map3d_close_effects_m")
	Map3DCloseEffects.apply(Game.data, vp, sky, high, edge * 0.5)
	assert_eq(vp.msaa_3d, Viewport.MSAA_4X, "up close: MSAA 4x")
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_true(env.ssao_enabled)
	Map3DCloseEffects.apply(Game.data, vp, sky, high, edge * 2.0)
	assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED, "far out: no MSAA")
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_SMAA, "but SMAA")
	assert_false(env.ssao_enabled, "and no SSAO")
	Map3DCloseEffects.apply(Game.data, vp, sky, Map3DQuality.row(Game.data, "ultra"), edge * 2.0)
	assert_eq(vp.msaa_3d, Viewport.MSAA_4X, "ultra keeps its MSAA far out")
	vp.free()
	sky.free()


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
