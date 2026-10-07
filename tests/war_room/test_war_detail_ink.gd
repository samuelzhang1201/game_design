extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The near-zoom detail patch (spec 2026-10-07-war-room-scale-hover §2).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_levels_by_distance() -> void:
	var t := repo.bal("war_detail_level_m")
	assert_eq(WarDetailInk.level(repo, t * 1.01), 0)
	assert_eq(WarDetailInk.level(repo, t * 0.99), 1)
	assert_eq(WarDetailInk.level(repo, t * 0.49), 2)
	assert_eq(WarDetailInk.level(repo, t * 0.24), 3)
	assert_eq(WarDetailInk.level(repo, 0.001), 3)


func test_the_patch_covers_the_view_and_snaps() -> void:
	var sheet := Rect2(0, 0, 71, 52)
	var view := Vector2(10, 6)
	var a := WarDetailInk.patch_rect(repo, sheet, Vector2(30, 20), view)
	assert_true(a.has_point(Vector2(30, 20)))
	assert_gte(a.size.x, view.x * repo.bal("war_detail_cover") - 0.001)
	var b := WarDetailInk.patch_rect(repo, sheet, Vector2(30.2, 20.1), view)
	assert_eq(a, b, "a small pan keeps the same patch")


func test_a_redraw_only_when_level_rect_or_key_changes() -> void:
	var s := {"level": 1, "rect": Rect2(0, 0, 10, 10), "key": 5}
	assert_false(WarDetailInk.needs_redraw(s, s.duplicate()))
	var t := s.duplicate()
	t["level"] = 2
	assert_true(WarDetailInk.needs_redraw(s, t))
	t = s.duplicate()
	t["key"] = 6
	assert_true(WarDetailInk.needs_redraw(s, t))
