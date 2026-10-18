extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
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
	assert_eq(String(scene.current_beat()["kind"]), "narration")
	assert_eq(String(scene.current_beat()["speaker"]), "", "narration is nameless")
	assert_true(scene.event_popup().visible, "narration pops centered")
	assert_string_contains(scene.said_text(), "ascended to the throne")
	# Keep the audience window and its Continue button inside the viewport.
	var panel: PanelContainer = scene.find_child("AudienceWindow", true, false)
	var viewport_h := scene.get_viewport_rect().size.y
	assert_lt(panel.size.y, viewport_h, "the window fits the viewport")
	assert_not_null(scene.speech_scroll(), "narration text scrolls inside the window")
	var pages := OpeningNarration.beats(Game.data).size()
	for i in pages:
		assert_eq(int(scene.current_beat()["page"]), i + 1)
		var replies := scene.reply_buttons()
		assert_eq(replies.size(), 1, "one button a page")
		var btn: Button = replies[0]
		await wait_until(func() -> bool: return btn.visible, 1.0)
		assert_true(btn.visible, "continue button revealed")
		assert_between(btn.get_global_rect().position.y, 0.0, viewport_h, "button on screen")
		assert_lt(btn.get_global_rect().end.y, viewport_h, "button bottom on screen")
		assert_eq(btn.text, "I am ready. Let the reign begin." if i == pages - 1 else "Continue")
		if scene.narration_left_frame != null:
			assert_true(scene.narration_left_frame.visible and scene.narration_right_frame.visible,
				"both busts up on page %d" % (i + 1))
		var scroll: ScrollContainer = scene.speech_scroll()
		await wait_process_frames(2)
		var bar := scroll.get_v_scroll_bar()
		assert_lte(bar.max_value, bar.page + 1.0, "page %d needs no scrolling" % (i + 1))
		btn.pressed.emit()
		await wait_process_frames(2)
	assert_true(r.current_screen is CourtScreen, "the table after the last page")
	# The chapter opener waits for its presenter before showing authored prose.
	assert_eq(String(Game.state.pending_event.get("event_id", "")), "c0_01")
	r.audience_with(ConversationBeats.event_presenter(Game.state, Game.data))
	await wait_process_frames(2)
	var stage: ConversationScene = r.current_screen
	var beat := stage.current_beat()
	assert_eq(String(beat["kind"]), "event")
	assert_eq(String(beat["event"]["event_id"]), "c0_01")
	assert_string_contains(stage.speech_text(), "older than the kingdom",
		"the authored scene is shown verbatim")

func _scene_with_frames() -> Array:
	var scene: ConversationScene = load("res://scenes/screens/conversation.tscn").instantiate()
	add_child_autofree(scene)
	var nodes: Array = []
	for n in 4:
		var c := Control.new()
		c.custom_minimum_size = Vector2(150, 200)
		scene.add_child(c)
		nodes.append(c)
	scene.narration_left_frame = nodes[0]
	scene.narration_left = nodes[1]
	scene.narration_right_frame = nodes[2]
	scene.narration_right = nodes[3]
	return [scene, nodes]

func test_frames_show_on_a_narration_page_both_lit_and_hide_after() -> void:
	var made := _scene_with_frames()
	var scene: ConversationScene = made[0]
	var nodes: Array = made[1]
	var beat: Dictionary = OpeningNarration.beats(SuiteData.repo())[0]
	scene._show_narration_busts(beat)
	for n: Control in nodes:
		assert_true(n.visible)
	assert_eq(nodes[1].modulate, nodes[3].modulate, "both busts lit alike")
	assert_eq(nodes[1].modulate, Color.WHITE, "the default dims nothing")
	scene._show_narration_busts({"kind": "minister"})
	for n: Control in nodes:
		assert_false(n.visible, "gone on the first minister beat")

func test_a_zero_sized_box_does_not_divide_by_zero() -> void:
	var made := _scene_with_frames()
	var scene: ConversationScene = made[0]
	var box := Control.new()
	box.custom_minimum_size = Vector2.ZERO
	scene.add_child(box)
	scene._fill_portrait(box, OpeningNarration.LEFT_ID)
	assert_eq(box.get_child_count(), 0, "nothing drawn into a box with no size")

func test_the_scene_busts_are_authored() -> void:
	var scene: ConversationScene = load("res://scenes/screens/conversation.tscn").instantiate()
	add_child_autofree(scene)
	if scene.narration_left == null or scene.narration_left_frame == null:
		pending("Phase E2: NarrationLeftFrame/NarrationRightFrame not yet authored in conversation.tscn")
		return
	assert_not_null(scene.narration_right)
	assert_not_null(scene.narration_right_frame)
