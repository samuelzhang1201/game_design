extends GutTest
## THE MAP LAID ON THE TABLE (owner 2026-10-01): Take the Throne lifts the
## title's last frame like a sheet and lays it where the map sheet lies, and
## the table's pieces come to it one by one instead of appearing at once.

const KEYS := ["ui_landing_lift_s", "ui_landing_carry_s", "ui_landing_settle_s",
	"ui_landing_cross_s", "ui_landing_ui_start_s", "ui_landing_ui_stagger_s", "ui_landing_ui_s",
	"ui_landing_voice_after_s"]
var _saved := {}

func before_each() -> void:
	for k: String in KEYS:
		_saved[k] = Game.data.balance.get(k)
		Game.data.balance[k] = 0.02  # the whole landing in a few frames

func after_each() -> void:
	for k: String in KEYS:
		Game.data.balance[k] = _saved[k]

func _frame() -> Texture2D:
	var img := Image.create(32, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.5, 0.2))
	return ImageTexture.create_from_image(img)

func _begun() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	(r.current_screen as MainMenu).menu_column().get_node("StartGame").pressed.emit()
	await wait_frames(2)
	return r

func test_no_frame_no_landing() -> void:
	var r := await _begun()
	assert_null(r.find_child("TableLanding", false, false),
		"headless the title shows no map, so there is no sheet to lay down")
	assert_null(TableLanding.play(r, r.current_screen, null))

func test_the_pieces_wait_for_the_sheet_and_then_all_come() -> void:
	var r := await _begun()
	var screen: Control = r.current_screen
	var top := screen.get_node("%TopBar") as Control
	var rest := top.position
	var l := TableLanding.play(r, screen, _frame())
	assert_not_null(l)
	assert_eq(top.modulate.a, 0.0, "the board waits off the table")
	assert_eq((screen.map_panel() as Control).modulate.a, 0.0, "the real sheet waits under the flying one")
	assert_eq(l.mouse_filter, Control.MOUSE_FILTER_STOP, "no click lands while the table is laid")
	await wait_until(func() -> bool: return not is_instance_valid(l), 3.0)
	assert_false(is_instance_valid(l), "the landing frees itself")
	assert_eq(top.modulate.a, 1.0, "the board is down")
	assert_eq(top.position, rest, "and back in its place")
	assert_eq((screen.map_panel() as Control).modulate.a, 1.0)

func test_the_sheet_starts_as_the_screen_and_ends_on_the_map_sheet() -> void:
	var l := TableLanding.new()
	l.size = Vector2(1280, 720)
	l.set("_target", Rect2(300, 80, 900, 560))
	var first: Dictionary = l.pose(0.0)
	assert_eq(first["rect"], Rect2(0, 0, 1280, 720), "it begins as the title filled the screen")
	assert_eq(first["tilt"], 0.0)
	var last: Dictionary = l.pose(10.0)
	assert_eq(last["rect"], Rect2(300, 80, 900, 560), "it ends exactly on the sheet")
	assert_eq(last["tilt"], 0.0, "square on the table")
	assert_eq(last["lift"], 0.0)
	l.free()
