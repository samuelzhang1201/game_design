extends GutTest


func test_marks_keep_clear_of_each_other_and_inside_the_view() -> void:
	var marks := [{"at": Vector2(10, 10), "kind": "rain"}, {"at": Vector2(15, 10), "kind": "snow"},
		{"at": Vector2(60, 10), "kind": "mud"}, {"at": Vector2(-5, 10), "kind": "rain"}]
	var kept := Map3DHudWeather.thin(marks, 20.0, Rect2(0, 0, 100, 100))
	assert_eq(kept.size(), 2)
	assert_eq(String(kept[0]["kind"]), "rain", "the first in province order keeps its place")
	assert_eq(String(kept[1]["kind"]), "mud")
