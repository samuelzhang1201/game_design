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
func test_the_view_is_a_coordinator() -> void:
	assert_lte(_lines("res://scripts/map3d/map3d_view.gd"), 536)


func test_every_other_script_is_small() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if not f.ends_with(".gd") or f == "map3d_view.gd" or f in OLD_HELPERS:
			continue
		assert_lte(_lines("res://scripts/map3d/" + f), 300, f)
