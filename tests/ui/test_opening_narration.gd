extends GutTest
## The opening background narration cut into pages (owner 2026-10-12): every
## page loads, none is empty or too long for one box, the sides name Malvern
## (left) and the player (right), and the player walks the pages with Continue
## into the reign.

func _segments() -> Array:
	return OpeningNarration.segments(SuiteData.repo())

func test_the_story_is_cut_into_pages() -> void:
	var segs := _segments()
	assert_eq(segs.size(), 11, "one page a topic")
	assert_eq(OpeningNarration.beats(SuiteData.repo()).size(), segs.size())

func test_no_page_is_empty_or_too_long_and_every_page_has_a_side() -> void:
	var repo := SuiteData.repo()
	var cap := int(repo.bal("opening_segment_max_chars"))
	for s: Dictionary in OpeningNarration.segments(repo):
		var text := String(s["text"])
		assert_ne(text.strip_edges(), "", "no empty page")
		assert_lte(text.length(), cap, "fits a box: " + text.left(30))
		assert_true(String(s["side"]) in ["left", "right"])
		assert_eq(String(s["portrait_id"]),
			OpeningNarration.LEFT_ID if s["side"] == "left" else OpeningNarration.RIGHT_ID)
		assert_false(text.contains("{"), "realm tokens filled")
		assert_false(text.contains("**"), "markdown stripped")

func test_beats_carry_page_numbers_and_the_portraits_exist() -> void:
	var beats := OpeningNarration.beats(SuiteData.repo())
	for i in beats.size():
		assert_eq(int(beats[i]["page"]), i + 1)
		assert_eq(int(beats[i]["pages"]), beats.size())
		assert_eq(String(beats[i]["kind"]), "narration")
		assert_eq(String(beats[i]["speaker"]), "", "the narration is nameless")
	assert_not_null(CharacterPortrait.full_texture_for(OpeningNarration.LEFT_ID))
	assert_not_null(CharacterPortrait.full_texture_for(OpeningNarration.RIGHT_ID))

func test_both_speakers_are_used() -> void:
	var sides := {}
	for s: Dictionary in _segments():
		sides[s["side"]] = true
	assert_true(sides.has("left") and sides.has("right"))

func test_a_missing_file_gives_no_pages() -> void:
	assert_eq(OpeningNarration.segments(SuiteData.repo(), "res://game_story/nope.md").size(), 0)

func test_continue_walks_every_page_then_the_reign_begins() -> void:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	var scene: ConversationScene = r.current_screen
	var pages := OpeningNarration.beats(Game.data).size()
	for i in pages:
		assert_eq(int(scene.current_beat()["page"]), i + 1)
		var replies := scene.reply_buttons()
		assert_eq(replies.size(), 1, "one button a page")
		var btn: Button = replies[0]
		await wait_until(func() -> bool: return btn.visible, 1.0)
		assert_eq(btn.text, "I am ready. Let the reign begin." if i == pages - 1 else "Continue")
		var scroll: ScrollContainer = scene.speech_scroll()
		await wait_process_frames(2)
		var bar := scroll.get_v_scroll_bar()
		assert_lte(bar.max_value, bar.page + 1.0, "page %d needs no scrolling" % (i + 1))
		btn.pressed.emit()
		await wait_process_frames(2)
	assert_true(r.current_screen is CourtScreen, "the table after the last page")
