extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The board's art slots (spec 2026-09-28-courier-art §5): an installed piece
## is drawn from its texture, nine-sliced by its margin; an uninstalled or
## unloadable one keeps the flat fallback.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


## Scaled nine-slice: the art is installed at ui_missive_art_px_per_design
## texture px per design px (hi-res for the ~3x window scale), so the DRAWN
## corner is the margin divided by that scale, not the margin itself —
## StyleBoxTexture has no such scale (CLAUDE.md notes the same trap for the
## vellum plate), which is why a piece needs its own StyleBox.
func test_an_installed_piece_is_nine_sliced_by_its_margin() -> void:
	repo.missive_art["note"] = "res://icon.png"
	repo.missive_margin["note"] = 40
	var s := MissiveArt.style(repo, "note", StyleBoxFlat.new())
	assert_true(s is ScaledNineSlice)
	var n := s as ScaledNineSlice
	assert_eq(n.source_inset, 40.0, "the SOURCE inset is the margin, in texture px")
	assert_eq(n.scale, repo.bal("ui_missive_art_px_per_design"))
	assert_eq(n.draw_inset(), 40.0 / repo.bal("ui_missive_art_px_per_design"),
		"the DRAWN inset is the margin over the scale, in design px")


func test_a_piece_with_no_margin_tiles_instead_of_nine_slicing() -> void:
	repo.missive_art["board"] = "res://icon.png"
	repo.missive_margin["board"] = 0
	var s := MissiveArt.style(repo, "board", StyleBoxFlat.new())
	assert_true(s is ScaledNineSlice)
	var n := s as ScaledNineSlice
	assert_eq(n.source_inset, 0.0)
	assert_eq(n.draw_inset(), 0.0, "no corners: the whole box tiles")


## Board art follow-up: MissiveArt.style was copying the FALLBACK's content
## margins onto an installed piece regardless of the piece's own texture
## margin, so the frame's 72px of wood drew over only 16px of content inset
## and the first note sat on the wood. A piece names its own content inset
## in missive_content; when set it wins over the fallback's.
func test_an_installed_piece_with_content_set_uses_it_over_the_fallback() -> void:
	repo.missive_art["frame"] = "res://icon.png"
	repo.missive_margin["frame"] = 72
	repo.missive_content["frame"] = 76
	var fallback := StyleBoxFlat.new()
	fallback.content_margin_left = 16
	fallback.content_margin_top = 16
	var s := MissiveArt.style(repo, "frame", fallback) as ScaledNineSlice
	assert_not_null(s)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(s.get_content_margin(side), 76.0, "side %d" % side)


func test_an_installed_piece_with_no_content_keeps_the_fallbacks_margin() -> void:
	repo.missive_art["board"] = "res://icon.png"
	repo.missive_margin["board"] = 0
	repo.missive_content["board"] = -1
	var fallback := StyleBoxFlat.new()
	fallback.content_margin_left = 8
	var s := MissiveArt.style(repo, "board", fallback) as ScaledNineSlice
	assert_not_null(s)
	assert_eq(s.get_content_margin(SIDE_LEFT), 8.0)


func test_an_uninstalled_or_broken_piece_keeps_the_fallback() -> void:
	var flat := StyleBoxFlat.new()
	repo.missive_art["frame"] = ""
	assert_same(MissiveArt.style(repo, "frame", flat), flat)
	repo.missive_art["frame"] = "res://no/such/art.png"
	assert_same(MissiveArt.style(repo, "frame", flat), flat)
	assert_null(MissiveArt.texture(repo, "frame"))


func test_every_board_piece_named_exists() -> void:
	for key: String in repo.missive_art:
		var p := String(repo.missive_art[key])
		assert_true(p == "" or ResourceLoader.exists(p) or FileAccess.file_exists(p), "%s: %s" % [key, p])
	for key in ["frame", "board", "note", "letter", "envelope", "pin", "plaque"]:
		assert_true(repo.missive_art.has(key), key)
		assert_true(repo.missive_margin.has(key), key)
		assert_true(repo.missive_content.has(key), key)


## CSV guard follow-up: a misconfigured scale (never a real
## ui_missive_art_px_per_design) must not divide the tile step to 0 or
## negative and loop forever — it completes, which a hanging test would not.
func test_drawing_a_tiled_piece_with_a_non_positive_scale_completes() -> void:
	var s := ScaledNineSlice.new()
	s.texture = load("res://icon.png")
	s.source_inset = 0.0
	s.scale = -1.0
	var ci := RenderingServer.canvas_item_create()
	s.draw(ci, Rect2(0, 0, 50, 50))
	RenderingServer.free_rid(ci)
	assert_true(true, "drawing with scale <= 0 returned instead of looping forever")
