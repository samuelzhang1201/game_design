extends GutTest
## The Missive board as the WAR ROOM hangs it on its easel (spec
## 2026-10-02-war-room-v2 §1.3): the board alone, and a note's press is
## reported, not read.

func test_board_only_hides_the_desk_and_reports_a_note() -> void:
	Game.start_campaign(44)
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", 3,
		MissiveLog.subject("point", "", -1, Vector2(500, 300)), "A letter", []))
	var s: MissiveScreen = load("res://scenes/screens/missive_screen.tscn").instantiate()
	add_child_autofree(s)
	s.set_board_only(true)
	s.visible = true
	await wait_process_frames(1)
	assert_true(s.board_only())
	assert_false(s.get_node("%Desk").visible, "no reading desk")
	assert_false(s.get_node("%Close").visible, "no close")
	watch_signals(s)
	var note := s.find_child("Note%d" % id, true, false) as Button
	assert_not_null(note)
	note.pressed.emit()
	assert_signal_emitted_with_parameters(s, "note_chosen", [id])
	assert_eq(s.selected(), -1, "the easel's board does not read the letter itself")


func test_the_full_board_still_reads_a_note() -> void:
	Game.start_campaign(44)
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", 3,
		MissiveLog.subject("point", "", -1, Vector2(500, 300)), "A letter", []))
	var s: MissiveScreen = load("res://scenes/screens/missive_screen.tscn").instantiate()
	add_child_autofree(s)
	s.refresh()
	await wait_process_frames(1)
	(s.find_child("Note%d" % id, true, false) as Button).pressed.emit()
	assert_eq(s.selected(), id)
