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
func test_the_view_is_a_coordinator() -> void:
	assert_lte(_lines("res://scripts/map3d/map3d_view.gd"), 568)


func test_every_other_script_is_small() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if not f.ends_with(".gd") or f == "map3d_view.gd" or f in OLD_HELPERS:
			continue
		assert_lte(_lines("res://scripts/map3d/" + f), 300, f)
