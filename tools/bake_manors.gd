extends SceneTree
## Bake a pack's manor table and cell index for a map imported before the
## manor system (2026-09-13) — the same two files tools/import_azgaar.gd
## writes on import, from the same export, so the names come out the same:
##   data/maps/<id>/political/manors.csv   one named manor per land cell
##   assets/maps/<id>/world_cell_index.png  R | G<<8 = cell id, white = water
## Needs the export JSON in assets/maps/<id>/ for the name banks and the
## cell cultures; everything else comes from the pack.
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##     -s tools/bake_manors.gd -- --map beria
## A tool, not simulation: it reads the clock to report its run time.

func _init() -> void:
	var map := "beria"
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map = args[i + 1]
	var t0 := Time.get_ticks_msec()
	var repo := DataRepository.load_all("res://data")
	if repo == null or repo.map_id != map:
		if repo == null or not repo.load_map(map):
			push_error("bake_manors: cannot load pack %s: %s" % [map, DataRepository.last_error])
			quit(1)
			return
	var art_dir := "res://assets/maps/%s" % map
	var json_path := _export_json(art_dir)
	if json_path == "":
		push_error("bake_manors: no *Full*.json in " + art_dir)
		quit(1)
		return
	var world := AzgaarJson.load_export(json_path)
	if world.is_empty():
		quit(1)
		return
	var pack: Dictionary = world["pack"]
	var info: Dictionary = world.get("info", {})
	var map_seed := int(String(info.get("seed", "0")))
	# Name banks and each culture's bank, from the export.
	var banks: Dictionary = {}
	for nb in (world.get("nameBases", []) as Array):
		if nb is Dictionary:
			banks[int((nb as Dictionary).get("i", 0))] = {
				"names": String((nb as Dictionary).get("b", "")).split(",", false),
				"min": int((nb as Dictionary).get("min", 5)), "max": int((nb as Dictionary).get("max", 12))}
	var culture_bank: Dictionary = {}
	for cu in (pack.get("cultures", []) as Array):
		if cu is Dictionary:
			culture_bank[int((cu as Dictionary).get("i", 0))] = int((cu as Dictionary).get("base", 0))
	var culture_code: Dictionary = {}
	for code: String in repo.world_table("society", "cultures"):
		var row: Dictionary = repo.world_table("society", "cultures")[code]
		culture_code[int(row.get("culture_id", -1))] = code
	var json_cells: Array = pack["cells"]
	# Burg in each cell, and the province under each cell's centre.
	var burg_in: Dictionary = {}
	for burg_code: String in MapEconomy.burg_cells(repo):
		burg_in[int(MapEconomy.burg_cells(repo)[burg_code])] = burg_code
	var province_img: Image = (load(repo.province_texture_path) as Texture2D).get_image()
	var specs: Array = []
	var polys: Array = []
	var ids := PackedInt32Array()
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell):
			continue
		var jc: Dictionary = json_cells[id] if id < json_cells.size() and json_cells[id] is Dictionary else {}
		var culture := int(jc.get("culture", 0))
		var centre := MapTerrain.cell_center(repo, cell)
		var prov := repo.province_by_id(MapIndex.id_at(province_img, Vector2i(centre.floor())))
		var burg := String(burg_in.get(id, ""))
		specs.append({"cell_id": id, "bank": int(culture_bank.get(culture, 0)),
			"burg_label": String(repo.burgs.get(burg, {}).get("label", "")) if burg != "" else "",
			"province_code": String(prov.get("province_code", "")), "burg_code": burg,
			"culture_code": String(culture_code.get(culture, ""))})
		polys.append(MapEconomy.cell_polygon(repo, cell))
		ids.append(id)
	var rows := ManorNames.forge_table(map_seed, specs, banks)
	var out := "cell_id,manor_code,label,province_code,burg_code,culture_code\n"
	for row: Dictionary in rows:
		out += "%d,%s,%s,%s,%s,%s\n" % [int(row["cell_id"]), row["manor_code"], _csv(String(row["label"])),
			row["province_code"], row["burg_code"], row["culture_code"]]
	var csv_path := ProjectSettings.globalize_path("res://data/maps/%s/political/manors.csv" % map)
	var f := FileAccess.open(csv_path, FileAccess.WRITE)
	if f == null:
		push_error("bake_manors: cannot write " + csv_path)
		quit(1)
		return
	f.store_string(out)
	f.close()
	var w := int(repo.map_info.get("width", "0"))
	var h := int(repo.map_info.get("height", "0"))
	var img := MapIndex.rasterize(polys, ids, w, h)
	var png := ProjectSettings.globalize_path(art_dir + "/world_cell_index.png")
	var err := img.save_png(png)
	print("bake_manors: %s — %d manors named (%d after burgs), cell index %dx%d in %d ms (%s)" % [
		map, rows.size(), burg_in.size(), w, h, Time.get_ticks_msec() - t0,
		"ok" if err == OK else "png FAILED %d" % err])
	quit(0 if err == OK else 1)

static func _csv(s: String) -> String:
	if s.contains(",") or s.contains("\""):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s

static func _export_json(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for name in d.get_files():
		if name.ends_with(".json") and name.contains("Full"):
			return dir + "/" + name
	return ""
