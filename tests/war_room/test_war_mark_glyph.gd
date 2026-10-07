extends GutTest
## Every glyph the data may name draws without error (spec 2026-10-07-war-room-p2 §1.3).


class Probe:
	extends Node2D
	var glyph := ""
	func _draw() -> void:
		WarMarkGlyph.draw(self, glyph, Vector2(20, 20), 16.0, Color.BLACK)


func test_every_glyph_draws() -> void:
	for g: String in WarMarks.GLYPHS:
		var p := Probe.new()
		p.glyph = g
		add_child_autofree(p)
		p.queue_redraw()
		await wait_process_frames(1)
		assert_true(WarMarkGlyph.knows(g), g)
	assert_false(WarMarkGlyph.knows("dragon"))
