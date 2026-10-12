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


## Owner item 15 (R4): the pale-yellow smear was the Hand slot's glyph; Phase E4
## deletes Row/Hand and Row/Sep0 in the editor. Pending until then, so the step
## is not forgotten.
func test_the_roll_has_no_hand_slot() -> void:
	var roll: WarToolRoll = load("res://scenes/war_room/war_tool_roll.tscn").instantiate()
	add_child_autofree(roll)
	if roll.slot("hand") != null:
		pending("Phase E4: delete Row/Hand and Row/Sep0 in war_tool_roll.tscn")
		return
	assert_null(roll.get_node_or_null("Row/Sep0"), "the separator after the hand went with it")


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
	var hand := roll.slot("hand")   # R4: the roll needs no hand slot; if one stands, it is pale
	if hand != null:
		assert_eq(hand.glyph_colour(), hand.glyph_ink)
	# the inking itself, on a drawing made here (CI's headless renderer reads no
	# pixels back from an imported texture): a dark stroke on clear comes out
	# in the crayon's colour at full alpha, the light fill at glyph_light_keep
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x: int in range(4, 28):
		img.set_pixel(x, 16, Color(0.05, 0.03, 0.02, 1.0))   # the stroke
		img.set_pixel(x, 20, Color(0.95, 0.9, 0.8, 1.0))     # the pale fill
	var inked := WarInkIcon.inked(ImageTexture.create_from_image(img), red.stick_color, red.glyph_light_keep).get_image()
	var stroke := inked.get_pixel(16, 16)
	var fill := inked.get_pixel(16, 20)
	assert_almost_eq(stroke.r, red.stick_color.r, 0.02, "the stroke carries the crayon's red")
	assert_almost_eq(stroke.b, red.stick_color.b, 0.02)
	assert_gt(stroke.a, 0.95, "the stroke is opaque ink")
	assert_almost_eq(fill.a, red.glyph_light_keep, 0.08, "the light fill keeps glyph_light_keep of its alpha")
	assert_almost_eq(inked.get_pixel(0, 0).a, 0.0, 0.001, "clear stays clear")


func test_an_unknown_key_falls_back_to_the_vector_glyph() -> void:
	var s := WarToolSlot.new()
	s.key = "nothing_like_this"
	add_child_autofree(s)
	assert_null(s.inked_glyph())
	s.size = Vector2(44, 44)
	s.queue_redraw()
	await wait_process_frames(1)
	pass_test("a slot without a painted glyph draws its vector fallback without error")
