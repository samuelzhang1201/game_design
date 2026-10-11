extends GutTest
## The WAR ROOM's tool roll wears painted ink glyphs (library W-61..W-68) and
## the resolutions' button its rolled scroll (U-61), all from
## GameArt.WAR_TOOL_ART: every slot of the authored roll finds its drawing and
## inks it in its own colour (the crayons in theirs), and a key the table
## lacks falls back to the vector glyph without error.

const KEYS := ["hand", "crayon", "arrow", "front", "phase", "objective", "piece", "scrape", "scroll"]


func test_the_table_has_every_tool_and_the_scroll() -> void:
	var t := GameArt.table(GameArt.WAR_TOOL_ART)
	for k: String in KEYS:
		assert_true(t.of(k) is Texture2D, "%s is a texture in war_tool_art.tres" % k)


func test_every_slot_of_the_roll_inks_its_glyph() -> void:
	var roll: WarToolRoll = load("res://scenes/war_room/war_tool_roll.tscn").instantiate()
	add_child_autofree(roll)
	for s: WarToolSlot in roll.slots():
		var tex := s.inked_glyph()
		assert_not_null(tex, "%s (%s) has a painted glyph" % [s.key, WarToolRoll.side_of(s)])
		assert_same(tex, s.inked_glyph(), "the inked glyph is cached")


func test_a_crayon_is_inked_in_its_own_colour_and_the_hand_in_the_pale_ink() -> void:
	var roll: WarToolRoll = load("res://scenes/war_room/war_tool_roll.tscn").instantiate()
	add_child_autofree(roll)
	var red := roll.slot("red", "red")
	var blue := roll.slot("blue", "blue")
	assert_eq(red.art_key(), "crayon")
	assert_eq(blue.art_key(), "crayon")
	assert_eq(red.glyph_colour(), red.stick_color)
	assert_eq(blue.glyph_colour(), blue.stick_color)
	assert_ne(red.inked_glyph(), blue.inked_glyph(), "each crayon is inked in its side's colour")
	var hand := roll.slot("hand")
	assert_eq(hand.glyph_colour(), hand.glyph_ink)
	var ink := (red.inked_glyph() as ImageTexture).get_image()
	if ink.get_width() < 16 or ink.get_height() < 16:
		pass_test("a placeholder texture (a headless renderer): the colour cannot be read here")
		return
	# the darkest inked pixel carries the crayon's colour (WarInkIcon: alpha from
	# the drawing's own alpha and darkness, the colour the ink's)
	var best := 0.0
	var best_c := Color.TRANSPARENT
	for y: int in ink.get_height():
		for x: int in ink.get_width():
			var c := ink.get_pixel(x, y)
			if c.a > best:
				best = c.a
				best_c = c
	assert_gt(best, 0.3, "the inked crayon has ink somewhere")
	if best > 0.3:
		assert_almost_eq(best_c.r, red.stick_color.r, 0.02, "an inked pixel carries the crayon's colour")
		assert_almost_eq(best_c.b, red.stick_color.b, 0.02, "an inked pixel carries the crayon's colour")


func test_an_unknown_key_falls_back_to_the_vector_glyph() -> void:
	var s := WarToolSlot.new()
	s.key = "nothing_like_this"
	add_child_autofree(s)
	assert_null(s.inked_glyph())
	s.size = Vector2(44, 44)
	s.queue_redraw()
	await wait_process_frames(1)
	pass_test("a slot without a painted glyph draws its vector fallback without error")
