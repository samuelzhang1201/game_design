extends GutTest
## The sheet index on the war room's wall: the chart's image and its pick (spec §2).

var repo: DataRepository


func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	WarSheets.forget()


func test_the_chart_keeps_the_maps_ratio() -> void:
	var img := WarIndexChart.image(repo, 512)
	assert_eq(img.get_width(), 512)
	assert_eq(img.get_height(), int(round(512.0 * 929.0 / 2560.0)))


func test_a_uv_on_a_sheet_picks_it() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var c: Vector2 = (s["rect"] as Rect2).get_center()
	var uv := c / Vector2(2560.0, 929.0)
	assert_eq(WarIndexChart.sheet_at_uv(repo, uv), WarSheets.sheet_of(repo, c))
	assert_eq(WarIndexChart.sheet_at_uv(repo, Vector2(-0.1, 0.5)), -1)
