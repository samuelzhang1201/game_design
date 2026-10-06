extends GutTest
## The WAR ROOM's hover slip (spec 2026-10-07-war-room-scale-hover §4.2).


func test_the_slip_sits_below_right_and_flips_at_the_edges() -> void:
	var bounds := Rect2(0, 0, 1000, 600)
	var size := Vector2(300, 200)
	assert_eq(WarHoverSlip.place(Vector2(100, 100), size, bounds, 20.0), Vector2(120, 120))
	assert_eq(WarHoverSlip.place(Vector2(900, 100), size, bounds, 20.0), Vector2(580, 120), "flipped left")
	assert_eq(WarHoverSlip.place(Vector2(100, 550), size, bounds, 20.0), Vector2(120, 330), "flipped up")


func test_the_lines_become_labels_of_their_kinds() -> void:
	var slip: WarHoverSlip = load("res://scenes/war_room/war_hover_slip.tscn").instantiate()
	add_child_autofree(slip)
	slip.show_lines([{"text": "Knutham (Axbrigh)", "kind": "title"}, {"text": "", "kind": "rule"},
		{"text": "Hills · 780 m", "kind": "line"}], Vector2(10, 10), Rect2(0, 0, 800, 600))
	await wait_process_frames(1)
	assert_true(slip.visible)
	var kids := slip.get_node("%Lines").get_children()
	assert_eq(kids.size(), 3)
	assert_eq((kids[0] as Label).theme_type_variation, &"WarHoverTitle")
	assert_true(kids[1] is HSeparator)
	assert_eq((kids[2] as Label).text, "Hills · 780 m")
	slip.hide_slip()
	assert_false(slip.visible)
