extends GutTest
## The board's art pieces (spec 2026-09-28-courier-art §5) are styles edited
## in the inspector (owner 2026-10-02): assets/2D/ui/missive_board/styles/.
## Each is a ScaledNineSlice of its installed art, nine-sliced by its margin in
## TEXTURE px and drawn at its scale — the art is installed at 3 texture px per
## design px for the ~3x window scale, and StyleBoxTexture has no such scale
## (CLAUDE.md notes the same trap for the vellum plate).

const DIR := "res://assets/2D/ui/missive_board/styles/"


func _style(key: String) -> ScaledNineSlice:
	var s := load(DIR + key + ".tres") as ScaledNineSlice
	assert_not_null(s, key)
	assert_not_null(s.texture, key + " wears its art")
	return s


func test_a_slip_is_nine_sliced_by_its_margin_at_its_scale() -> void:
	var s := _style("note")
	assert_gt(s.scale, 1.0, "installed hi-res")
	assert_almost_eq(s.draw_inset(), s.source_inset / s.scale, 0.001, "the drawn corner is the margin scaled down")
	assert_eq(s.get_content_margin(SIDE_LEFT), 11.0, "the text sits just inside the slip's rule")


## The board's wood TILES (no corners): its weave at its real texel density
## however large the board is drawn.
func test_the_wood_tiles_under_the_frame() -> void:
	var wood := _style("board_wood")
	assert_eq(wood.source_inset, 0.0)
	var frame := _style("frame")
	assert_eq(frame.fill, wood, "the frame's clear opening shows the wood")
	assert_eq(frame.get_content_margin(SIDE_TOP), 32.0, "content clears the carved border")


## Every piece of the board is installed and wears its art.
func test_every_piece_wears_its_art() -> void:
	for key: String in ["frame", "board_wood", "plaque", "desk", "report_letter", "note", "note_lit",
			"note_hover", "note_pressed"]:
		_style(key)
	assert_ne(_style("note_hover").tint, Color.WHITE, "a hovered slip darkens")


## CSV guard follow-up: a misconfigured scale must not divide the tile step to
## 0 or negative and loop forever — it completes, which a hanging test would not.
func test_drawing_a_tiled_piece_with_a_non_positive_scale_completes() -> void:
	var s := ScaledNineSlice.new()
	s.texture = load("res://icon.png")
	s.source_inset = 0.0
	s.scale = -1.0
	var ci := RenderingServer.canvas_item_create()
	s.draw(ci, Rect2(0, 0, 50, 50))
	RenderingServer.free_rid(ci)
	assert_true(true, "drawing with scale <= 0 returned instead of looping forever")
