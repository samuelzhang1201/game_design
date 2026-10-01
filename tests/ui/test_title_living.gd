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
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	assert_not_null(menu.find_child("TitleColumn", true, false), "the words stand down the reading side")
	assert_not_null(menu.find_child("Title_Crown", true, false))
	assert_not_null(menu.find_child("TitleArms", true, false), "the crown's arms over the name")
	var col := menu.menu_column()
	for row in ["StartGame", "LoadGame", "MusicToggle", "GraphicsQuality", "DevMode", "Quit"]:
		assert_not_null(col.get_node_or_null(row), "the menu keeps the row " + row)
	assert_eq((col.get_node("StartGame") as Button).text, "Take the Throne")
	var place: Label = menu.find_child("Place", true, false)
	assert_not_null(place, "a caption names the place")
	assert_string_contains(place.text, "seat of House")
	assert_null(menu.find_child("LivingRealm", true, false), "no live map headless: the painted page")

func test_take_the_throne_begins_the_reign_without_a_map() -> void:
	var r := _root()
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	menu.menu_column().get_node("StartGame").pressed.emit()
	await wait_frames(2)
	assert_false(r.current_screen is MainMenu, "with no map to sweep, the reign begins at once")
