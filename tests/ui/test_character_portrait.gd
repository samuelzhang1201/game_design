extends GutTest

func before_each() -> void:
	Game.start_campaign(42)

func test_known_character_gets_its_own_scene() -> void:
	var p := CharacterPortrait.instantiate_for("char_marshal")
	add_child_autofree(p)
	assert_string_contains(p.scene_file_path, "char_marshal.tscn")
	assert_eq(p.character_id, "char_marshal")

func test_unknown_character_falls_back_to_base_scene() -> void:
	var p := CharacterPortrait.instantiate_for("char_future_recruit")
	add_child_autofree(p)
	assert_string_contains(p.scene_file_path, "character_portrait.tscn")

func test_minister_portrait_has_badge_and_tooltip() -> void:
	Game.state.characters["char_chaplain"].change_opinion(-6,
		"tithed the church (opposes, orthodoxy)", 1)
	var p := CharacterPortrait.instantiate_for("char_chaplain")
	add_child_autofree(p)
	await wait_frames(2)
	assert_not_null(p.get_node_or_null("Gen_Badge"))
	assert_string_contains(p.tooltip_text, "Father Odo")
	assert_string_contains(p.tooltip_text, "opposes, orthodoxy")

func test_non_character_portrait_has_no_badge() -> void:
	var p := CharacterPortrait.instantiate_for("herald")
	add_child_autofree(p)
	await wait_frames(2)
	assert_null(p.get_node_or_null("Gen_Badge"))
	assert_ne(p.get_child_count(), 0)  # default visual built

func test_full_art_exists_for_chancellor_and_marshal() -> void:
	assert_not_null(CharacterPortrait.full_texture_for("char_chancellor"),
		"assets/portraits/full/char_chancellor.png should load")
	assert_not_null(CharacterPortrait.full_texture_for("char_marshal"),
		"assets/portraits/full/char_marshal.png should load")

func test_full_art_null_for_character_without_it() -> void:
	assert_null(CharacterPortrait.full_texture_for("char_chaplain"))

func test_custom_art_node_suppresses_default_visual() -> void:
	var p := CharacterPortrait.instantiate_for("char_steward")
	var custom := Node2D.new()
	custom.name = "CustomArt"
	p.add_child(custom)
	add_child_autofree(p)
	await wait_frames(2)
	assert_null(p.get_node_or_null("Gen_Texture"), "default art skipped when CustomArt present")
	assert_null(p.get_node_or_null("Gen_Fallback"))
	assert_not_null(p.get_node_or_null("Gen_Badge"), "badge still maintained")
