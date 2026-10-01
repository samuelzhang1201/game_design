extends GutTest
## The sheet's ink (spec 2026-10-01-war-room-design §2).

var repo: DataRepository
var state: GameState


func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	state = GameState.new_campaign(repo, 42)
	WarSheets.forget()


func test_dashes_alternate_on_and_off_along_the_line() -> void:
	var d := WarSheetInk.dashed(PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), 20.0, 10.0)
	assert_eq(d.size(), 4)  # 0-20, 30-50, 60-80, 90-100
	assert_almost_eq(d[1][0].x, 30.0, 0.001)
	assert_almost_eq(d[3][1].x, 100.0, 0.001)


func test_only_what_touches_the_sheet_is_inked_in_texture_px() -> void:
	var sheet: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = sheet["rect"]
	var ink := WarSheetInk.strokes(repo, state, sheet, 4096)
	var k := 4096.0 / r.size.x
	for t: Dictionary in ink["towns"]:
		var at: Vector2 = t["at"]
		assert_true(at.x >= 0.0 and at.x <= 4096.0 and at.y >= 0.0 and at.y <= r.size.y * k, String(t["label"]))
	var inside := 0
	for b: Dictionary in repo.burgs.values():
		if r.has_point(Vector2(float(b["x"]), float(b["y"]))):
			inside += 1
	assert_eq(ink["towns"].size(), inside)
	for key in ["roads", "trails", "rivers", "coasts", "seams", "peaks", "borders"]:
		assert_true(ink.has(key), key)


func test_a_conquest_changes_the_cache_key() -> void:
	var before := WarSheetInk.cache_key(state, 0)
	var prov: String = repo.provinces.keys()[0]
	state.province_owner[prov] = "someone_else"
	assert_ne(WarSheetInk.cache_key(state, 0), before)
	state.province_owner.erase(prov)
	assert_eq(WarSheetInk.cache_key(state, 0), before)
