extends SceneTree
## Bake the 3D map's static layers (spec 2026-09-20 §2) — rivers, roads,
## trails, bridges — for every distinct step set in data/graphics_quality.csv,
## into <map3d_dir>/layers/. Run after build_world.gd (build_pack.sh does):
##   GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/bake_layers.gd [-- --map ID]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var repo := DataRepository.load_all("res://data")
	if repo == null:
		push_error("bake_layers: data failed to load: " + DataRepository.last_error)
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var at := args.find("--map")
	if at >= 0 and at + 1 < args.size() and not repo.load_map(args[at + 1]):
		push_error("bake_layers: no pack " + args[at + 1])
		quit(1)
		return
	var dir := repo.map3d_dir()
	var world := Map3DWorldLoader.instance(dir.path_join("world.tscn"))
	if world == null:
		push_error("bake_layers: no world at " + dir)
		quit(1)
		return
	# Terrain3D looks for a camera once it is in a tree; one it can find
	# keeps it from reporting none (the bake draws nothing).
	var cam := Camera3D.new()
	root.add_child(cam)
	root.add_child(world)
	await process_frame  # Terrain3D's data only exists in the tree
	var ctx := Map3DContext.new(repo, world.get_meta("map3d_world"), world)
	var done: Dictionary = {}
	var failed := false
	for tier: String in Map3DQuality.TIERS:
		var row := Map3DQuality.row(repo, tier)
		var set_name := Map3DLayerBake.step_set(row)
		if done.has(set_name):
			continue
		done[set_name] = true
		ctx.quality = row
		var rv := Map3DLayerRivers.arrays_for(ctx, dir)
		var rd := Map3DLayerRoads.plan_for(ctx, rv["courses"])
		var meshes := {"rivers": Map3DLayerBake.mesh_of(rv["arrays"]),
			"roads": Map3DLayerBake.mesh_of(rd["Roads"]), "trails": Map3DLayerBake.mesh_of(rd["Trails"]),
			"bridges": Map3DLayerRoads.bridge_mesh(ctx, rd["bridges"])}
		var err := Map3DLayerBake.save(dir, row, Map3DLayerBake.key(repo, dir, row), meshes)
		print("bake_layers: %s %s" % [set_name, "ok" if err == OK else "err %d" % err])
		failed = failed or err != OK
	world.queue_free()
	cam.queue_free()
	await process_frame
	quit(1 if failed else 0)  # build_pack.sh's set -e stops on a failed save
