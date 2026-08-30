extends GutTest
## Locks the fit-any-screen guarantee (user requirement 2026-08-30): the UI
## is authored at a 640x360 design viewport and must scale to fill whatever
## screen the player has — fullscreen by default, proportional canvas_items
## stretch, expand aspect (no cropping, no distortion, no dead bars), and a
## window that can never shrink below the design size.

const DESIGN := Vector2i(640, 360)

var _original_size: Vector2i

func before_each() -> void:
	_original_size = get_tree().root.size

func after_each() -> void:
	get_tree().root.size = _original_size

func test_project_stretch_settings_scale_to_any_screen() -> void:
	var w := get_tree().root
	assert_eq(w.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
		"UI scales as vectors, not blurry pixels")
	assert_eq(w.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_EXPAND,
		"any aspect ratio is filled edge-to-edge, never cropped")
	assert_eq(Vector2i(w.content_scale_size), DESIGN, "design viewport")
	assert_eq(int(ProjectSettings.get_setting("display/window/size/mode")), 3,
		"launches fullscreen on the player's monitor")

func test_window_cannot_shrink_below_design_size() -> void:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	assert_eq(get_window().min_size, GameRoot.MIN_WINDOW_SIZE)
	assert_eq(GameRoot.MIN_WINDOW_SIZE, DESIGN,
		"minimum window = design viewport, so nothing can ever clip")

func test_gameplay_fills_viewport_at_common_screen_shapes() -> void:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	# 16:9 monitor, 16:10 MacBook, 4:3 legacy, 21:9 ultrawide.
	for shape in [Vector2i(1920, 1080), Vector2i(1512, 982),
			Vector2i(1024, 768), Vector2i(2560, 1080)]:
		get_tree().root.size = shape
		await wait_frames(2)
		var viewport := r.get_viewport_rect().size
		# Expand-stretch: the scaled viewport is never smaller than the
		# design space in either axis (nothing squeezed off screen)...
		assert_gte(viewport.x + 0.001, float(DESIGN.x), "width fits at %s" % shape)
		assert_gte(viewport.y + 0.001, float(DESIGN.y), "height fits at %s" % shape)
		# ...and the root control spans it exactly (no dead margins).
		assert_almost_eq(r.size.x, viewport.x, 0.5, "fills width at %s" % shape)
		assert_almost_eq(r.size.y, viewport.y, 0.5, "fills height at %s" % shape)
