extends GutTest


func test_marks_keep_clear_of_each_other_and_inside_the_view() -> void:
	var marks := [{"at": Vector2(10, 10), "kind": "rain"}, {"at": Vector2(15, 10), "kind": "snow"},
		{"at": Vector2(60, 10), "kind": "mud"}, {"at": Vector2(-5, 10), "kind": "rain"}]
	var kept := Map3DHudWeather.thin(marks, 20.0, Rect2(0, 0, 100, 100))
	assert_eq(kept.size(), 2)
	assert_eq(String(kept[0]["kind"]), "rain", "the first in province order keeps its place")
	assert_eq(String(kept[1]["kind"]), "mud")


## Spec §2: the marks keep off the settlement dots and the counters (found
## through the real game, 2026-09-28: a rain drop sat on a town and a counter).
func test_marks_keep_off_what_is_already_drawn() -> void:
	var marks := [{"at": Vector2(10, 10), "kind": "rain"}, {"at": Vector2(60, 60), "kind": "snow"}]
	var taken := [Rect2(0, 0, 12, 12)]
	var kept := Map3DHudWeather.thin(marks, 20.0, Rect2(0, 0, 100, 100), taken, 10.0)
	assert_eq(kept.size(), 1)
	assert_eq(String(kept[0]["kind"]), "snow", "the mark over a dot is left off")
