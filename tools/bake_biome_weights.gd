extends SceneTree
## Bake world_biome_weights_N.png for a map pack from its biome index
## (BIOMES LAYER experiment 2026-09-14): per biome 1..12, its share of the
## LAND within balance.csv map_biome_blur_px of every point, at 1/scale of
## the index's resolution, four biomes per RGBA image
## (MapIndex.bake_biome_weights). biome_tiles.gdshader mixes the ground
## tiles by these, so one biome fades into the next with no cell edge.
## Re-run after changing map_biome_blur_px or re-importing the pack.
## No autoloads needed:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##     -s tools/bake_biome_weights.gd -- --map beria [--scale 4]
## A tool, not simulation: it reads the clock to report its own run time.

const BIOMES := 16  # 13..15 are the high ground (MapIndex.raise_high_ground)

func _init() -> void:
	var map := "beria"
	var scale := 4
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map = args[i + 1]
		elif args[i] == "--scale":
			scale = maxi(int(args[i + 1]), 1)
	var blur := 40.0
	for row: Dictionary in DataRepository.parse_csv("res://data/balance.csv", ["key", "value"]):
		if String(row["key"]) == "map_biome_blur_px":
			blur = float(row["value"])
	var dir := "res://assets/maps/%s" % map
	var src := ProjectSettings.globalize_path(dir + "/world_biome_index.png")
	var img := Image.load_from_file(src)
	if img == null:
		push_error("bake_biome_weights: cannot read " + src)
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var radius := maxi(int(round(blur / float(scale))), 0)
	var baked := MapIndex.bake_biome_weights(img, scale, radius, BIOMES)
	var ok := true
	for i in baked.size():
		var out := ProjectSettings.globalize_path(dir + "/world_biome_weights_%d.png" % i)
		var err := (baked[i] as Image).save_png(out)
		print("bake_biome_weights: %s -> %s (%s)" % [map, out, "ok" if err == OK else "FAILED %d" % err])
		ok = ok and err == OK
	print("bake_biome_weights: %s %dx%d at 1/%d, blur %d px (radius %d), %d images in %d ms" % [
		map, baked[0].get_width(), baked[0].get_height(), scale, int(blur), radius,
		baked.size(), Time.get_ticks_msec() - t0])
	quit(0 if ok else 1)
