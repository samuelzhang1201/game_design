extends GutTest
## The conversation column gives the location a thin clipped strip; a view
## that keeps its full design size inside it loses the name (2026-09-13:
## the banner rendered as a bare brown bar with the label cut off below).

func _slot(min_size: Vector2) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = min_size
	slot.clip_contents = true
	add_child_autofree(slot)
	slot.size = min_size
	return slot


func test_the_banner_fits_a_thin_slot() -> void:
	Game.start_campaign(42)
	var slot := _slot(Vector2(128, 22))
	var view := LocationView.instantiate_for("council_chamber")
	slot.add_child(view)
	await wait_process_frames(2)
	assert_almost_eq(view.size.y, 22.0, 0.5,
		"the view takes the slot's height, not the 52 px design height")
	var label: Label = view.get_node("Gen_Label")
	assert_true(label.size.y <= slot.size.y + 0.5,
		"the name label stays inside the strip the slot allows")
	assert_ne(label.text, "", "the strip still names the location")


func test_a_roomy_slot_keeps_the_design_size() -> void:
	Game.start_campaign(42)
	var host := Control.new()
	add_child_autofree(host)
	var view := LocationView.instantiate_for("council_chamber")
	host.add_child(view)
	await wait_process_frames(2)
	assert_almost_eq(view.size.y, LocationView.VIEW_SIZE.y, 0.5,
		"with no slot minimum the view keeps its own design size")
