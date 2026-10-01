extends GutTest
## scripts/war_room/ never reaches the Game autoload (spec §5), like map3d and ledger3d.

func test_no_war_room_script_names_game() -> void:
	var dir := DirAccess.open("res://scripts/war_room")
	assert_not_null(dir)
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			assert_false(FileAccess.get_file_as_string("res://scripts/war_room/" + f).contains("Game."), f)
