extends GutTest
## The board's art slots (spec 2026-09-28-courier-art §5): an installed piece
## is drawn from its texture, nine-sliced by its margin; an uninstalled or
## unloadable one keeps the flat fallback.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")


func test_an_installed_piece_is_nine_sliced_by_its_margin() -> void:
	repo.missive_art["note"] = "res://icon.png"
	repo.missive_margin["note"] = 40
	var s := MissiveArt.style(repo, "note", StyleBoxFlat.new())
	assert_true(s is StyleBoxTexture)
	assert_eq((s as StyleBoxTexture).texture_margin_left, 40.0)
	assert_eq((s as StyleBoxTexture).texture_margin_bottom, 40.0)


func test_a_piece_with_no_margin_still_draws_stretched() -> void:
	repo.missive_art["board"] = "res://icon.png"
	repo.missive_margin["board"] = 0
	var s := MissiveArt.style(repo, "board", StyleBoxFlat.new())
	assert_true(s is StyleBoxTexture)
	assert_eq((s as StyleBoxTexture).texture_margin_left, 0.0)


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
	var s := MissiveArt.style(repo, "frame", fallback) as StyleBoxTexture
	assert_not_null(s)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(s.get_content_margin(side), 76.0, "side %d" % side)


func test_an_installed_piece_with_no_content_keeps_the_fallbacks_margin() -> void:
	repo.missive_art["board"] = "res://icon.png"
	repo.missive_margin["board"] = 0
	repo.missive_content["board"] = -1
	var fallback := StyleBoxFlat.new()
	fallback.content_margin_left = 8
	var s := MissiveArt.style(repo, "board", fallback) as StyleBoxTexture
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


func test_the_board_wears_an_installed_frame() -> void:
	var saved := String(Game.data.missive_art.get("frame", ""))
	Game.data.missive_art["frame"] = "res://icon.png"
	Game.data.missive_margin["frame"] = 8
	var screen: MissiveScreen = (load("res://scenes/missive_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	assert_true(screen.get_node("%Frame").get_theme_stylebox("panel") is StyleBoxTexture)
	Game.data.missive_art["frame"] = saved
