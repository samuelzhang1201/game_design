extends GutTest
## The compass wheel (owner 2026-09-14; the 3D HUD's since the 2D map was
## deleted 2026-09-24): CompassLayer turns clockwise only while time runs,
## faster at a faster clock, and without its art the vector rose stays.
## Moved here from the 2D map's tests.


func test_the_compass_art_turns_only_while_time_runs() -> void:
	Game.start_campaign(42)
	var layer := CompassLayer.new()
	add_child_autofree(layer)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	layer.texture = ImageTexture.create_from_image(img)
	assert_true(layer.has_art())
	Game.set_clock_speed(0)
	layer.angle = 0.0
	await wait_process_frames(5)
	assert_eq(layer.angle, 0.0, "paused: the compass holds still")
	Game.set_clock_speed(1)
	await wait_process_frames(5)
	var slow := layer.angle
	assert_gt(slow, 0.0, "time runs: it turns clockwise")
	Game.set_clock_speed(4)
	layer.angle = 0.0
	await wait_process_frames(5)
	Game.set_clock_speed(0)
	assert_gt(layer.angle, slow, "a faster clock turns it faster")
	layer.texture = null
	assert_false(layer.has_art(), "without the art the vector rose stays")
