extends GutTest
## The shape the owner asked for (spec 2026-09-20 §1): no script of the 3D
## map over ~250 lines apart from the pure helpers that were already there,
## and the view a coordinator.

const OLD_HELPERS := ["map3d_rivers.gd", "map3d_bridges.gd", "map3d_borders.gd"]


func _lines(path: String) -> int:
	return FileAccess.get_file_as_string(path).split("\n").size()


func test_the_view_is_a_coordinator() -> void:
	assert_lte(_lines("res://scripts/map3d/map3d_view.gd"), 450)


func test_every_other_script_is_small() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if not f.ends_with(".gd") or f == "map3d_view.gd" or f in OLD_HELPERS:
			continue
		assert_lte(_lines("res://scripts/map3d/" + f), 300, f)
