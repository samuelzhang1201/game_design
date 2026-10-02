extends GutTest
## UiPalette.load_art keeps what it loaded only up to ui_art_cache_mb (perf
## 2026-10-02): every portrait, painting and icon a session drew stayed in
## video memory. The least recently asked go first.

var _saved: float


func before_each() -> void:
	_saved = float(Game.data.balance.get("ui_art_cache_mb", 160.0))


func after_each() -> void:
	Game.data.balance["ui_art_cache_mb"] = _saved


func _portraits() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at("res://assets/2D/portraits/cast/full"):
		if f.ends_with(".png"):
			out.append("res://assets/2D/portraits/cast/full/" + f)
	out.sort()
	return out


func test_past_its_cap_the_oldest_art_goes_and_the_asked_stays() -> void:
	var paths := _portraits()
	assert_gt(paths.size(), 3, "the cast's full portraits are installed")
	var one := UiPalette.load_art(paths[0])
	assert_not_null(one)
	var bytes := one.get_width() * one.get_height() * 4
	# room for about two portraits
	Game.data.balance["ui_art_cache_mb"] = 2.5 * bytes / 1048576.0
	UiPalette.load_art(paths[1])
	UiPalette.load_art(paths[0])  # asked again: the most recent now
	UiPalette.load_art(paths[2])
	assert_true(UiPalette._art_cache.has(paths[0]), "the one asked again is kept")
	assert_true(UiPalette._art_cache.has(paths[2]), "and the newest")
	assert_false(UiPalette._art_cache.has(paths[1]), "the least recently asked is let go")
	assert_same(UiPalette.load_art(paths[0]), one, "a kept one is the same texture")
	assert_not_null(UiPalette.load_art(paths[1]), "a let-go one loads again")
