extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## WarIndexChart.wall_image (spec 2026-10-13-war-room-sunlit-chamber, north-wall review
## 2026-10-14): the pack's continent on parchment for the north wall, its aspect the
## quad's, its rim burnt darker than its middle.


func test_the_picture_takes_the_quads_aspect() -> void:
	var img := WarIndexChart.wall_image(SuiteData.repo(), 256, 2.5)
	assert_eq(img.get_width(), 256)
	assert_eq(img.get_height(), 102, "256 / 2.5, rounded")


func test_the_rim_is_darker_than_the_middle() -> void:
	var img := WarIndexChart.wall_image(SuiteData.repo(), 256, 2.5)
	var mid := img.get_pixel(128, 51).get_luminance()
	for p: Vector2i in [Vector2i(0, 0), Vector2i(128, 0), Vector2i(255, 101), Vector2i(0, 51)]:
		assert_lt(img.get_pixel(p.x, p.y).get_luminance(), mid, "the rim at %s" % p)


func test_the_rim_fades_out_within_its_reach() -> void:
	var repo := SuiteData.repo()
	var reach := int(repo.bal("war_wall_map_rim_px"))
	var img := WarIndexChart.wall_image(repo, 256, 2.5)
	var inside := img.get_pixel(128, reach + 12).get_luminance()
	var rim := img.get_pixel(128, 0).get_luminance()
	assert_gt(inside, rim, "a pixel past the rim's reach is lighter than the edge")
