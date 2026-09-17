extends SceneTree
## Bake the high ground into a map pack (owner 2026-09-17, choice B: the
## satellite ground needs mountains, and height is not a biome).
##
## Two products, from the pack's own cells and its cell-index bitmap:
##   world_relief.png            every pixel its cell's height, smoothed
##                               (MapIndex.bake_relief) — biome_tiles.gdshader
##                               lights the ground by this field's SLOPE
##   world_biome_weights_N.png   re-baked over an index whose high land has
##                               been rewritten to 13 hill / 14 mountain /
##                               15 peak (MapIndex.raise_high_ground), so the
##                               high ground cross-fades in like any biome
##
## The bands and the smoothing come from balance.csv (map_biome_hill_height,
## map_biome_mountain_height, map_biome_peak_height, map_biome_blur_px), so
## re-run this after changing any of them or re-importing the pack.
## No autoloads needed:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##     -s tools/bake_relief.gd -- --map beria
## The resolutions are data: map_relief_scale for the height field and
## map_biome_weights_scale for the weight maps, each with its own blur.
## A tool, not simulation: it reads the clock to report its own run time.

const BIOMES := 16


func _init() -> void:
	var map := "beria"
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map = args[i + 1]
	var bal := _balance()
	var hill := int(bal.get("map_biome_hill_height", 45.0))
	var mountain := int(bal.get("map_biome_mountain_height", 62.0))
	var peak := int(bal.get("map_biome_peak_height", 80.0))
	var blur: float = bal.get("map_biome_blur_px", 10.0)

	var dir := "res://assets/maps/%s" % map
	var cells_img := _load(dir + "/world_cell_index.png")
	var biome_img := _load(dir + "/world_biome_index.png")
	if cells_img == null or biome_img == null:
		quit(1)
		return
	var heights := _heights(map)
	if heights.is_empty():
		push_error("bake_relief: no cells for %s" % map)
		quit(1)
		return

	var began := Time.get_ticks_msec()

	# The SLOPE needs a sharp field: the tile weights want a wide blur, the
	# relief wants the landforms. relief_scale / relief_blur are its own.
	var r_scale := maxi(int(bal.get("map_relief_scale", 1.0)), 1)
	var r_radius := maxi(int(bal.get("map_relief_blur_px", 0.0)) / r_scale, 0)
	var lw := ceili(float(cells_img.get_width()) / float(r_scale))
	var lh := ceili(float(cells_img.get_height()) / float(r_scale))

	# Rivers and the coast hold the invented ridges down: stamp both into one
	# mask, then reuse the chamfer transform to measure distance from it.
	var river_px: float = bal.get("map_relief_detail_river_px", 0.0)
	var coast_px: float = bal.get("map_relief_detail_coast_px", 0.0)
	var courses := _courses(map, r_scale, river_px, coast_px)
	var mask := MapIndex.stamp_polylines(lw, lh, courses["lines"], courses["radii"])
	var dist := MapIndex.distance_to_land(mask, lw, lh)
	var reach := maxf(maxf(river_px, coast_px) / float(r_scale), 1.0)
	var suppression := PackedFloat32Array()
	suppression.resize(lw * lh)
	for i in lw * lh:
		suppression[i] = smoothstep(0.0, reach, dist[i])

	var detail := MapIndex.detail_field(lw, lh,
		int(bal.get("map_relief_detail_seed", 0.0)),
		bal.get("map_relief_detail_freq_px", 180.0) / float(r_scale),
		int(bal.get("map_relief_detail_octaves", 4.0)),
		bal.get("map_relief_detail_warp_px", 0.0) / float(r_scale))

	var relief := MapIndex.bake_relief(cells_img, heights, r_scale, r_radius,
		detail, suppression,
		bal.get("map_relief_detail_gain", 0.0),
		bal.get("map_relief_detail_floor", 0.0))
	var relief_path := ProjectSettings.globalize_path(dir + "/world_relief.png")
	print("bake_relief: %s -> %s (%s)" % [map, relief_path, "ok" if relief.save_png(relief_path) == OK else "FAILED"])

	var raised := MapIndex.raise_high_ground(biome_img, cells_img, heights,
		hill, mountain, peak, relief)
	# The weights get their own scale too (owner 2026-09-17: a blocky edge at
	# the closest zoom). At 1/4 one weight pixel covers ~29 screen px there,
	# so the blend between two biomes shows as a straight step.
	var w_scale := maxi(int(bal.get("map_biome_weights_scale", 4.0)), 1)
	var w_radius := maxi(int(round(blur / float(w_scale))), 0)
	var images := MapIndex.bake_biome_weights(raised, w_scale, w_radius, BIOMES)
	for i in images.size():
		var path := ProjectSettings.globalize_path(dir + "/world_biome_weights_%d.png" % i)
		print("bake_relief: %s -> %s (%s)" % [map, path, "ok" if images[i].save_png(path) == OK else "FAILED"])

	var high := _count_high(raised)
	print("bake_relief: %s relief %dx%d at 1/%d (radius %d), weights at 1/%d (radius %d), bands %d/%d/%d, blur %.0f px, %d images in %d ms" % [
		map, relief.get_width(), relief.get_height(), r_scale, r_radius, w_scale, w_radius,
		hill, mountain, peak, blur, images.size(), Time.get_ticks_msec() - began])
	print("bake_relief: high ground — %d hill, %d mountain, %d peak px" % [high[0], high[1], high[2]])
	quit()


func _balance() -> Dictionary:
	var out: Dictionary = {}
	for row: Dictionary in DataRepository.parse_csv("res://data/balance.csv", ["key", "value"]):
		out[String(row["key"])] = float(row["value"])
	return out


## The pack's cell heights, indexed by cell id.
func _heights(map: String) -> PackedInt32Array:
	var rows := DataRepository.parse_csv("res://data/maps/%s/geography/cells.csv" % map,
		["cell_id", "vertex_ids", "height", "biome_id", "water", "neighbor_ids"])
	var out := PackedInt32Array()
	for row: Dictionary in rows:
		var id := int(row.get("cell_id", -1))
		if id < 0:
			continue
		if id >= out.size():
			out.resize(id + 1)
		out[id] = int(row.get("height", 0))
	return out


## The pack's river courses and land shores in native px, with the stamp
## radius each should wear. A river's radius grows with its discharge so a
## great river holds a wider valley clear than a brook does.
func _courses(map: String, scale: int, river_px: float, coast_px: float) -> Dictionary:
	var lines: Array = []
	var radii := PackedFloat32Array()
	var rivers := DataRepository.parse_csv("res://data/maps/%s/geography/rivers.csv" % map,
		["river_code", "label", "type", "length", "discharge", "kingdom_codes", "points"])
	var most := 1.0
	for row: Dictionary in rivers:
		most = maxf(most, float(row.get("discharge", 0)))
	for row: Dictionary in rivers:
		var pts := MapGeometry.parse_points(String(row.get("points", "")))
		if pts.size() < 2:
			continue
		lines.append(_scaled(pts, scale))
		var share := sqrt(float(row.get("discharge", 0)) / most)
		radii.append(maxf(river_px * share, 1.0) / float(scale))
	var coasts := DataRepository.parse_csv("res://data/maps/%s/geography/coasts.csv" % map,
		["kind", "feature_id", "loop", "points"])
	for row: Dictionary in coasts:
		if String(row.get("kind", "")) != "land":
			continue
		var pts := MapGeometry.parse_points(String(row.get("points", "")))
		if pts.size() < 2:
			continue
		lines.append(_scaled(pts, scale))
		radii.append(maxf(coast_px, 1.0) / float(scale))
	return {"lines": lines, "radii": radii}

func _scaled(pts: PackedVector2Array, scale: int) -> PackedVector2Array:
	if scale <= 1:
		return pts
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] / float(scale)
	return out


func _load(path: String) -> Image:
	var file := ProjectSettings.globalize_path(path)
	var img := Image.load_from_file(file)
	if img == null:
		push_error("bake_relief: cannot read %s" % file)
	return img


func _count_high(raised: Image) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0])
	for y in raised.get_height():
		for x in raised.get_width():
			var id := MapIndex.biome_at(raised, Vector2i(x, y))
			if id >= 13 and id <= 15:
				out[id - 13] += 1
	return out
