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

## User ruling (2026-08-29): every council minister has full-body art in
## assets/portraits/full/ (the two provided artworks reused by archetype
## until per-minister art lands).
func test_full_art_exists_for_all_five_ministers() -> void:
	for id in ["char_chancellor", "char_marshal", "char_steward",
			"char_spymaster", "char_chaplain"]:
		assert_not_null(CharacterPortrait.full_texture_for(id),
			"assets/portraits/full/%s.png should load" % id)

func test_full_art_null_for_character_without_it() -> void:
	assert_null(CharacterPortrait.full_texture_for("herald"))

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
