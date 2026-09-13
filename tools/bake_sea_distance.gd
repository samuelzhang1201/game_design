extends SceneTree
## Bake world_sea_distance.png for a map pack from its biome index — the same
## file tools/import_azgaar.gd writes on import (2026-09-13), for a pack that
## was imported before the sea had a distance field. Every pixel becomes its
## distance to the nearest land pixel in native px, capped at 255
## (MapIndex.bake_sea_distance); SeaLayer's shader turns that into the four
## sea bands. No autoloads needed:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##     -s tools/bake_sea_distance.gd -- --map beria
## A tool, not simulation: it reads the clock to report its own run time.

func _init() -> void:
	var map := "beria"
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map = args[i + 1]
	var dir := "res://assets/maps/%s" % map
	var src := ProjectSettings.globalize_path(dir + "/world_biome_index.png")
	var img := Image.load_from_file(src)
	if img == null:
		push_error("bake_sea_distance: cannot read " + src)
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var baked := MapIndex.bake_sea_distance(img)
	var out := ProjectSettings.globalize_path(dir + "/world_sea_distance.png")
	var err := baked.save_png(out)
	print("bake_sea_distance: %s %dx%d in %d ms -> %s (%s)" % [
		map, baked.get_width(), baked.get_height(), Time.get_ticks_msec() - t0, out,
		"ok" if err == OK else "FAILED %d" % err])
	quit(0 if err == OK else 1)
