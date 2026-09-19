extends SceneTree
## Export each manor's chief good for the 3D bake (owner 2026-09-19: fields
## round the villages, sown by what the manor works). The game decides a
## manor's default focus in GDScript (MapManors.default_focus — coast, peak,
## high ground, biome, in manor_focus.csv's own order); bake_world.py reads
## this file instead of re-deriving it, so the two can never disagree. The
## campaign's STARTING focus: a focus the player changes later does not
## re-sow the baked ground.
##
##   GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . \
##     -s tools/map3d/export_manor_land.gd [-- --map ID]
##
## writes <map3d_dir>/bake/manor_land.csv (maps.csv map3d_dir, default
## assets/map3d/<map>): cell_id,focus


func _init() -> void:
	var repo := DataRepository.load_all("res://data")
	if repo == null:
		push_error("export_manor_land: data failed to load: " + DataRepository.last_error)
		quit(1)
		return
	var map := DataRepository.default_pack_id()
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map = args[i + 1]
	if map != repo.map_id and not repo.load_map(map):
		push_error("export_manor_land: no pack " + map)
		quit(1)
		return
	var dir := ProjectSettings.globalize_path(DataRepository.map3d_dir_of(map).path_join("bake"))
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/manor_land.csv", FileAccess.WRITE)
	f.store_line("cell_id,focus")
	var ids: Array = repo.manors.keys()
	ids.sort()
	for id: int in ids:
		f.store_line("%d,%s" % [id, MapManors.default_focus(repo, id)])
	f.close()
	print("export_manor_land: %d manors -> %s/manor_land.csv" % [ids.size(), dir])
	quit(0)
