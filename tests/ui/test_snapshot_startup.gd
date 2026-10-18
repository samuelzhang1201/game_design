extends GutTest


func test_root_shot_frames_wait_for_overlay_startup() -> void:
	var shot := load("res://tools/snapshot_screen.gd").new() as Node
	var root := GameRoot.new()
	autofree(shot)
	autofree(root)
	shot._root = root
	shot._process(0.016)
	assert_eq(shot._frames, 0, "startup must not consume scheduled input or capture frames")
	root._report_popup = MissiveReportPopup.new()
	root._report_popup.visible = false
	root.add_child(root._report_popup)
	root._overlays_made = true
	shot._process(0.016)
	assert_eq(shot._frames, 1, "the capture sequence begins once overlays exist")


func test_bare_screen_shot_frames_start_without_a_game_root() -> void:
	var shot := load("res://tools/snapshot_screen.gd").new() as Node
	autofree(shot)
	shot._process(0.016)
	assert_eq(shot._frames, 1)
