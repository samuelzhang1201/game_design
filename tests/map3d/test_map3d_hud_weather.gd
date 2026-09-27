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


const HUD_FIXTURE := "user://test_map3d_hud_weather_world.tscn"
const HUD_WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func _hud_view() -> Map3DView:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.set_meta("map3d_world", HUD_WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, HUD_FIXTURE)
	root.free()
	var v := Map3DView.create(Game.data, HUD_FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


## The gathering itself, through the real HUD (review 2026-09-28): what the
## marks keep off is every piece's own output — the kingdom names' boxes, the
## counters with their bars, the couriers' pending envelopes — not a
## hand-built list.
func test_the_marks_keep_off_every_pieces_output() -> void:
	var v := _hud_view()
	var hud := v.get_node("Hud") as Map3DHud
	var repo := Game.data
	var reg: Dictionary = {}
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			reg = r
			break
	var at := ArmySystem.position_of(repo, Game.state, reg)
	var dest := ArmySystem.pack_to_metres(repo, at + Vector2(3.0, 3.0))
	CourierSystem.dispatch(repo, Game.state, CourierSystem.ORDINARY, String(reg["regiment_code"]),
		{"action_code": "ARMY_MARCH", "dest_x_m": dest.x, "dest_y_m": dest.y})
	v.look_at_pack(at, 30000.0)
	var weather := hud.piece("Weather") as Map3DHudWeather
	var taken := weather.taken()
	var envelopes := (hud.piece("Couriers") as Map3DHudCouriers).pending_rects()
	var names := (hud.piece("Labels") as Map3DHudLabels).rects()
	var counters := (hud.piece("Armies") as Map3DHudArmies).markers()
	assert_eq(envelopes.size(), 1, "the pending order's envelope is on screen")
	assert_gt(names.size(), 0, "some kingdom is lettered")
	assert_gt(counters.size(), 0, "some counter stands")
	for r: Rect2 in envelopes + names:
		assert_true(taken.has(r), "kept off %s" % r)
	for m: Dictionary in counters:
		assert_true(taken.has(m["rect"]), "kept off the counter and its bars of " + String(m["code"]))


## Final review M5: the marks are cut once per day on the ground and once per
## camera pose on the screen, not recomputed for every province each redraw.
func test_the_marks_are_cut_once_per_day_and_per_pose() -> void:
	var v := _hud_view()
	var repo := Game.data
	var saved := repo.weather_odds.duplicate(true)
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 0, "rain": 1, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()
	var weather := (v.get_node("Hud") as Map3DHud).piece("Weather") as Map3DHudWeather
	var day := weather.day_marks()
	assert_eq(day.size(), repo.provinces.size(), "rain everywhere: a mark per province")
	assert_true(is_same(weather.day_marks(), day), "the same day: not cut again")
	var shown := weather.screen_marks()
	assert_true(is_same(weather.screen_marks(), shown), "the same pose: not projected again")
	var capital: Dictionary = repo.burgs[String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])]
	v.look_at_pack(Vector2(float(capital["x"]), float(capital["y"])), 20000.0)
	assert_false(is_same(weather.screen_marks(), shown), "a new pose: projected anew")
	Game.state.day += 1
	assert_false(is_same(weather.day_marks(), day), "a new day: cut anew")
	repo.weather_odds = saved
	Weather.forget()


func after_all() -> void:
	Map3DWorldCache.clear()
