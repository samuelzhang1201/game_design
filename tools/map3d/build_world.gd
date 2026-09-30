extends SceneTree
## Build assets/3D/terrain/<map>/world.tscn headless — no editor step.
##   python3 tools/map3d/bake_world.py
##   GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/build_world.gd [-- --map ID]
## (default: data/maps.csv's is_default pack)
## build_terrain.gd does the work: build_scene() packs the scene around an
## empty Terrain3D; its data only initialises inside a tree, so the scene is
## instanced under root, import_into() fills and saves the regions, and the
## filled scene is packed over the first one. Beside it goes manifest.json
## (format version, meta, build time, the bake tables' fingerprint), which
## Map3DWorldLoader.status reads to tell a current build from a stale one.
## The whole chain for one pack is tools/map3d/build_pack.sh.

const BuildTerrain := preload("res://tools/map3d/build_terrain.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			BuildTerrain.map_id = args[i + 1]
	print(BuildTerrain.build_scene())
	var path := BuildTerrain.root() + "/world.tscn"
	var scene: Node = (load(path) as PackedScene).instantiate()
	# Terrain3D stops its physics process without an active camera; the build
	# has none of its own, so one stands beside the scene and is never packed.
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	root.add_child(scene)
	var terrain := scene.get_node("Terrain3D") as Terrain3D
	terrain.set_camera(camera)
	await process_frame
	print(BuildTerrain.import_into(terrain))
	var packed := PackedScene.new()
	var err := packed.pack(scene)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("saved %s err=%d" % [path, err])
	if err == OK:
		err = _write_manifest(scene)
	scene.queue_free()
	camera.queue_free()
	await process_frame
	quit(0 if err == OK else 1)


## manifest.json beside world.tscn: what Map3DWorldLoader.status checks.
## (Time is fine here: a tool, not simulation code.)
func _write_manifest(scene: Node) -> Error:
	var mpath := BuildTerrain.root() + "/manifest.json"
	var manifest := {"format_version": Map3DWorldLoader.FORMAT_VERSION,
		"meta": scene.get_meta("map3d_world"),
		"built_at": Time.get_datetime_string_from_system(true),
		"steps_hash": Map3DWorldLoader.steps_hash()}
	var f := FileAccess.open(mpath, FileAccess.WRITE)
	if f == null:
		print("manifest %s err=%d" % [mpath, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("manifest %s" % mpath)
	return OK
