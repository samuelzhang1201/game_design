extends SceneTree
## Bake the SETTLEMENT EARTH HALO field into a map pack (owner 2026-09-17:
## "定居点周边的地图渐变为土色，然后定居点从这个土色中无缝建立起来").
##
## A town on a real map does not sit on untouched forest: it sits in a ring of
## trodden earth, yards, tracks and worked ground that fades outward into the
## countryside. Drawing the settlement art straight onto green ground is what
## made it read as a sticker. This bakes the field the ground shader needs to
## make that ring itself:
##
##   world_settlement_distance.png   every pixel its distance IN KM to the
##                                   nearest settlement's worked ground, L8,
##                                   capped at 255 — 0 inside a town's own
##                                   radius, rising outward
##
## The radius of each town's worked ground grows with its population, the same
## square-root scaling `tools/bake_relief.gd` uses for a river's discharge, so
## a hamlet clears a field or two and a city of fifty thousand clears ten
## kilometres. Reuses MapIndex.stamp_polylines (single-point branch) and
## MapIndex.distance_to_land — the same two primitives the relief bake uses to
## keep invented ridges out of real river valleys.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##     -s tools/bake_settlements.gd -- [--map ID]  (default: data/maps.csv is_default)
##
## The radii come from balance.csv (map_town_halo_*), so re-run after changing
## them or re-importing the pack. A tool, not simulation: it reads the clock to
## report its own run time.


func _init() -> void:
	var map := DataRepository.default_pack_id()
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map = args[i + 1]
	var bal := _balance()
	# The radius a town of MEDIAN population clears, in native px (= km).
	var base: float = bal.get("map_town_halo_base_px", 3.0)
	var cap: float = bal.get("map_town_halo_max_px", 12.0)

	var dir := "res://data/maps/%s" % map
	var info := _info(dir)
	var w := int(info.get("width", 0))
	var h := int(info.get("height", 0))
	if w <= 0 or h <= 0:
		push_error("bake_settlements: %s has no canvas size" % map)
		quit(1)
		return

	var rows := DataRepository.parse_csv(dir + "/political/burgs.csv",
		["burg_code", "label", "province_code", "kingdom_code", "population",
		"is_capital", "is_port", "x", "y"])
	if rows.is_empty():
		push_error("bake_settlements: no burgs for %s" % map)
		quit(1)
		return

	var began := Time.get_ticks_msec()

	# The median population is the anchor, so the scaling does not depend on
	# one outlier capital.
	var pops := PackedFloat32Array()
	for row: Dictionary in rows:
		pops.append(maxf(float(row.get("population", 0)), 1.0))
	var sorted_pops := Array(pops)
	sorted_pops.sort()
	@warning_ignore("integer_division")  # the middle row, whole index
	var median: float = maxf(float(sorted_pops[sorted_pops.size() / 2]), 1.0)

	var lines: Array = []
	var radii := PackedFloat32Array()
	for row: Dictionary in rows:
		var at := Vector2(float(row.get("x", 0)), float(row.get("y", 0)))
		if at.x <= 0.0 and at.y <= 0.0:
			continue
		var pop := maxf(float(row.get("population", 0)), 1.0)
		# A single-point "line": stamp_polylines fills a disc for it.
		lines.append(PackedVector2Array([at]))
		radii.append(minf(base * sqrt(pop / median), cap))

	var mask := MapIndex.stamp_polylines(w, h, lines, radii)
	var dist := MapIndex.distance_to_land(mask, w, h)
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	for i in w * h:
		bytes[i] = mini(int(dist[i] + 0.5), 255)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_L8, bytes)

	var out := ProjectSettings.globalize_path("res://assets/maps/%s/world_settlement_distance.png" % map)
	var err := img.save_png(out)
	var inside := 0
	for i in w * h:
		if bytes[i] == 0:
			inside += 1
	print("bake_settlements: %s -> %s (%s)" % [map, out, "ok" if err == OK else "FAILED"])
	print("bake_settlements: %d burgs, median pop %.0f, radius %.1f..%.1f km, %d px of worked ground (%.2f%% of the canvas), %d ms" % [
		lines.size(), median, base * sqrt(maxf(float(sorted_pops[0]), 1.0) / median),
		minf(base * sqrt(float(sorted_pops[-1]) / median), cap),
		inside, 100.0 * float(inside) / float(w * h), Time.get_ticks_msec() - began])
	quit()


func _balance() -> Dictionary:
	var out: Dictionary = {}
	for row: Dictionary in DataRepository.parse_csv("res://data/balance.csv", ["key", "value"]):
		out[String(row["key"])] = float(row["value"])
	return out


func _info(dir: String) -> Dictionary:
	var out: Dictionary = {}
	for row: Dictionary in DataRepository.parse_csv(dir + "/map_info.csv", ["key", "value"]):
		out[String(row["key"])] = String(row["value"])
	return out
