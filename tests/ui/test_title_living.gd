extends GutTest
## THE LIVING REALM (owner 2026-10-01, title plan A; the hero look 2026-10-11):
## on the war table the title's words stand over the live map (the bare table
## when, as here headless, no world can be shown) — the name and the ways in
## bottom left, the SAME rows as the pause menu top right, the music as a
## speaker, and a caption naming the place — after the black of launch.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_the_title_is_the_living_realm_layout() -> void:
	var r := _root()
	await wait_process_frames(2)
	var menu: MainMenu = r.current_screen
	assert_not_null(menu.find_child("Hero", true, false), "the words stand bottom left")
	assert_not_null(menu.find_child("Title_Crown", true, false))
	assert_not_null(menu.find_child("TitleArms", true, false), "the crown's arms top left")
	for row in ["StartGame", "LoadGame", "MusicToggle", "GraphicsQuality", "FrameCap", "FpsToggle", "DevMode", "Quit"]:
		assert_not_null(menu.row(row), "the menu keeps the row " + row)
	assert_ne(menu.row("StartGame").text, "", "the first row is worded")
	assert_false(menu.row("MusicToggle").visible, "the music is the speaker")
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
	r.current_screen.row("LoadGame").pressed.emit()
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
	r.current_screen.row("LoadGame").pressed.emit()
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.COURT, "the chronicle resumes at court")
	assert_null(MainMenu.landing_frame, "the frame is taken once")
	assert_not_null(r.find_child("TableLanding", false, false), "and laid on the table")

## The launch (owner 2026-10-11): black until the title can show itself, then
## the black lifts and every word comes in; without a world (headless) the
## title enters over the bare table at once.
func test_the_title_enters_out_of_the_black() -> void:
	var r := _root()
	await wait_process_frames(1)
	var menu: MainMenu = r.current_screen
	var curtain := menu.get_node("Curtain") as CanvasItem
	assert_true(curtain.visible, "the window starts black")
	assert_eq(menu.find_child("Title_Crown", true, false).modulate.a, 0.0, "the words wait")
	await wait_until(func() -> bool: return not menu.realm_pending(), 10.0)
	assert_false(curtain.visible, "the black has lifted")
	assert_eq(menu.find_child("Title_Crown", true, false).modulate.a, 1.0, "the name is in")
	assert_eq(menu.row("StartGame").modulate.a, 1.0)

## The speaker is the Music row's switch: a press turns the music and the
## speaker's face, and the pause menu's row reads the same.
func test_the_speaker_turns_the_music() -> void:
	var r := _root()
	await wait_process_frames(2)
	var menu: MainMenu = r.current_screen
	var sound := menu.find_child("Sound", true, false) as Button
	var was := menu.row("MusicToggle").text
	sound.pressed.emit()
	assert_ne(menu.row("MusicToggle").text, was, "the music turned")
	assert_eq(sound.icon, menu.speaker_off if menu.row("MusicToggle").text.ends_with("Off") else menu.speaker_on)
	sound.pressed.emit()
	assert_eq(menu.row("MusicToggle").text, was, "and back")
