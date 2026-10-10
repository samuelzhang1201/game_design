extends GutTest
## The shape the owner asked for (spec 2026-09-20 §1): no script of the 3D
## map over ~250 lines apart from the pure helpers that were already there,
## and the view a coordinator.

const OLD_HELPERS := ["map3d_rivers.gd", "map3d_bridges.gd", "map3d_borders.gd"]


func _lines(path: String) -> int:
	return FileAccess.get_file_as_string(path).split("\n").size()


## 536, not the 498 of Task 7, which was not the 495 of Task 22: each rise is
## one more LAYER or one more INTERACTION hung on the coordinator, and nothing
## else. Task 7 put the houses layer's @onready field, its bind()/build() at
## load (Map3DHouses.load_csv costs ~91 ms — warmed here, not on the first
## refresh() mid-play) and a house_counts() getter on the root.
##
## MILITARY's 3D pieces and their orders (owner 2026-09-22) put here: the
## units layer's @onready field, its bind() and first set_shown() at load, its
## per-frame turn in _process, a set_shown() in set_military and three
## one-line getters the HUD and the picker read it through; then two signals
## (army_menu_requested, ground_clicked), the `aiming` flag that makes a left
## click say WHERE it landed instead of picking, right_click(), and one more
## parameter on attach() that hands the view to ArmyOrderMenu. Every one of
## those is a forwarder or a signal — the orders themselves are ArmyOrderMenu's,
## because nothing under scripts/map3d may reach the Game autoload.
##
## In both cases the camera_moved refresh is NOT here: the layer self-connects
## inside its own bind(), the same idiom Map3DHud.bind() uses, so the
## coordinator never dispatches it. The view still only forwards — every new
## line here must be a forwarder or a guard, and a change that is neither
## belongs in the layer.
##
## 556 since the regiment pieces' second round (owner 2026-09-27), again only
## forwarders, guards and signals: DEV MODE's set_dev_mode / dev_mode (the
## pause menu's switch, handed to the context and the units layer); the march's
## COMMIT / CANCEL and route menu — a route_clicked signal, aim_dest, the
## aim_code setter's HUD refresh and a route_ends() forwarder; and the sun's
## round, one line in _process reading Game.day_progress (the view is the one
## script under scripts/map3d allowed the autoload). The rule is the layer's
## (Map3DEnvironment.sun_angles), the menus are ArmyOrderMenu's.
##
## 560 since the couriers (2026-09-27): the Couriers layer's @onready, its
## bind, its step in _process and a courier_rects() forwarder — the layer
## does the work. (_lines() counts split("\n").size(), one more than the
## file's own newlines, so four added lines raise it by four, not three.)
## 561 since the dusk (2026-09-28): the FillLight's @onready, handed to
## Map3DEnvironment.sweep_sun, which does the work.
## 562 since the courier rides the day as it runs (owner 2026-09-28): one line
## handing Game.day_progress to the context (day_fn); the layer does the work.
##
## 568 since the spy's right-click on the ground (2026-09-28): a signal and its
## emit — SpyOrderMenu does the work.
## 574 since the weather's look (2026-09-29): the layer's var, its bind, its
## step in _process, its apply_quality and set_weather_override with its note —
## Map3DLayerWeather (and the Precip layer it steps) does the work.
## 577 since the woods and the wind (2026-09-30): the trees layer's var, its one
## build line — Map3DLayerTrees does the work.
## 578 since the march's road is draped from where its piece is DRAWN
## (2026-09-30): one line handing the HUD the pieces' positions.
## 581 since the march trails (2026-10-01; the march dust since 2026-10-07):
## the layer's var, its bind and its step in _process — Map3DLayerDust does the work.
## 582 since the view put away stops its subtree's processing (perf
## 2026-10-02): one line each in activate and deactivate.
## 603 since the load runs a step at a time (owner 2026-10-10: the title's map
## opens a frame a step, no long stall): load_step's match and the three
## step functions' heads — the layers still do the work.
func test_the_view_is_a_coordinator() -> void:
	assert_lte(_lines("res://scripts/map3d/map3d_view.gd"), 603)


func test_every_other_script_is_small() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if not f.ends_with(".gd") or f == "map3d_view.gd" or f in OLD_HELPERS:
			continue
		assert_lte(_lines("res://scripts/map3d/" + f), 300, f)
