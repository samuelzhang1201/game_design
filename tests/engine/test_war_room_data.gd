extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM's tables (spec 2026-10-01-war-room-design §5): they load, and
## every row names something that exists.

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_every_balance_key_the_room_reads_is_there() -> void:
	for key in ["war_sheet_deg", "war_intel_hazard_px", "war_intel_hazard_alpha", "war_hazard_hatch_km", "war_intel_hazard_label_px", "war_hazard_dot_ratio", "war_works_min_gold", "war_trade_tier1_gold", "war_trade_tier2_gold", "war_trade_tier3_gold", "war_ink_trade_px", "war_ink_works_px", "war_ink_market_px", "war_hazard_sample_km", "war_mark_reach_px", "war_mark_px", "war_mark_reach_alpha", "war_mark_hover_km", "war_mark_hover_max", "war_mark_legend_chars", "war_detail_level_m", "war_detail_cover", "war_detail_inner", "war_detail_texture_px", "war_detail_feather", "war_fine_texels_per_px", "war_hover_budget_ms", "war_hover_width_px", "war_hover_gap_px", "war_hover_delay_s", "war_hover_still_px", "war_contour_near_m", "war_fine_far_m", "war_fine_near_m", "war_fine_note_px", "war_fine_route_px", "war_fine_mark_px", "war_fine_figure_px", "war_fine_contour_level_m", "war_fine_contour_label_km", "war_fine_contour_grid", "war_chart_label_every", "war_sheet_collar_km", "war_grid_deg", "war_collar_ink", "war_collar_shade", "war_neat_px", "war_neat_gap_px", "war_chart_axis_margin_m", "war_toss_apex_m", "war_toss_fly_s", "war_toss_turns_min", "war_toss_turns_max", "war_toss_bounces", "war_toss_bounce_ratio", "war_toss_settle_s", "war_toss_margin", "war_toss_hand_m", "war_ink_wood_px", "war_ink_wood_step_km", "war_ink_wood_min_cover", "war_ink_wood_jitter", "war_ink_manor_px", "war_ink_manor_dash_px", "war_ink_manor_gap_px", "war_ink_manor_label_px", "war_ink_manor_clear_px", "war_ink_char_w", "war_ink_wall_ratio", "war_ink_anchor_ratio", "war_ink_river_discharge_k", "war_ink_river_max_px", "war_ink_river_label_px", "war_ink_bridge_px", "war_intel_texture_px", "war_intel_supply_px", "war_intel_supply_dash_px", "war_intel_supply_gap_px", "war_intel_courier_px", "war_intel_weather_px", "war_intel_label_px", "war_intel_spy_ring_px", "war_intel_spy_spread_k",
			"war_table_w_m", "war_relief_grid", "war_relief_exaggeration", "war_contour_m",
			"war_contour_index_every", "war_sheet_texture_px", "war_sheet_swap_s",
			"war_cam_distance_m", "war_cam_min_m", "war_cam_max_m", "war_cam_pitch_near_deg",
			"war_cam_pitch_far_deg", "war_cam_pitch_mid_deg", "war_cam_turn_deg_per_px", "war_cam_north_s", "war_cam_wall_clear_m",
			"war_room_floor_x_m", "war_key_pan_screens_per_s", "war_click_slop_px", "war_unroll_s", "war_unroll_roller_px", "war_board_fly_s", "war_board_distance_m", "war_board_min_m", "war_board_max_m", "war_board_px", "war_board_layout_px", "war_room_floor_z_min_m", "war_room_floor_z_max_m", "war_cam_zoom_step", "war_piece_base_mm", "war_piece_base_h_mm",
			"war_piece_figure_mm", "war_piece_plinth_mm", "war_piece_gap", "war_pose_frame_march", "war_pose_frame_garrison",
			"war_pose_frame_standby", "war_plot_push_s", "war_pick_px", "war_rake_min_px",
			"war_explode_s", "war_explode_m", "war_ink_road_px", "war_ink_trail_px", "war_ink_river_px",
			"war_ink_coast_px", "war_ink_border_px", "war_ink_band_px", "war_ink_seam_px",
			"war_ink_town_px", "war_ink_label_px", "war_ink_dash_px", "war_ink_gap_px",
			"war_draft_alpha", "war_deploy_wax_s", "war_deploy_press_s",
			"war_deploy_roll_s", "war_deploy_rolled_share"]:
		assert_true(repo.balance.has(key), key)


func test_the_palette_has_every_ink_the_room_draws() -> void:
	for key in ["paper", "paper_age", "ink", "ink_faint", "contour_figure", "hazard_ink", "rubric", "sea_ink", "river_ink",
			"chalk", "brass", "arrow", "candle", "background", "pencil", "plan_blue", "plan_blue_draft"]:
		assert_true(repo.war_palette.has(key), key)
		assert_true(repo.war_palette[key] is Color, key)


func test_every_drill_names_a_known_clip_and_real_arms() -> void:
	var arms: Dictionary = repo.world_table("military", "unit_types")
	assert_gt(repo.war_drills.size(), 0)
	for row: Dictionary in repo.war_drills:
		assert_true(String(row["clip"]) in ["MARCH", "STANDBY", "GARRISON", "ATTACK", "DEFEND"], String(row["key"]))
		for arm: String in row["arms"]:
			assert_true(arms.has(arm), "%s names arm %s" % [row["key"], arm])


func test_every_equipment_row_names_a_real_arm() -> void:
	var arms: Dictionary = repo.world_table("military", "unit_types")
	assert_gt(repo.war_equipment.size(), 0)
	for row: Dictionary in repo.war_equipment:
		assert_true(arms.has(String(row["arm"])), String(row["part"]))
		assert_ne(String(row["label"]), "")
		# shown to the player: a plain description, never empty, never a design note
		assert_ne(String(row["note"]), "", "%s %s has no note" % [row["arm"], row["part"]])
		assert_false(String(row["note"]).contains("stands in"), String(row["part"]))
		assert_false(String(row["note"]).contains("WAR ROOM"), String(row["part"]))


func test_the_folio_sections_are_the_six_of_the_spec_in_order() -> void:
	var keys: Array = repo.war_folio_sections.map(func(r: Dictionary) -> String: return String(r["key"]))
	assert_eq(keys, ["composition", "arms", "morale", "supply", "ground", "march"])
