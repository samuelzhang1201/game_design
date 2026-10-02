extends GutTest
## THE LIVING REALM (owner 2026-10-01, title plan A): on the war table the
## title is a column of words on the reading side over the live map (the
## painted page when, as here headless, no world can be shown), the SAME rows
## as the pause menu, and a caption naming the place.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_the_title_is_the_living_realm_layout() -> void:
	var r := _root()
	await wait_process_frames(2)
	var menu: MainMenu = r.current_screen
	assert_not_null(menu.find_child("TitleColumn", true, false), "the words stand down the reading side")
	assert_not_null(menu.find_child("Title_Crown", true, false))
	assert_not_null(menu.find_child("TitleArms", true, false), "the crown's arms over the name")
	var col := menu.menu_column()
	for row in ["StartGame", "LoadGame", "MusicToggle", "GraphicsQuality", "FrameCap", "DevMode", "Quit"]:
		assert_not_null(col.get_node_or_null(row), "the menu keeps the row " + row)
	assert_ne((col.get_node("StartGame") as Button).text, "", "the first row is worded")
	var place: Label = menu.find_child("Place", true, false)
	assert_not_null(place, "a caption names the place")
	assert_string_contains(place.text, "seat of House")
	assert_null(menu.find_child("LivingRealm", true, false), "no live map headless: the painted page")

## Continue the Chronicle (owner 2026-10-01: the same as Take the Throne):
## with no save the title says so and stays; with one, the reign resumes and
## the title's frame is laid on the court's table like a new reign's.
func test_continue_without_a_save_stays_on_the_title() -> void:
	var r := _root()
	await wait_process_frames(2)
	var path := Game.save_path
	Game.save_path = "user://no_such_realm.json"
	r.current_screen.menu_column().get_node("LoadGame").pressed.emit()
	await wait_process_frames(2)
	Game.save_path = path
	assert_true(r.current_screen is MainMenu, "nothing to continue: the title stays")

func test_continue_the_chronicle_lays_the_map_on_the_table() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	assert_true(Game.save_campaign())
	Game.menu_requested.emit()
	r.pause_menu().find_child("Restart", true, false).pressed.emit()
	await wait_process_frames(2)
	var img := Image.create(32, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.5, 0.2))
	MainMenu.landing_frame = ImageTexture.create_from_image(img)  # as the sweep would leave it
	r.current_screen.menu_column().get_node("LoadGame").pressed.emit()
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.COURT, "the chronicle resumes at court")
	assert_null(MainMenu.landing_frame, "the frame is taken once")
	assert_not_null(r.find_child("TableLanding", false, false), "and laid on the table")
