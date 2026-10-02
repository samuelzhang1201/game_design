class_name Map3DCloseEffects
extends RefCounted
## The finishing effects are spent up close (owner 2026-10-02, 按缩放切换):
## within map3d_close_effects_m a tier wears its msaa / screen_aa / ssao,
## farther out its far_* values (graphics_quality.csv, blank: the same) — at
## the opening view MSAA 4x with SSAO cost the high tier ~9 ms and matched
## shots showed no difference. Called on every camera move
## (Map3DEnvironment.follow_camera); only a value that changes is set, so a
## move costs nothing and only a crossing reallocates MSAA's targets.


static func apply(repo: DataRepository, vp: SubViewport, env: Environment, row: Dictionary,
		distance_m: float) -> void:
	var far := distance_m > repo.bal("map3d_close_effects_m")
	var pick := func(key: String) -> float:
		var near_v := Map3DQuality.num(row, key, 0.0)
		return Map3DQuality.num(row, "far_" + key, near_v) if far else near_v
	if vp != null:
		var msaa: Viewport.MSAA = {2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(
			int(pick.call("msaa")), Viewport.MSAA_DISABLED)
		if vp.msaa_3d != msaa:
			vp.msaa_3d = msaa
		var aa: Viewport.ScreenSpaceAA = {1: Viewport.SCREEN_SPACE_AA_FXAA, 2: Viewport.SCREEN_SPACE_AA_SMAA}.get(
			int(pick.call("screen_aa")), Viewport.SCREEN_SPACE_AA_DISABLED)
		if vp.screen_space_aa != aa:
			vp.screen_space_aa = aa
	if env != null:
		var ao := repo.bal("map3d_env_ssao") > 0.0 and Map3DQuality.num(row, "ssao", 1.0) > 0.0 \
			and (not far or Map3DQuality.num(row, "far_ssao", 1.0) > 0.0)
		if env.ssao_enabled != ao:
			env.ssao_enabled = ao
